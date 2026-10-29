/**
 * Hint: متحكم التقارير الشاملة الشهرية وتصدير ملفات الإكسل
 * 1. احتساب الأيام المعتمدة حصرياً (Committed Days Only)
 * 2. السجل المعتمد هو مصدر الحقيقة: لا يُفلتر بحالة الموظف الحالية، والقسم من لقطة يوم الاعتماد
 * 3. نقطة تصدير عامة مرنة تستقبل الصفوف والأعمدة وتنتج ملف xlsx حقيقي
 */
const xlsx = require('xlsx');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse } = require('../../shared/responseHelper');
const { toPositiveInt, isYmd, badRequest, asTrimmedString } = require('../../shared/validators');

const STATUS_LABELS_SQL = `
  CASE
    WHEN a.status = 'ON_TIME' THEN 'حضور نظامي'
    WHEN a.status = 'LATE' THEN 'تأخير بسيط'
    WHEN a.status = 'VERY_LATE' THEN 'تأخير كبير'
    WHEN a.status = 'EARLY_LEAVE' THEN 'انصراف مبكر'
    WHEN a.status = 'ABSENT' THEN 'غائب'
    WHEN a.status = 'ON_LEAVE' THEN 'مجاز'
    WHEN a.status = 'OFF_DAY' THEN 'يوم راحة'
    WHEN a.status = 'HOLIDAY' THEN 'عطلة رسمية'
    WHEN a.status = 'MISSED_PUNCH' THEN 'بصمة ناقصة'
    ELSE a.status
  END`;

/**
 * Hint: التحقق من السنة والشهر وإرجاع بادئة الشهر أو null
 */
function readMonth(query) {
  const year = toPositiveInt(query.year);
  const month = toPositiveInt(query.month);
  if (!year || year < 2000 || year > 2100 || !month || month > 12) return null;
  const paddedMonth = String(month).padStart(2, '0');
  return { year, month, paddedMonth, prefix: `${year}-${paddedMonth}-%` };
}

/**
 * Hint: الاستعلام الموحد للتقرير الشهري (يُستخدم في الشاشة والتصدير)
 */
function buildMonthlyRows(prefix, department) {
  let query = `
    SELECT
      e.id as employee_id, e.emp_code, e.name,
      COALESCE(MAX(a.department_snapshot), e.department) as department,
      e.status as emp_status,
      CASE WHEN e.deleted_at IS NOT NULL OR e.status != 'نشط' THEN 1 ELSE 0 END as currently_inactive,
      COUNT(CASE WHEN a.status IN ('ON_TIME', 'LATE', 'VERY_LATE', 'EARLY_LEAVE') THEN 1 END) as days_present,
      COUNT(CASE WHEN a.status = 'ON_TIME' THEN 1 END) as days_on_time,
      COUNT(CASE WHEN a.status = 'LATE' THEN 1 END) as days_late,
      COUNT(CASE WHEN a.status = 'VERY_LATE' THEN 1 END) as days_very_late,
      COUNT(CASE WHEN a.status = 'EARLY_LEAVE' THEN 1 END) as days_early_leave,
      COUNT(CASE WHEN a.status = 'MISSED_PUNCH' THEN 1 END) as days_missed_punch,
      SUM(COALESCE(a.late_minutes, 0)) as total_late_minutes,
      SUM(COALESCE(a.early_leave_minutes, 0)) as total_early_leave_minutes,
      SUM(COALESCE(a.early_bonus_minutes, 0)) as total_early_bonus_minutes,
      SUM(COALESCE(a.overtime_minutes, 0)) as total_overtime_minutes,
      COUNT(CASE WHEN a.status = 'ABSENT' THEN 1 END) as days_absent,
      COUNT(CASE WHEN a.status = 'ON_LEAVE' THEN 1 END) as days_on_leave,
      COUNT(CASE WHEN a.status = 'OFF_DAY' THEN 1 END) as days_off,
      COUNT(CASE WHEN a.status = 'HOLIDAY' THEN 1 END) as days_holiday
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date LIKE ?
      AND a.date IN (SELECT date FROM attendance_days WHERE status = 'COMMITTED')
  `;
  const params = [prefix];

  if (department) {
    query += ' AND COALESCE(a.department_snapshot, e.department) = ?';
    params.push(String(department));
  }

  query += ' GROUP BY e.id ORDER BY CAST(e.emp_code AS INTEGER) ASC';
  return db.prepare(query).all(...params);
}

/**
 * تقرير الكشف التراكمي الشهري للموظفين (الأيام المعتمدة فقط)
 */
function getMonthlyTimesheet(req, res) {
  const m = readMonth(req.query);
  if (!m) {
    return badRequest(res, 'يرجى تحديد سنة وشهر صالحين (مثال: year=2026&month=10)');
  }

  const committedDays = db.prepare(`
    SELECT date FROM attendance_days
    WHERE date LIKE ? AND status = 'COMMITTED'
    ORDER BY date ASC
  `).all(m.prefix).map(d => d.date);

  const report = buildMonthlyRows(m.prefix, req.query.department);

  return successResponse(res, {
    year: m.year,
    month: m.month,
    committedDaysCount: committedDays.length,
    committedDays,
    totalEmployees: report.length,
    report
  });
}

/**
 * Hint: اسم ورقة إكسل صالح: بلا الأحرف الممنوعة وبحد أقصى 31 حرفاً
 */
function safeSheetName(name) {
  const cleaned = String(name || 'تقرير').replace(/[[\]:*?/\\]/g, ' ').trim();
  return (cleaned || 'تقرير').slice(0, 31);
}

