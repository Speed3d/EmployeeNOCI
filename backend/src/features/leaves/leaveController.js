/**
 * Hint: متحكم إدارة الإجازات والأذونات والعطل الرسمية
 * أي تغيير في الإجازات أو العطل يعيد احتساب الأيام المعتمدة المتأثرة عبر المحرك نفسه لضمان نتيجة موحدة
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { LEAVE_TYPES } = require('../../shared/constants');
const { recalculateCommittedRange } = require('../attendance/attendanceEngine');
const { isYmd, isHHMM, toPositiveInt, asTrimmedString, badRequest } = require('../../shared/validators');
const { timeToMinutes } = require('../../tools/timeUtils');

const VALID_LEAVE_TYPES = new Set(Object.values(LEAVE_TYPES));

function lastDayOfMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

// 1. الإجازات
function listLeaves(req, res) {
  const { employeeId, year, month, department } = req.query;

  let query = `
    SELECT l.*, e.emp_code, e.name as employee_name, e.department, e.status as employee_status
    FROM leaves l
    JOIN employees e ON e.id = l.employee_id
    WHERE e.deleted_at IS NULL
  `;
  const params = [];

  if (employeeId) {
    const id = toPositiveInt(employeeId);
    if (!id) return badRequest(res, 'معرف الموظف غير صالح');
    query += ' AND l.employee_id = ?';
    params.push(id);
  }

  if (department) {
    query += ' AND e.department = ?';
    params.push(String(department));
  }

  // Hint: فلترة الفترة بالتداخل حتى تظهر الإجازة الممتدة عبر عدة أشهر في كل شهر تغطيه
  if (year) {
    const y = toPositiveInt(year);
    if (!y || y < 2000 || y > 2100) return badRequest(res, 'السنة غير صالحة');
    let from = `${y}-01-01`;
    let to = `${y}-12-31`;
    if (month) {
      const m = toPositiveInt(month);
      if (!m || m > 12) return badRequest(res, 'الشهر غير صالح');
      const mm = String(m).padStart(2, '0');
      from = `${y}-${mm}-01`;
      to = `${y}-${mm}-${String(lastDayOfMonth(y, m)).padStart(2, '0')}`;
    }
    query += ' AND l.start_date <= ? AND l.end_date >= ?';
    params.push(to, from);
  }

  query += ' ORDER BY l.start_date DESC';

  const leaves = db.prepare(query).all(...params);
  return successResponse(res, leaves);
}

function createLeave(req, res) {
  const { leaveType, startDate, startTime, endTime, approvedBy } = req.body;
  let { endDate } = req.body;
  const user = req.user;

  const employeeId = toPositiveInt(req.body.employeeId);
  if (!employeeId || !leaveType || !isYmd(startDate)) {
    return badRequest(res, 'الموظف، نوع الإجازة، وتاريخ البداية حقول إلزامية بصيغة صحيحة');
  }
  if (!VALID_LEAVE_TYPES.has(leaveType)) {
    return badRequest(res, 'نوع الإجازة غير معروف');
  }

  const isHourly = leaveType === LEAVE_TYPES.HOURLY;
  let hours = 0;

  if (isHourly) {
    // Hint: الإذن الساعي ليوم واحد فقط وبوقت بداية ونهاية
    if (endDate === undefined || endDate === null || endDate === '') endDate = startDate;
    if (endDate !== startDate) {
      return badRequest(res, 'الإذن الساعي يجب أن يكون في يوم واحد');
    }
    if (!isHHMM(startTime) || !isHHMM(endTime)) {
      return badRequest(res, 'يرجى تحديد وقت بداية ونهاية الإذن الساعي بصيغة HH:MM');
    }
    const minutes = timeToMinutes(endTime) - timeToMinutes(startTime);
    if (minutes <= 0) {
      return badRequest(res, 'وقت نهاية الإذن يجب أن يكون بعد وقت بدايته');
    }
    hours = Math.round((minutes / 60) * 100) / 100;
  } else {
    if (!isYmd(endDate)) {
      return badRequest(res, 'تاريخ نهاية الإجازة إلزامي بصيغة صحيحة');
    }
    if (endDate < startDate) {
      return badRequest(res, 'تاريخ نهاية الإجازة يجب ألا يسبق تاريخ بدايتها');
    }
  }

  const reason = req.body.reason === undefined ? '' : asTrimmedString(req.body.reason, 500);
  if (reason === null) {
    return badRequest(res, 'سبب الإجازة غير صالح أو طويل جداً');
  }

  const emp = db.prepare('SELECT name, emp_code FROM employees WHERE id = ? AND deleted_at IS NULL').get(employeeId);
  if (!emp) {
    return errorResponse(res, 'الموظف غير موجود', 404);
  }

  // Hint: منع تداخل إجازتين كاملتين لنفس الموظف
  if (!isHourly) {
    const overlap = db.prepare(`
      SELECT id, start_date, end_date FROM leaves
      WHERE employee_id = ? AND leave_type != ? AND start_date <= ? AND end_date >= ?
      LIMIT 1
    `).get(employeeId, LEAVE_TYPES.HOURLY, endDate, startDate);
    if (overlap) {
      return badRequest(res, `توجد إجازة مسجلة لهذا الموظف تتداخل مع الفترة (${overlap.start_date} إلى ${overlap.end_date})`);
    }
  }

  const result = db.prepare(`
    INSERT INTO leaves (employee_id, leave_type, start_date, end_date, hours, reason, approved_by, start_time, end_time)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    employeeId,
    leaveType,
    startDate,
    endDate,
    hours,
    reason,
    asTrimmedString(approvedBy, 120) || user.full_name,
    isHourly ? startTime : null,
    isHourly ? endTime : null
  );

  const recalculatedDays = recalculateCommittedRange(startDate, endDate, user.id);

  logAction(
    user.id,
    user.full_name,
    'تسجيل إجازة',
    `تسجيل إجازة ${leaveType} للموظف [${emp.emp_code}] ${emp.name} من ${startDate} إلى ${endDate}`
      + (isHourly ? ` (${startTime} - ${endTime})` : '')
      + (recalculatedDays ? ` وإعادة احتساب ${recalculatedDays} يوم معتمد` : ''),
    req.clientIp
  );

  return successResponse(res, { id: result.lastInsertRowid, recalculatedDays }, 'تم تسجيل الإجازة وتحديث الكشوفات المعتمدة المتأثرة بنجاح', 201);
}

function deleteLeave(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  const leave = id && db.prepare(`
    SELECT l.*, e.name as emp_name, e.emp_code
    FROM leaves l
    JOIN employees e ON e.id = l.employee_id
    WHERE l.id = ?
  `).get(id);

  if (!leave) {
    return errorResponse(res, 'الإجازة غير موجودة', 404);
  }

  db.prepare('DELETE FROM leaves WHERE id = ?').run(id);

  // Hint: إعادة احتساب الأيام المعتمدة الواقعة ضمن فترة الإجازة المحذوفة
  const recalculatedDays = recalculateCommittedRange(leave.start_date, leave.end_date, user.id);

  logAction(
    user.id,
    user.full_name,
    'حذف إجازة',
    `حذف إجازة ${leave.leave_type} للموظف [${leave.emp_code}] ${leave.emp_name} (${leave.start_date} إلى ${leave.end_date})`,
    req.clientIp
  );

  return successResponse(res, { recalculatedDays }, 'تم حذف الإجازة بنجاح');
}

// 2. العطل والمناسبات الرسمية
function listHolidays(req, res) {
  const { year } = req.query;
  let query = 'SELECT * FROM official_holidays';
  const params = [];

  if (year) {
    const y = toPositiveInt(year);
    if (!y) return badRequest(res, 'السنة غير صالحة');
    query += ' WHERE year = ?';
    params.push(y);
  }

  query += ' ORDER BY date ASC';
  const holidays = db.prepare(query).all(...params);
  return successResponse(res, holidays);
}

function createHoliday(req, res) {
  const { date } = req.body;
  const user = req.user;
  const title = asTrimmedString(req.body.title, 200);

  if (!isYmd(date) || !title) {
    return badRequest(res, 'تاريخ العطلة (YYYY-MM-DD) واسم المناسبة حقول إلزامية');
  }

  const existing = db.prepare('SELECT id FROM official_holidays WHERE date = ?').get(date);
  if (existing) {
    return badRequest(res, 'يوجد عطلة رسمية مسجلة بهذا التاريخ مسبقاً');
  }

  // Hint: السنة تُشتق من التاريخ دائماً
  const holidayYear = parseInt(date.slice(0, 4), 10);
  const result = db.prepare('INSERT INTO official_holidays (date, title, year) VALUES (?, ?, ?)').run(date, title, holidayYear);

  const recalculatedDays = recalculateCommittedRange(date, date, user.id);

  logAction(user.id, user.full_name, 'إضافة عطلة رسمية', `إضافة عطلة رسمية [${title}] بتاريخ ${date}`, req.clientIp);

  return successResponse(res, { id: result.lastInsertRowid, recalculatedDays }, 'تم تسجيل العطلة الرسمية بنجاح', 201);
}

function deleteHoliday(req, res) {
  const id = toPositiveInt(req.params.id);
  const user = req.user;

  const holiday = id && db.prepare('SELECT * FROM official_holidays WHERE id = ?').get(id);
  if (!holiday) {
    return errorResponse(res, 'العطلة غير موجودة', 404);
  }

  db.prepare('DELETE FROM official_holidays WHERE id = ?').run(id);

  // Hint: إعادة احتساب اليوم إذا كان معتمداً لإرجاع حالة الحضور الفعلية بدلاً من HOLIDAY
  const recalculatedDays = recalculateCommittedRange(holiday.date, holiday.date, user.id);

  logAction(user.id, user.full_name, 'حذف عطلة رسمية', `حذف العطلة [${holiday.title}] لتاريخ ${holiday.date}`, req.clientIp);

  return successResponse(res, { recalculatedDays }, 'تم حذف العطلة الرسمية بنجاح');
}

module.exports = {
  listLeaves,
  createLeave,
  deleteLeave,
  listHolidays,
  createHoliday,
  deleteHoliday
};
