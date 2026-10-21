/**
 * Hint: متحكم التقارير الشاملة وتصدير ملفات الإكسل (Excel Reports)
 */
const xlsx = require('xlsx');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

/**
 * تقرير الكشف التراكمي الشهري للموظفين
 */
function getMonthlyTimesheet(req, res) {
  const { year, month, department } = req.query;

  if (!year || !month) {
    return errorResponse(res, 'يرجى تحديد السنة والشهر (مثال: year=2026&month=10)', 400);
  }

  const paddedMonth = String(month).padStart(2, '0');
  const monthPrefix = `${year}-${paddedMonth}-%`;

  let query = `
    SELECT 
      e.id as employee_id, e.emp_code, e.name, e.department, e.status as emp_status, e.is_exempt,
      COUNT(CASE WHEN a.status IN ('ON_TIME', 'LATE', 'VERY_LATE', 'EARLY_LEAVE') THEN 1 END) as days_present,
      COUNT(CASE WHEN a.status = 'ON_TIME' THEN 1 END) as days_on_time,
      COUNT(CASE WHEN a.status = 'LATE' THEN 1 END) as days_late,
      COUNT(CASE WHEN a.status = 'VERY_LATE' THEN 1 END) as days_very_late,
      SUM(COALESCE(a.late_minutes, 0)) as total_late_minutes,
      SUM(COALESCE(a.early_leave_minutes, 0)) as total_early_leave_minutes,
      SUM(COALESCE(a.early_bonus_minutes, 0)) as total_early_bonus_minutes,
      SUM(COALESCE(a.overtime_minutes, 0)) as total_overtime_minutes,
      COUNT(CASE WHEN a.status = 'ABSENT' THEN 1 END) as days_absent,
      COUNT(CASE WHEN a.status = 'ON_LEAVE' THEN 1 END) as days_on_leave,
      COUNT(CASE WHEN a.status = 'VIP_EXEMPT' THEN 1 END) as days_exempt
    FROM employees e
    LEFT JOIN attendance_records a ON a.employee_id = e.id AND a.date LIKE ?
    WHERE 1=1
  `;
  const params = [monthPrefix];

  if (department) {
    query += ' AND e.department = ?';
    params.push(department);
  }

  query += ' GROUP BY e.id ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const report = db.prepare(query).all(...params);

  return successResponse(res, {
    year: parseInt(year, 10),
    month: parseInt(month, 10),
    totalEmployees: report.length,
    report
  });
}

/**
 * تصدير كشف الحضور اليومي كملف Excel منسق
 */
function exportDailyExcel(req, res) {
  const { date, department, status, excludeDepts } = req.query;
  const user = req.user;

  if (!date) {
    return errorResponse(res, 'يرجى تحديد التاريخ المطلوب تصديره', 400);
  }

  let query = `
    SELECT 
      e.emp_code as 'المعرف',
      e.name as 'الاسم',
      e.department as 'القسم',
      COALESCE(a.first_punch, '-') as 'وقت الحضور',
      COALESCE(a.last_punch, '-') as 'وقت الانصراف',
      CASE 
        WHEN a.status = 'ON_TIME' THEN 'حضور نظامي'
        WHEN a.status = 'LATE' THEN 'تأخير بسيط'
        WHEN a.status = 'VERY_LATE' THEN 'تأخير كبير'
        WHEN a.status = 'EARLY_LEAVE' THEN 'انصراف مبكر'
        WHEN a.status = 'ABSENT' THEN 'غائب'
        WHEN a.status = 'ON_LEAVE' THEN 'مجاز'
        WHEN a.status = 'VIP_EXEMPT' THEN 'مستثنى VIP'
        WHEN a.status = 'DEPT_EXCLUDED' THEN 'قسم مستبعد'
        ELSE a.status
      END as 'الحالة',
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
    query += ' AND e.department = ?';
    params.push(department);
  }

  if (status) {
    query += ' AND a.status = ?';
    params.push(status);
  }

  if (excludeDepts) {
    const excludedList = Array.isArray(excludeDepts) ? excludeDepts : excludeDepts.split(',');
    const placeholders = excludedList.map(() => '?').join(',');
    query += ` AND e.department NOT IN (${placeholders})`;
    params.push(...excludedList);
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const rows = db.prepare(query).all(...params);

  // بناء مصنف إكسل عبر xlsx
  const wb = xlsx.utils.book_new();
  const ws = xlsx.utils.json_to_sheet(rows);

  // ضبط اتجاه الورقة من اليمين لليسار RTL
  ws['!views'] = [{ rightToLeft: true }];
  xlsx.utils.book_append_sheet(wb, ws, `كشف ${date}`);

  const buffer = xlsx.write(wb, { type: 'buffer', bookType: 'xlsx' });

  logAction(user.id, user.full_name, 'تصدير كشف إكسل', `تصدير كشف الحضور ليوم ${date} (${rows.length} سجل)`);

  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="Attendance_${date}.xlsx"`);
  return res.send(buffer);
}

module.exports = {
  getMonthlyTimesheet,
  exportDailyExcel
};
