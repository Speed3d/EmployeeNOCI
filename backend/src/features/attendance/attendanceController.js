/**
 * Hint: متحكم كشوفات البصمة، رفع الإكسل اليومي، واستعراض الإحصائيات
 */
const db = require('../../core/database');
const { parseDailyAttendanceFile } = require('../../tools/excelHelper');
const { processAttendanceForDay } = require('./attendanceEngine');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

/**
 * استيراد وتحليل ملف البصمة اليومي
 */
function uploadDailyAttendance(req, res) {
  const user = req.user;
  const file = req.file;

  if (!file) {
    return errorResponse(res, 'يرجى اختيار ملف الإكسل اليومي للبصمة', 400);
  }

  try {
    const parsed = parseDailyAttendanceFile(file.buffer);
    if (!parsed.detectedDate) {
      return errorResponse(res, 'لم يتم العثور على تاريخ صالح في ملف البصمة', 400);
    }

    const outcome = processAttendanceForDay(parsed.detectedDate, parsed.employees);

    logAction(
      user.id,
      user.full_name,
      'رفع كشف بصمة يومي',
      `رفع ملف [${file.originalname}] لتاريخ ${parsed.detectedDate} - إجمالي الموظفين الذين بصموا: ${parsed.uniqueEmployeesCount}`
    );

    return successResponse(res, {
      date: parsed.detectedDate,
      stats: outcome.stats,
      records: outcome.records
    }, `تم تحليل واعتماد كشف البصمة لتاريخ ${parsed.detectedDate} بنجاح`);
  } catch (err) {
    console.error('خطأ في معالجة ملف البصمة:', err);
    return errorResponse(res, `فشل في معالجة الملف: ${err.message}`, 500);
  }
}

/**
 * جلب كشف البصمة ليوم محدد مع الفلاتر والإحصائيات
 */
function getDailyAttendance(req, res) {
  let { date, department, status, search, excludeDepts } = req.query;

  // إذا لم يُحدد تاريخ، نأخذ آخر تاريخ مسجل
  if (!date) {
    const latest = db.prepare('SELECT date FROM attendance_records ORDER BY date DESC LIMIT 1').get();
    date = latest ? latest.date : new Date().toISOString().split('T')[0];
  }

  let query = `
    SELECT 
      a.id, a.date, a.first_punch, a.last_punch, a.punch_count,
      a.status, a.late_minutes, a.early_leave_minutes,
      a.early_bonus_minutes, a.overtime_minutes, a.notes, a.year,
      e.id as employee_id, e.emp_code, e.name, e.department, e.status as emp_status,
      e.is_exempt, e.exempt_reason, e.phone, e.avatar_url
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ?
  `;
  const params = [date];

  if (department) {
    query += ' AND e.department = ?';
    params.push(department);
  }

  if (status) {
    query += ' AND a.status = ?';
    params.push(status);
  }

  if (search) {
    query += ' AND (e.name LIKE ? OR e.emp_code LIKE ?)';
    const term = `%${search.trim()}%`;
    params.push(term, term);
  }

  // فلترة استبعاد الأقسام المحددة بالفلتر
  if (excludeDepts) {
    const excludedList = Array.isArray(excludeDepts) ? excludeDepts : excludeDepts.split(',');
    const placeholders = excludedList.map(() => '?').join(',');
    query += ` AND e.department NOT IN (${placeholders})`;
    params.push(...excludedList);
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const records = db.prepare(query).all(...params);

  // حساب الإحصائيات العامة لهذا اليوم (لكل الموظفين بغض النظر عن فلاتر البحث)
  const allDayRecords = db.prepare(`
    SELECT a.status, a.late_minutes, a.early_bonus_minutes, a.overtime_minutes
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ?
  `).all(date);

  const stats = {
    date,
    total: allDayRecords.length,
    present: allDayRecords.filter(r => ['ON_TIME', 'LATE', 'VERY_LATE', 'EARLY_LEAVE'].includes(r.status)).length,
    onTime: allDayRecords.filter(r => r.status === 'ON_TIME').length,
    late: allDayRecords.filter(r => r.status === 'LATE').length,
    veryLate: allDayRecords.filter(r => r.status === 'VERY_LATE').length,
    absent: allDayRecords.filter(r => r.status === 'ABSENT').length,
    onLeave: allDayRecords.filter(r => r.status === 'ON_LEAVE').length,
    vipExempt: allDayRecords.filter(r => r.status === 'VIP_EXEMPT').length,
    deptExcluded: allDayRecords.filter(r => r.status === 'DEPT_EXCLUDED').length
  };

  return successResponse(res, {
    date,
    stats,
    records
  });
}

/**
 * إعادة تشخيص واحتساب يوم مسجل (عند تعديل قواعد المكافأة أو إضافة إجازة)
 */
function recalculateDay(req, res) {
  const { date } = req.body;
  const user = req.user;

  if (!date) {
    return errorResponse(res, 'يرجى تحديد التاريخ المطلوب إعادة احتسابه', 400);
  }

  // جلب حركات البصمة المحفوظة مسبقاً لهذا اليوم
  const stored = db.prepare(`
    SELECT a.first_punch, a.last_punch, a.punch_count, a.punch_details, e.emp_code, e.name, e.department
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ? AND a.first_punch IS NOT NULL
  `).all(date);

  const punchList = stored.map(s => ({
    empCode: s.emp_code,
    name: s.name,
    department: s.department,
    firstPunch: s.first_punch,
    lastPunch: s.last_punch,
    punchCount: s.punch_count,
    allPunches: s.punch_details ? JSON.parse(s.punch_details) : [s.first_punch]
  }));

  const outcome = processAttendanceForDay(date, punchList);

  logAction(user.id, user.full_name, 'إعادة احتساب الحضور', `إعادة احتساب كشف الحضور لتاريخ ${date}`);

  return successResponse(res, {
    date,
    stats: outcome.stats,
    records: outcome.records
  }, `تمت إعادة احتساب يوم ${date} وفق القواعد المحدثة`);
}

module.exports = {
  uploadDailyAttendance,
  getDailyAttendance,
  recalculateDay
};
