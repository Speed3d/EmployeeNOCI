/**
 * Hint: متحكم إدارة الموظفين والأقسام واستثناءات الـ VIP ونقل الموظفين
 * الحذف ناعم (deleted_at) حتى يبقى تاريخ الحضور والإجازات محفوظاً، مع إمكانية الاستعادة
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { parseMasterEmployeesFile } = require('../../tools/excelHelper');
const { ROLES } = require('../../shared/constants');
const { getBaghdadDateStr } = require('../../tools/timeUtils');
const { asTrimmedString, asBool, toPositiveInt, isYmd, badRequest } = require('../../shared/validators');
const { EMPLOYEE_STATUSES, transferInTx, importEmployees } = require('./employeeService');

function listEmployees(req, res) {
  const { search, department, status, isExempt } = req.query;
  const includeDeleted = asBool(req.query.includeDeleted);
  // اعتماد توقيت بغداد لتطابق تاريخ الإجازات واليوم الحالي
  const today = getBaghdadDateStr();

  let query = `
    SELECT e.*,
      (SELECT 1 FROM leaves l
       WHERE l.employee_id = e.id
         AND ? BETWEEN l.start_date AND l.end_date
       LIMIT 1) as has_active_leave,
      (SELECT l.leave_type FROM leaves l
       WHERE l.employee_id = e.id
         AND ? BETWEEN l.start_date AND l.end_date
       LIMIT 1) as active_leave_type
    FROM employees e
    WHERE 1=1
  `;
  const params = [today, today];

  if (!includeDeleted) {
    query += ' AND e.deleted_at IS NULL';
  }

  if (search) {
    query += ' AND (e.name LIKE ? OR e.emp_code LIKE ? OR e.phone LIKE ?)';
    const term = `%${String(search).trim()}%`;
    params.push(term, term, term);
  }

  if (department) {
    query += ' AND e.department = ?';
    params.push(String(department));
  }

  if (status) {
    query += ' AND e.status = ?';
    params.push(String(status));
  }

  if (isExempt !== undefined) {
    query += ' AND e.is_exempt = ?';
    params.push(asBool(isExempt) ? 1 : 0);
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC, e.id ASC';

  const employees = db.prepare(query).all(...params);
  return successResponse(res, employees);
}

function getEmployee(req, res) {
  const id = toPositiveInt(req.params.id);
  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const recentAttendance = db.prepare(`
    SELECT * FROM attendance_records
    WHERE employee_id = ?
    ORDER BY date DESC LIMIT 30
  `).all(id);

  const leaves = db.prepare(`
    SELECT * FROM leaves
    WHERE employee_id = ?
    ORDER BY start_date DESC
  `).all(id);

  const transfers = db.prepare(`
    SELECT t.*, u.full_name as transferred_by_name
    FROM employee_transfers t
    LEFT JOIN users u ON u.id = t.transferred_by
    WHERE t.employee_id = ?
    ORDER BY t.created_at DESC
  `).all(id);

  return successResponse(res, {
    employee: emp,
    recentAttendance,
    leaves,
    transfers
  });
}

/**
 * Hint: التحقق من الحقول الاختيارية النصية للموظف وإرجاع رسالة الخطأ الأولى إن وجدت
 */
function readOptionalFields(body) {
  const out = {};
  const limits = { exemptReason: 255, phone: 40, address: 255, notes: 1000 };
  for (const [key, max] of Object.entries(limits)) {
    if (body[key] === undefined || body[key] === null) continue;
    const v = asTrimmedString(body[key], max);
    if (v === null) return { error: `قيمة الحقل ${key} غير صالحة أو طويلة جداً` };
    out[key] = v;
  }
  if (body.hireDate !== undefined && body.hireDate !== null && body.hireDate !== '') {
    if (!isYmd(body.hireDate)) return { error: 'تاريخ التعيين غير صالح (YYYY-MM-DD)' };
    out.hireDate = body.hireDate;
  } else if (body.hireDate === '') {
    out.hireDate = '';
  }
  if (body.status !== undefined && !EMPLOYEE_STATUSES.includes(body.status)) {
    return { error: 'حالة الموظف غير معروفة' };
  }
  return { fields: out };
}

