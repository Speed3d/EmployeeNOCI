/**
 * Hint: متحكم إدارة الموظفين والأقسام واستثناءات الـ VIP ونقل الموظفين (الإصدار الثاني المعتمد)
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { parseMasterEmployeesFile } = require('../../tools/excelHelper');
const { ROLES } = require('../../shared/constants');

function listEmployees(req, res) {
  const { search, department, status, isExempt } = req.query;

  let query = 'SELECT * FROM employees WHERE 1=1';
  const params = [];

  if (search) {
    query += ' AND (name LIKE ? OR emp_code LIKE ? OR phone LIKE ?)';
    const term = `%${search.trim()}%`;
    params.push(term, term, term);
  }

  if (department) {
    query += ' AND department = ?';
    params.push(department);
  }

  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }

  if (isExempt !== undefined) {
    query += ' AND is_exempt = ?';
    params.push(isExempt === 'true' || isExempt === '1' ? 1 : 0);
  }

  query += ' ORDER BY CAST(emp_code AS INTEGER) ASC, id ASC';

  const employees = db.prepare(query).all(...params);
  return successResponse(res, employees);
}

function getEmployee(req, res) {
  const { id } = req.params;
  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  // جلب آخر 30 حركة حضور
  const recentAttendance = db.prepare(`
    SELECT * FROM attendance_records 
    WHERE employee_id = ? 
    ORDER BY date DESC LIMIT 30
  `).all(id);

  // جلب إجازاته للسنة الحالية
  const leaves = db.prepare(`
    SELECT * FROM leaves 
    WHERE employee_id = ? 
    ORDER BY start_date DESC
  `).all(id);

  // جلب سجل تنقلات الموظف
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

function createEmployee(req, res) {
  const { empCode, name, department, status, isExempt, exemptReason, phone, address, hireDate, notes } = req.body;
  const user = req.user;

  if (!empCode || !name || !department) {
    return errorResponse(res, 'معرف الموظف، الاسم، والقسم حقول إلزامية', 400);
  }

  const existing = db.prepare('SELECT id FROM employees WHERE emp_code = ?').get(empCode.trim());
  if (existing) {
    return errorResponse(res, 'رقم المعرف مسجل مسبقاً لموظف آخر', 400);
  }

  const stmt = db.prepare(`
    INSERT INTO employees (emp_code, name, department, status, is_exempt, exempt_reason, phone, address, hire_date, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const result = stmt.run(
    empCode.trim(),
    name.trim(),
    department.trim(),
    status || 'نشط',
    isExempt ? 1 : 0,
    exemptReason || '',
    phone || '',
    address || '',
    hireDate || '',
    notes || ''
  );

  db.prepare('INSERT OR IGNORE INTO departments (name) VALUES (?)').run(department.trim());

  logAction(user.id, user.full_name, 'إضافة موظف جديد', `إضافة الموظف [${empCode}] ${name} في قسم ${department}`);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إضافة الموظف بنجاح', 201);
}

function updateEmployee(req, res) {
  const { id } = req.params;
  const { empCode, name, department, status, isExempt, exemptReason, phone, address, hireDate, notes } = req.body;
  const user = req.user;

  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  if (empCode && empCode.trim() !== emp.emp_code) {
    const existing = db.prepare('SELECT id FROM employees WHERE emp_code = ? AND id != ?').get(empCode.trim(), id);
    if (existing) {
      return errorResponse(res, 'رقم المعرف الجديد مسجل مسبقاً لموظف آخر', 400);
    }
  }

  const stmt = db.prepare(`
    UPDATE employees SET
      emp_code = ?,
      name = ?,
      department = ?,
      status = ?,
      is_exempt = ?,
      exempt_reason = ?,
      phone = ?,
      address = ?,
      hire_date = ?,
      notes = ?
    WHERE id = ?
  `);

  stmt.run(
    empCode ? empCode.trim() : emp.emp_code,
    name ? name.trim() : emp.name,
    department ? department.trim() : emp.department,
    status || emp.status,
    isExempt !== undefined ? (isExempt ? 1 : 0) : emp.is_exempt,
    exemptReason !== undefined ? exemptReason : emp.exempt_reason,
    phone !== undefined ? phone : emp.phone,
    address !== undefined ? address : emp.address,
    hireDate !== undefined ? hireDate : emp.hire_date,
    notes !== undefined ? notes : emp.notes,
    id
  );

  logAction(user.id, user.full_name, 'تعديل موظف', `تعديل بيانات الموظف [${emp.emp_code}] ${emp.name}`);

  return successResponse(res, null, 'تم تحديث بيانات الموظف بنجاح');
}

/**
 * نقل موظف من قسم إلى آخر مع تسجيل ذلك في سجل التنقلات (النقطة 16)
 */
