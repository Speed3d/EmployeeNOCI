/**
 * Hint: متحكم إدارة الموظفين والأقسام واستثناءات الـ VIP
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

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

  return successResponse(res, {
    employee: emp,
    recentAttendance,
    leaves
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

  // التأكد من تسجيل القسم في جدول الأقسام
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

  // فحص عدم تكرار الكود مع موظف آخر
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

// Hint: تفعيل أو إلغاء استثناء الـ VIP لموظف معين
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

// Hint: قائمة الأقسام مع حالة الاستبعاد
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

// Hint: استبعاد أو تضمين قسم بالكامل في كشوفات البصمة
function toggleDepartmentExclusion(req, res) {
  const { id } = req.params;
  const { isExcluded } = req.body;
  const user = req.user;

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

module.exports = {
  listEmployees,
  getEmployee,
  createEmployee,
  updateEmployee,
  deleteEmployee,
  toggleVipExempt,
  listDepartments,
  toggleDepartmentExclusion
};
