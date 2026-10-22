/**
 * Hint: متحكم كشوفات البصمة، المعاينة، الاعتماد، والتحقق من حالة اليوم (الإصدار الثاني المعتمد)
 */
const db = require('../../core/database');
const { parseDailyAttendanceFile } = require('../../tools/excelHelper');
const { processAttendanceForDay } = require('./attendanceEngine');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { ROLES } = require('../../shared/constants');

/**
 * 1. معاينة كشف البصمة اليومي بدون حفظ في القاعدة (Preview)
 */
function previewAttendance(req, res) {
  const file = req.file;

  if (!file) {
    return errorResponse(res, 'يرجى اختيار ملف الإكسل اليومي للبصمة', 400);
  }

  try {
    const parsed = parseDailyAttendanceFile(file.buffer);
    if (!parsed.detectedDate) {
      return errorResponse(res, 'لم يتم العثور على تاريخ صالح في ملف البصمة', 400);
    }

    // تشغيل المحرك في وضع المعاينة فقط (persist = false)
    const outcome = processAttendanceForDay(parsed.detectedDate, parsed.employees, { persist: false });

    // فحص هل هذا اليوم معتمد مسبقاً في جدول attendance_days
    const existingDay = db.prepare('SELECT * FROM attendance_days WHERE date = ?').get(parsed.detectedDate);

    return successResponse(res, {
      date: parsed.detectedDate,
      isCommitted: Boolean(existingDay && existingDay.status === 'COMMITTED'),
      committedAt: existingDay ? existingDay.committed_at : null,
      stats: outcome.stats,
      records: outcome.records,
      rawPunches: parsed.employees
    }, `تمت معاينة وتحليل كشف البصمة لتاريخ ${parsed.detectedDate} بنجاح`);
  } catch (err) {
    console.error('خطأ في معاينة ملف البصمة:', err);
    return errorResponse(res, `فشل في قراءة ومعاينة الملف: ${err.message}`, 500);
  }
}

/**
 * 2. حفظ واعتماد كشف البصمة اليومي في قاعدة البيانات (Commit)
 */
function commitAttendance(req, res) {
  const user = req.user;
  const { date, punchList } = req.body;

  if (!date || !Array.isArray(punchList)) {
    return errorResponse(res, 'يرجى تزويد التاريخ وبيانات البصمات للاعتماد', 400);
  }

  // فحص هل اليوم معتمد مسبقاً
  const existingDay = db.prepare('SELECT * FROM attendance_days WHERE date = ?').get(date);
  if (existingDay && existingDay.status === 'COMMITTED') {
    // التحقق من صلاحية إعادة الاعتماد
    const hasPermission = user.role === ROLES.SUPER_ADMIN || user.can_recommit === 1;
    if (!hasPermission) {
      return errorResponse(res, 'تم اعتماد كشف هذا اليوم مسبقاً. إعادة الاعتماد محصورة بالسوبر أدمن أو من يملك صلاحية إعادة الاعتماد.', 403);
    }
  }

  try {
    // تشغيل المحرك وحفظ السجلات فعلياً في القاعدة (persist = true)
    const outcome = processAttendanceForDay(date, punchList, {
      persist: true,
      userId: user.id,
      rawPunchesJson: JSON.stringify(punchList)
    });

    logAction(
      user.id,
      user.full_name,
      'اعتماد كشف بصمة يومي',
      `اعتماد كشف تاريخ ${date} (${outcome.records.length} موظف)` + (existingDay ? ' [إعادة اعتماد]' : '')
    );

    return successResponse(res, {
      date,
      isCommitted: true,
      stats: outcome.stats,
      records: outcome.records
    }, `تم حفظ واعتماد كشف البصمة ليوم ${date} بنجاح`);
  } catch (err) {
    console.error('خطأ في اعتماد كشف البصمة:', err);
    return errorResponse(res, `فشل في اعتماد الكشف: ${err.message}`, 500);
  }
}

/**
 * 3. فحص حالة يوم محدد (هل هو معتمد مسبقاً أم لا)
 */
function checkDayStatus(req, res) {
  const { date } = req.query;
  if (!date) {
    return errorResponse(res, 'يرجى تحديد التاريخ', 400);
  }

  const day = db.prepare(`
    SELECT ad.*, u.full_name as committed_by_name
    FROM attendance_days ad
    LEFT JOIN users u ON u.id = ad.committed_by
    WHERE ad.date = ?
  `).get(date);

  return successResponse(res, {
    date,
    isCommitted: Boolean(day && day.status === 'COMMITTED'),
    committedAt: day ? day.committed_at : null,
    committedByName: day ? day.committed_by_name : null,
    stats: day && day.stats_json ? JSON.parse(day.stats_json) : null
  });
}