function createEmployee(req, res) {
  const user = req.user;
  const empCode = asTrimmedString(req.body.empCode, 40);
  const name = asTrimmedString(req.body.name, 200);
  const department = asTrimmedString(req.body.department, 200);

  if (!empCode || !name || !department) {
    return badRequest(res, 'معرف الموظف، الاسم، والقسم حقول إلزامية');
  }

  const { error, fields } = readOptionalFields(req.body);
  if (error) return badRequest(res, error);

  const existing = db.prepare('SELECT id, deleted_at FROM employees WHERE emp_code = ?').get(empCode);
  if (existing) {
    return badRequest(res, existing.deleted_at
      ? 'هذا المعرف يخص موظفاً محذوفاً؛ يمكنك استعادته من قائمة المحذوفين بدلاً من إنشائه من جديد'
      : 'رقم المعرف مسجل مسبقاً لموظف آخر');
  }

  const result = db.prepare(`
    INSERT INTO employees (emp_code, name, department, status, is_exempt, exempt_reason, phone, address, hire_date, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    empCode,
    name,
    department,
    req.body.status || 'نشط',
    asBool(req.body.isExempt) ? 1 : 0,
    fields.exemptReason || '',
    fields.phone || '',
    fields.address || '',
    fields.hireDate || '',
    fields.notes || ''
  );

  db.prepare('INSERT OR IGNORE INTO departments (name) VALUES (?)').run(department);

  logAction(user.id, user.full_name, 'إضافة موظف جديد', `إضافة الموظف [${empCode}] ${name} في قسم ${department}`, req.clientIp);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إضافة الموظف بنجاح', 201);
}

function updateEmployee(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const { error, fields } = readOptionalFields(req.body);
  if (error) return badRequest(res, error);

  const empCode = req.body.empCode !== undefined ? asTrimmedString(req.body.empCode, 40) : emp.emp_code;
  const name = req.body.name !== undefined ? asTrimmedString(req.body.name, 200) : emp.name;
  const department = req.body.department !== undefined ? asTrimmedString(req.body.department, 200) : emp.department;
  if (!empCode || !name || !department) {
    return badRequest(res, 'معرف الموظف والاسم والقسم لا يمكن أن تكون فارغة');
  }

  if (empCode !== emp.emp_code) {
    const existing = db.prepare('SELECT id FROM employees WHERE emp_code = ? AND id != ?').get(empCode, id);
    if (existing) {
      return badRequest(res, 'رقم المعرف الجديد مسجل مسبقاً لموظف آخر');
    }
  }

  const departmentChanged = department !== emp.department;

  db.transaction(() => {
    // Hint: تغيير القسم من نافذة التعديل يُسجل في سجل التنقلات مثل النقل الصريح
    if (departmentChanged) {
      transferInTx(id, emp.department, department, user.id, 'تعديل بيانات الموظف');
    }

    db.prepare(`
      UPDATE employees SET
        emp_code = ?, name = ?, status = ?, is_exempt = ?, exempt_reason = ?,
        phone = ?, address = ?, hire_date = ?, notes = ?
      WHERE id = ?
    `).run(
      empCode,
      name,
      req.body.status || emp.status,
      req.body.isExempt !== undefined ? (asBool(req.body.isExempt) ? 1 : 0) : emp.is_exempt,
      fields.exemptReason !== undefined ? fields.exemptReason : emp.exempt_reason,
      fields.phone !== undefined ? fields.phone : emp.phone,
      fields.address !== undefined ? fields.address : emp.address,
      fields.hireDate !== undefined ? fields.hireDate : emp.hire_date,
      fields.notes !== undefined ? fields.notes : emp.notes,
      id
    );
  })();

  logAction(
    user.id,
    user.full_name,
    'تعديل موظف',
    `تعديل بيانات الموظف [${emp.emp_code}] ${emp.name}` + (departmentChanged ? ` (نقل من [${emp.department}] إلى [${department}])` : ''),
    req.clientIp
  );

  return successResponse(res, null, 'تم تحديث بيانات الموظف بنجاح');
}

/**
 * نقل موظف من قسم إلى آخر مع تسجيل ذلك في سجل التنقلات
 */
function transferEmployee(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;
  const toDept = asTrimmedString(req.body.newDepartment, 200);
  const reason = req.body.reason === undefined ? '' : asTrimmedString(req.body.reason, 500);

  if (!toDept) {
    return badRequest(res, 'يرجى تحديد القسم الجديد المراد النقل إليه');
  }
  if (reason === null) {
    return badRequest(res, 'سبب النقل غير صالح أو طويل جداً');
  }

  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const fromDept = emp.department;
  if (fromDept === toDept) {
    return badRequest(res, 'الموظف موجود بالفعل في هذا القسم');
  }

  db.transaction(() => transferInTx(id, fromDept, toDept, user.id, reason))();

  logAction(
    user.id,
    user.full_name,
    'نقل موظف بين الأقسام',
    `نقل الموظف [${emp.emp_code}] ${emp.name} من [${fromDept}] إلى [${toDept}]` + (reason ? ` - السبب: ${reason}` : ''),
    req.clientIp
  );

  return successResponse(res, {
    employeeId: id,
    fromDepartment: fromDept,
    toDepartment: toDept
  }, `تم نقل الموظف إلى قسم ${toDept} بنجاح وتسجيل النقل في الأرشيف`);
}

/**
 * Hint: حذف ناعم: يختفي الموظف من القوائم والكشوفات الجديدة، ويبقى تاريخه محفوظاً في التقارير
 */
function deleteEmployee(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  db.prepare("UPDATE employees SET deleted_at = datetime('now') WHERE id = ?").run(id);

  logAction(user.id, user.full_name, 'حذف موظف', `حذف (أرشفة) الموظف [${emp.emp_code}] ${emp.name} من قسم ${emp.department} مع الاحتفاظ بتاريخه`, req.clientIp);

  return successResponse(res, null, 'تم حذف الموظف مع الاحتفاظ بسجل حضوره وإجازاته، ويمكن استعادته لاحقاً');
}

function restoreEmployee(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ? AND deleted_at IS NOT NULL').get(id);
  if (!emp) {
    return errorResponse(res, 'لا يوجد موظف محذوف بهذا المعرف', 404);
  }

  db.prepare('UPDATE employees SET deleted_at = NULL WHERE id = ?').run(id);

  logAction(user.id, user.full_name, 'استعادة موظف', `استعادة الموظف [${emp.emp_code}] ${emp.name}`, req.clientIp);

  return successResponse(res, null, 'تمت استعادة الموظف بنجاح');
}

function toggleVipExempt(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;
  const reason = req.body.reason === undefined ? '' : asTrimmedString(req.body.reason, 255);
  if (reason === null) return badRequest(res, 'سبب الاستثناء غير صالح');

  const emp = id && db.prepare('SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const newExemptVal = asBool(req.body.isExempt) ? 1 : 0;
  db.prepare('UPDATE employees SET is_exempt = ?, exempt_reason = ? WHERE id = ?').run(newExemptVal, reason, id);

  const actionText = newExemptVal === 1 ? 'منح استثناء VIP' : 'إلغاء استثناء VIP';
  logAction(user.id, user.full_name, actionText, `${actionText} للموظف [${emp.emp_code}] ${emp.name} (السبب: ${reason || 'بدون'})`, req.clientIp);

  return successResponse(res, { isExempt: newExemptVal, reason }, `تم ${actionText} بنجاح`);
}

function listDepartments(req, res) {
  const departments = db.prepare(`
    SELECT d.id, d.name, d.is_excluded, COUNT(e.id) as employee_count
    FROM departments d
    LEFT JOIN employees e ON e.department = d.name AND e.deleted_at IS NULL
    GROUP BY d.id
    ORDER BY d.name ASC
  `).all();

  return successResponse(res, departments);
}

function toggleDepartmentExclusion(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  if (user.role !== ROLES.SUPER_ADMIN && user.can_manage_exclusions !== 1) {
    return errorResponse(res, 'ليس لديك الصلاحية لتعديل استثناءات الأقسام', 403);
  }

  const dept = id && db.prepare('SELECT * FROM departments WHERE id = ?').get(id);
  if (!dept) {
    return errorResponse(res, 'القسم غير موجود', 404);
  }

  const val = asBool(req.body.isExcluded) ? 1 : 0;
  db.prepare('UPDATE departments SET is_excluded = ? WHERE id = ?').run(val, id);

  const action = val === 1 ? 'استبعاد قسم من الكشوفات' : 'إلغاء استبعاد قسم';
  logAction(user.id, user.full_name, action, `${action}: ${dept.name}`, req.clientIp);

  return successResponse(res, { isExcluded: val }, 'تم تحديث حالة استبعاد القسم بنجاح');
}

/**
 * استيراد وتحديث الموظفين من ملف إكسل شامل (حصري للسوبر أدمن)
 */
function importEmployeesExcel(req, res) {
  const user = req.user;
  const file = req.file;

  if (!file) {
    return errorResponse(res, 'يرجى اختيار ملف الإكسل للاستيراد', 400);
  }

  const list = parseMasterEmployeesFile(file.buffer);
  const summary = importEmployees(list, { userId: user.id });

  logAction(
    user.id,
    user.full_name,
    'استيراد موظفين من إكسل',
    `استيراد من ملف [${file.originalname}]: مضاف ${summary.added}، محدّث ${summary.updated}، منقول ${summary.transferred}، بلا تغيير ${summary.unchanged}، غير موجود في الملف ${summary.missingFromFile.length}`,
    req.clientIp
  );

  return successResponse(res, { count: list.length, ...summary },
    `تمت معالجة ${list.length} موظف: ${summary.added} جديد، ${summary.updated} محدّث، ${summary.transferred} منقول`);
}

module.exports = {
  listEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  transferEmployee,
  deleteEmployee,
  restoreEmployee,
  toggleVipExempt,
  listDepartments,
  toggleDepartmentExclusion,
  importEmployeesExcel
};
