/**
 * Hint: متحكم إدارة الإجازات والأذونات والعطل الرسمية (الإصدار الثاني المعتمد)
 * يستبعد الأقسام غير المشمولة والموظفين المستثنين، ويربط العطل بحالة HOLIDAY
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { recalculateCommittedDayIfExists } = require('../attendance/attendanceEngine');

// 1. الإجازات
function listLeaves(req, res) {
  const { employeeId, year, month, department } = req.query;

  let query = `
    SELECT l.*, e.emp_code, e.name as employee_name, e.department
    FROM leaves l
    JOIN employees e ON e.id = l.employee_id
    WHERE e.status = 'نشط' 
      AND e.is_exempt = 0
      AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
  `;
  const params = [];

  if (employeeId) {
    query += ' AND l.employee_id = ?';
    params.push(employeeId);
  }

  if (department) {
    query += ' AND e.department = ?';
    params.push(department);
  }

  if (year && month) {
    const paddedMonth = String(month).padStart(2, '0');
    const prefix = `${year}-${paddedMonth}-%`;
    query += ' AND (l.start_date LIKE ? OR l.end_date LIKE ?)';
    params.push(prefix, prefix);
  } else if (year) {
    query += ' AND (l.start_date LIKE ? OR l.end_date LIKE ?)';
    params.push(`${year}%`, `${year}%`);
  }

  query += ' ORDER BY l.start_date DESC';

  const leaves = db.prepare(query).all(...params);
  return successResponse(res, leaves);
}

function createLeave(req, res) {
  const { employeeId, leaveType, startDate, endDate, hours, reason, approvedBy } = req.body;
  const user = req.user;

  if (!employeeId || !leaveType || !startDate || !endDate) {
    return errorResponse(res, 'الموظف، نوع الإجازة، وتاريخ البداية والنهاية حقول إلزامية', 400);
  }

  const emp = db.prepare('SELECT name, emp_code FROM employees WHERE id = ?').get(employeeId);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  const stmt = db.prepare(`
    INSERT INTO leaves (employee_id, leave_type, start_date, end_date, hours, reason, approved_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const result = stmt.run(
    employeeId,
    leaveType,
    startDate,
    endDate,
    hours || 0,
    reason || '',
    approvedBy || user.full_name
  );

  // تحديث سجل الحضور لتلك الفترة تلقائياً إن كانت مسجلة غياباً
  db.prepare(`
    UPDATE attendance_records 
    SET status = 'ON_LEAVE', notes = ?
    WHERE employee_id = ? AND date BETWEEN ? AND ? AND status = 'ABSENT'
  `).run(`إجازة ${leaveType}`, employeeId, startDate, endDate);

  logAction(
    user.id,
    user.full_name,
    'تسجيل إجازة',
    `تسجيل إجازة ${leaveType} للموظف [${emp.emp_code}] ${emp.name} من ${startDate} إلى ${endDate}`
  );

  return successResponse(res, { id: result.lastInsertRowid }, 'تم تسجيل الإجازة وتحديث حالة الحضور بنجاح', 201);
}

function deleteLeave(req, res) {
  const { id } = req.params;
  const user = req.user;

  const leave = db.prepare(`
    SELECT l.*, e.name as emp_name, e.emp_code
    FROM leaves l
    JOIN employees e ON e.id = l.employee_id
    WHERE l.id = ?
  `).get(id);

  if (!leave) {
    return errorResponse(res, 'الإجازة غير موجودة', 404);
  }

  db.prepare('DELETE FROM leaves WHERE id = ?').run(id);

  // Hint: إعادة احتساب الأيام المعتمدة الواقعة ضمن فترة الإجازة المحذوفة لتحديث حالة الموظف تلقائياً
  const affectedDays = db.prepare(`
    SELECT date FROM attendance_days 
    WHERE date BETWEEN ? AND ? AND status = 'COMMITTED'
  `).all(leave.start_date, leave.end_date);

  for (const d of affectedDays) {
    recalculateCommittedDayIfExists(d.date, user.id);
  }

  logAction(
    user.id,
    user.full_name,
    'حذف إجازة',
    `حذف إجازة ${leave.leave_type} للموظف [${leave.emp_code}] ${leave.emp_name} (${leave.start_date} إلى ${leave.end_date})`
  );

  return successResponse(res, null, 'تم حذف الإجازة بنجاح');
}

// 2. العطل والمناسبات الرسمية
function listHolidays(req, res) {
  const { year } = req.query;
  let query = 'SELECT * FROM official_holidays';
  const params = [];

  if (year) {
    query += ' WHERE year = ?';
    params.push(year);
  }

  query += ' ORDER BY date ASC';
  const holidays = db.prepare(query).all(...params);
  return successResponse(res, holidays);
}

function createHoliday(req, res) {
  const { date, title, year } = req.body;
  const user = req.user;

  if (!date || !title) {
    return errorResponse(res, 'تاريخ العطلة واسم المناسبة حقول إلزامية', 400);
  }

  const existing = db.prepare('SELECT id FROM official_holidays WHERE date = ?').get(date);
  if (existing) {
    return errorResponse(res, 'يوجد عطلة رسمية مسجلة بهذا التاريخ مسبقاً', 400);
  }

  const holidayYear = year || parseInt(date.split('-')[0], 10);
  const stmt = db.prepare(`
    INSERT INTO official_holidays (date, title, year)
    VALUES (?, ?, ?)
  `);

  const result = stmt.run(date, title.trim(), holidayYear);

  // تحديث سجلات الحضور لهذا اليوم إن كانت مسجلة غياباً إلى عطلة رسمية
  db.prepare(`
    UPDATE attendance_records 
    SET status = 'HOLIDAY', notes = ?
    WHERE date = ? AND status = 'ABSENT'
  `).run(`عطلة رسمية: ${title.trim()}`, date);

  logAction(user.id, user.full_name, 'إضافة عطلة رسمية', `إضافة عطلة رسمية [${title}] بتاريخ ${date}`);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم تسجيل العطلة الرسمية بنجاح', 201);
}

function deleteHoliday(req, res) {
  const { id } = req.params;
  const user = req.user;

  const holiday = db.prepare('SELECT * FROM official_holidays WHERE id = ?').get(id);
  if (!holiday) {
    return errorResponse(res, 'العطلة غير موجودة', 404);
  }

  db.prepare('DELETE FROM official_holidays WHERE id = ?').run(id);

  // Hint: إعادة احتساب اليوم إذا كان معتمداً مسبقاً لإرجاع حالة الحضور الفعلية بدلاً من HOLIDAY
  recalculateCommittedDayIfExists(holiday.date, user.id);

  logAction(user.id, user.full_name, 'حذف عطلة رسمية', `حذف العطلة [${holiday.title}] لتاريخ ${holiday.date}`);

  return successResponse(res, null, 'تم حذف العطلة الرسمية بنجاح');
}

module.exports = {
  listLeaves,
  createLeave,
  deleteLeave,
  listHolidays,
  createHoliday,
  deleteHoliday
};