function transferEmployee(req, res) {
  const { id } = req.params;
  const { newDepartment, reason } = req.body;
  const user = req.user;

  if (!newDepartment || !newDepartment.trim()) {
    return errorResponse(res, 'يرجى تحديد القسم الجديد المراد النقل إليه', 400);
  }

  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const fromDept = emp.department;
  const toDept = newDepartment.trim();

  if (fromDept === toDept) {
    return errorResponse(res, 'الموظف موجود بالفعل في هذا القسم', 400);
  }

  // التأكد من وجود القسم الجديد في جدول الأقسام
  db.prepare('INSERT OR IGNORE INTO departments (name) VALUES (?)').run(toDept);

  // تحديث قسم الموظف وإضافة السجل في employee_transfers
  const updateEmpStmt = db.prepare('UPDATE employees SET department = ? WHERE id = ?');
  const insertTransferStmt = db.prepare(`
    INSERT INTO employee_transfers (employee_id, from_department, to_department, transferred_by, reason)
    VALUES (?, ?, ?, ?, ?)
  `);

  const tx = db.transaction(() => {
    updateEmpStmt.run(toDept, id);
    insertTransferStmt.run(id, fromDept, toDept, user.id, reason || '');
  });

  tx();

  logAction(
    user.id,
    user.full_name,
    'نقل موظف بين الأقسام',
    `نقل الموظف [${emp.emp_code}] ${emp.name} من [${fromDept}] إلى [${toDept}]` + (reason ? ` - السبب: ${reason}` : '')
  );

  return successResponse(res, {
    employeeId: id,
    fromDepartment: fromDept,
    toDepartment: toDept
  }, `تم نقل الموظف إلى قسم ${toDept} بنجاح وتسجيل النقل في الأرشيف`);
}

function deleteEmployee(req, res) {
  const { id } = req.params;
  const user = req.user;

  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  db.prepare('DELETE FROM employees WHERE id = ?').run(id);

  logAction(user.id, user.full_name, 'حذف موظف', `حذف الموظف [${emp.emp_code}] ${emp.name} من قسم ${emp.department}`);

  return successResponse(res, null, 'تم حذف الموظف بنجاح');
}

function toggleVipExempt(req, res) {
  const { id } = req.params;
  const { isExempt, reason } = req.body;
  const user = req.user;

  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const newExemptVal = isExempt ? 1 : 0;
  db.prepare('UPDATE employees SET is_exempt = ?, exempt_reason = ? WHERE id = ?')
    .run(newExemptVal, reason || '', id);

  const actionText = newExemptVal === 1 ? 'منح استثناء VIP' : 'إلغاء استثناء VIP';
  logAction(user.id, user.full_name, actionText, `${actionText} للموظف [${emp.emp_code}] ${emp.name} (السبب: ${reason || 'بدون'})`);

  return successResponse(res, { isExempt: newExemptVal, reason }, `تم ${actionText} بنجاح`);
}

function listDepartments(req, res) {
  const departments = db.prepare(`
    SELECT d.id, d.name, d.is_excluded, COUNT(e.id) as employee_count
    FROM departments d
    LEFT JOIN employees e ON e.department = d.name
    GROUP BY d.id
    ORDER BY d.name ASC
  `).all();

  return successResponse(res, departments);
}

function toggleDepartmentExclusion(req, res) {
  const { id } = req.params;
  const { isExcluded } = req.body;
  const user = req.user;

  // فحص الصلاحية: سوبر أدمن أو من يملك صلاحية إدارة الاستثناءات
  if (user.role !== ROLES.SUPER_ADMIN && user.can_manage_exclusions !== 1) {
    return errorResponse(res, 'ليس لديك الصلاحية لتعديل استثناءات الأقسام', 403);
  }

  const dept = db.prepare('SELECT * FROM departments WHERE id = ?').get(id);
  if (!dept) {
    return errorResponse(res, 'القسم غير موجود', 404);
  }

  const val = isExcluded ? 1 : 0;
  db.prepare('UPDATE departments SET is_excluded = ? WHERE id = ?').run(val, id);

  const action = val === 1 ? 'استبعاد قسم من الكشوفات' : 'إلغاء استبعاد قسم';
  logAction(user.id, user.full_name, action, `${action}: ${dept.name}`);

  return successResponse(res, { isExcluded: val }, `تم تحديث حالة استبعاد القسم بنجاح`);
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

  try {
    const list = parseMasterEmployeesFile(file.buffer);

    const upsertStmt = db.prepare(`
      INSERT INTO employees (emp_code, name, department, status, is_exempt, exempt_reason)
      VALUES (@empCode, @name, @department, @status, @isExempt, @exemptReason)
      ON CONFLICT(emp_code) DO UPDATE SET
        name = excluded.name,
        department = excluded.department,
        status = excluded.status,
        is_exempt = excluded.is_exempt,
        exempt_reason = excluded.exempt_reason
    `);

    const insertDeptStmt = db.prepare('INSERT OR IGNORE INTO departments (name) VALUES (?)');

    const tx = db.transaction(() => {
      for (const e of list) {
        insertDeptStmt.run(e.department);
        upsertStmt.run(e);
      }
    });

    tx();

    logAction(user.id, user.full_name, 'استيراد موظفين من إكسل', `استيراد/تحديث ${list.length} موظف من ملف [${file.originalname}]`);

    return successResponse(res, { count: list.length }, `تم استيراد وتحديث ${list.length} موظف بنجاح`);
  } catch (err) {
    console.error('خطأ في استيراد ملف الموظفين:', err);
    return errorResponse(res, `فشل في استيراد الملف: ${err.message}`, 500);
  }
}

module.exports = {
  listEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  transferEmployee,
  deleteEmployee,
  toggleVipExempt,
  listDepartments,
  toggleDepartmentExclusion,
  importEmployeesExcel
};