/**
 * 4. جلب كشف البصمة اليومي المحفوظ
 */
function getDailyAttendance(req, res) {
  let { date, department, status, search } = req.query;

  // التاريخ الافتراضي: تاريخ الحاسوب الحالي
  if (!date) {
    date = new Date().toISOString().split('T')[0];
  }

  // فحص حالة الاعتماد
  const committedDay = db.prepare(`
    SELECT ad.*, u.full_name as committed_by_name 
    FROM attendance_days ad
    LEFT JOIN users u ON u.id = ad.committed_by
    WHERE ad.date = ?
  `).get(date);

  let query = `
    SELECT 
      a.id, a.date, a.department_snapshot, a.first_punch, a.last_punch, a.punch_count,
      a.status, a.late_minutes, a.early_leave_minutes,
      a.early_bonus_minutes, a.overtime_minutes, a.notes, a.year,
      e.id as employee_id, e.emp_code, e.name, e.department, e.status as emp_status,
      e.phone, e.avatar_url
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ?
      AND e.status = 'نشط'
      AND e.is_exempt = 0
      AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
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

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const records = db.prepare(query).all(...params);

  // جلب إحصائيات اليوم العام من القاعدة
  const allDayRecords = db.prepare(`
    SELECT a.status
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ?
      AND e.status = 'نشط'
      AND e.is_exempt = 0
      AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
  `).all(date);

  const stats = {
    date,
    total: allDayRecords.length,
    present: allDayRecords.filter(r => ['ON_TIME', 'LATE', 'VERY_LATE', 'EARLY_LEAVE'].includes(r.status)).length,
    onTime: allDayRecords.filter(r => r.status === 'ON_TIME').length,
    late: allDayRecords.filter(r => ['LATE', 'VERY_LATE'].includes(r.status)).length,
    absent: allDayRecords.filter(r => r.status === 'ABSENT').length,
    onLeave: allDayRecords.filter(r => r.status === 'ON_LEAVE').length,
    offDay: allDayRecords.filter(r => r.status === 'OFF_DAY').length,
    holiday: allDayRecords.filter(r => r.status === 'HOLIDAY').length
  };

  return successResponse(res, {
    date,
    isCommitted: Boolean(committedDay && committedDay.status === 'COMMITTED'),
    committedAt: committedDay ? committedDay.committed_at : null,
    committedByName: committedDay ? committedDay.committed_by_name : null,
    stats,
    records
  });
}

/**
 * 5. إعادة تحليل واحتساب يوم معتمد من البصمات الخام المحفوظة
 */
function recalculateDay(req, res) {
  const { date } = req.body;
  const user = req.user;

  if (!date) {
    return errorResponse(res, 'يرجى تحديد التاريخ المطلوب إعادة احتسابه', 400);
  }

  // التحقق من الصلاحية
  if (user.role !== ROLES.SUPER_ADMIN && user.can_recommit !== 1) {
    return errorResponse(res, 'إعادة احتساب واعتماد اليوم تتطلب صلاحية خاصة', 403);
  }

  const day = db.prepare('SELECT * FROM attendance_days WHERE date = ?').get(date);
  let punchList = [];

  if (day && day.raw_punches_json) {
    punchList = JSON.parse(day.raw_punches_json);
  } else {
    // جلب حركات البصمة المحفوظة مسبقاً لهذا اليوم كخيار احتياطي
    const stored = db.prepare(`
      SELECT a.first_punch, a.last_punch, a.punch_count, a.punch_details, e.emp_code, e.name, e.department
      FROM attendance_records a
      JOIN employees e ON e.id = a.employee_id
      WHERE a.date = ? AND a.first_punch IS NOT NULL
    `).all(date);

    punchList = stored.map(s => ({
      empCode: s.emp_code,
      name: s.name,
      department: s.department,
      firstPunch: s.first_punch,
      lastPunch: s.last_punch,
      punchCount: s.punch_count,
      allPunches: s.punch_details ? JSON.parse(s.punch_details) : [s.first_punch]
    }));
  }

  const outcome = processAttendanceForDay(date, punchList, {
    persist: true,
    userId: user.id,
    rawPunchesJson: JSON.stringify(punchList)
  });

  logAction(user.id, user.full_name, 'إعادة احتساب واعتماد الحضور', `إعادة احتساب كشف الحضور لتاريخ ${date}`);

  return successResponse(res, {
    date,
    isCommitted: true,
    stats: outcome.stats,
    records: outcome.records
  }, `تمت إعادة احتساب واعتماد يوم ${date} وفق القواعد المحدثة`);
}

module.exports = {
  previewAttendance,
  commitAttendance,
  checkDayStatus,
  getDailyAttendance,
  recalculateDay
};