/**
 * Hint: ترويسة تنزيل تدعم الأسماء العربية (RFC 5987)
 */
function setDownloadHeaders(res, fileName) {
  const asciiFallback = fileName.replace(/[^\x20-\x7E]/g, '_').replace(/"/g, '');
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="${asciiFallback}"; filename*=UTF-8''${encodeURIComponent(fileName)}`);
}

function sendWorkbook(res, sheetName, ws, fileName) {
  ws['!views'] = [{ rightToLeft: true }];
  const wb = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(wb, ws, safeSheetName(sheetName));
  const buffer = xlsx.write(wb, { type: 'buffer', bookType: 'xlsx' });
  setDownloadHeaders(res, fileName);
  return res.send(buffer);
}

/**
 * تصدير ملف إكسل عام مرن
 */
function exportGenericExcel(req, res) {
  const { headers = [], rows = [] } = req.body;
  const user = req.user;
  const title = asTrimmedString(req.body.title, 200) || 'تقرير';
  const fileName = (asTrimmedString(req.body.fileName, 120) || 'Report').replace(/[\\/:*?"<>|]/g, '_');

  if (!Array.isArray(headers) || !Array.isArray(rows) || rows.some(r => !Array.isArray(r))) {
    return badRequest(res, 'صيغة بيانات التصدير غير صالحة');
  }
  if (rows.length > 50000) {
    return badRequest(res, 'عدد الصفوف أكبر من الحد المسموح للتصدير');
  }

  logAction(user.id, user.full_name, 'تصدير إكسل', `تصدير ملف [${fileName}] (${rows.length} صف)`, req.clientIp);
  return sendWorkbook(res, title, xlsx.utils.aoa_to_sheet([headers, ...rows]), `${fileName}.xlsx`);
}

/**
 * تصدير كشف الحضور اليومي المعتمد
 */
function exportDailyExcel(req, res) {
  const { date, department, status } = req.query;
  const user = req.user;

  if (!isYmd(date)) {
    return badRequest(res, 'يرجى تحديد تاريخ صالح للتصدير');
  }

  let query = `
    SELECT
      e.emp_code as 'المعرف',
      e.name as 'الاسم',
      COALESCE(a.department_snapshot, e.department) as 'القسم',
      COALESCE(a.first_punch, '-') as 'وقت الحضور',
      COALESCE(a.last_punch, '-') as 'وقت الانصراف',
      ${STATUS_LABELS_SQL} as 'الحالة',
      COALESCE(a.late_minutes, 0) as 'دقائق التأخير',
      COALESCE(a.early_leave_minutes, 0) as 'دقائق الانصراف المبكر',
      COALESCE(a.early_bonus_minutes, 0) as 'مكافأة الحضور المبكر (د)',
      COALESCE(a.overtime_minutes, 0) as 'الدوام الإضافي (د)',
      COALESCE(a.notes, '') as 'الملاحظات'
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ?
  `;
  const params = [date];

  if (department) {
    query += ' AND COALESCE(a.department_snapshot, e.department) = ?';
    params.push(String(department));
  }

  if (status) {
    query += ' AND a.status = ?';
    params.push(String(status));
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const rows = db.prepare(query).all(...params);

  logAction(user.id, user.full_name, 'تصدير كشف إكسل يومي', `تصدير كشف ${date} (${rows.length} موظف)`, req.clientIp);
  return sendWorkbook(res, `كشف ${date}`, xlsx.utils.json_to_sheet(rows), `Attendance_${date}.xlsx`);
}

/**
 * Hint: تصدير التقرير التراكمي الشهري كملف Excel
 */
function exportMonthlyExcel(req, res) {
  const user = req.user;
  const m = readMonth(req.query);
  if (!m) {
    return badRequest(res, 'يرجى تحديد سنة وشهر صالحين للتصدير');
  }

  const rows = buildMonthlyRows(m.prefix, req.query.department).map(r => ({
    'المعرف': r.emp_code,
    'الاسم': r.name,
    'القسم': r.department,
    'ملاحظة': r.currently_inactive ? 'غير نشط حالياً' : '',
    'أيام الحضور': r.days_present,
    'حضور نظامي': r.days_on_time,
    'تأخير بسيط': r.days_late,
    'تأخير كبير': r.days_very_late,
    'انصراف مبكر (أيام)': r.days_early_leave,
    'بصمة ناقصة (أيام)': r.days_missed_punch,
    'مجموع التأخير (دقيقة)': r.total_late_minutes,
    'الانصراف المبكر (دقيقة)': r.total_early_leave_minutes,
    'مكافأة التبكير (دقيقة)': r.total_early_bonus_minutes,
    'الدوام الإضافي (دقيقة)': r.total_overtime_minutes,
    'أيام الغياب': r.days_absent,
    'أيام الإجازات': r.days_on_leave,
    'أيام الراحة (Off)': r.days_off,
    'أيام العطل الرسمية': r.days_holiday
  }));

  logAction(user.id, user.full_name, 'تصدير التقرير الشهري إكسل', `تصدير التقرير الشهري ${m.year}-${m.paddedMonth} (${rows.length} موظف)`, req.clientIp);
  return sendWorkbook(res, `تقرير ${m.year}-${m.paddedMonth}`, xlsx.utils.json_to_sheet(rows), `Monthly_Report_${m.year}_${m.paddedMonth}.xlsx`);
}

module.exports = {
  getMonthlyTimesheet,
  exportGenericExcel,
  exportDailyExcel,
  exportMonthlyExcel
};
