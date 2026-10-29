/**
 * Hint: متحكم كشوفات البصمة، المعاينة، الاعتماد، والتحقق من حالة اليوم
 * المعاينة تُحفظ في الخادم، والاعتماد يتم بمعرف المعاينة فقط (لا تُقبل بصمات من العميل)
 */
const crypto = require('crypto');
const db = require('../../core/database');
const { parseDailyAttendanceFile } = require('../../tools/excelHelper');
const { processAttendanceForDay, recalculateCommittedDayIfExists, PRESENT_STATUSES } = require('./attendanceEngine');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { ROLES } = require('../../shared/constants');
const { getBaghdadDateStr } = require('../../tools/timeUtils');
const { isYmd, asBool, badRequest, asTrimmedString } = require('../../shared/validators');

const PREVIEW_TTL_SQL = "datetime('now', '-1 day')";

function canRecommit(user) {
  return user.role === ROLES.SUPER_ADMIN || user.can_recommit === 1;
}

function getDayInfo(date) {
  return db.prepare(`
    SELECT ad.*, u.full_name as committed_by_name
    FROM attendance_days ad
    LEFT JOIN users u ON u.id = ad.committed_by
    WHERE ad.date = ?
  `).get(date);
}

/**
 * 1. معاينة ملف البصمة (يوم أو عدة أيام) وحفظ النتيجة في الخادم بمعرف معاينة
 */
function previewAttendance(req, res) {
  const file = req.file;
  if (!file) {
    return errorResponse(res, 'يرجى اختيار ملف الإكسل اليومي للبصمة', 400);
  }

  const parsed = parseDailyAttendanceFile(file.buffer);
  const previewId = crypto.randomUUID();
  const sha256 = crypto.createHash('sha256').update(file.buffer).digest('hex');

  db.prepare(`DELETE FROM attendance_previews WHERE created_at < ${PREVIEW_TTL_SQL}`).run();
  db.prepare(`
    INSERT INTO attendance_previews (id, created_by, file_name, file_sha256, days_json)
    VALUES (?, ?, ?, ?, ?)
  `).run(previewId, req.user.id, String(file.originalname || '').slice(0, 255), sha256, JSON.stringify(parsed.days));

  const days = parsed.days.map(d => {
    const outcome = processAttendanceForDay(d.date, d.employees, { persist: false });
    const existing = getDayInfo(d.date);
    return {
      date: d.date,
      isCommitted: Boolean(existing && existing.status === 'COMMITTED'),
      committedAt: existing ? existing.committed_at : null,
      committedByName: existing ? existing.committed_by_name : null,
      stats: outcome.stats,
      records: outcome.records
    };
  });

  const first = days[0];
  const datesText = days.map(d => d.date).join('، ');
  return successResponse(res, {
    previewId,
    days,
    invalidRows: parsed.invalidRows,
    totalPunchRows: parsed.totalPunchRows,
    // Hint: حقول اليوم الأول للتوافق مع الواجهات التي تعرض يوماً واحداً
    date: first.date,
    isCommitted: first.isCommitted,
    committedAt: first.committedAt,
    stats: first.stats,
    records: first.records
  }, days.length > 1
    ? `تم اكتشاف ${days.length} أيام في الملف (${datesText})، يرجى معاينة واعتماد كل يوم على حدة`
    : `تمت معاينة وتحليل كشف البصمة لتاريخ ${first.date} بنجاح`);
}

/**
 * 2. اعتماد يوم من معاينة محفوظة في الخادم
 */
function commitAttendance(req, res) {
  const user = req.user;
  const { previewId, date } = req.body;

  if (req.body.punchList !== undefined) {
    return badRequest(res, 'لا يُقبل إرسال البصمات مباشرة؛ يجب الاعتماد من معاينة محفوظة في الخادم');
  }
  const cleanId = asTrimmedString(previewId, 64);
  if (!cleanId || !isYmd(date)) {
    return badRequest(res, 'يرجى تحديد معرف المعاينة وتاريخ صالح (YYYY-MM-DD)');
  }

  const preview = db.prepare(`SELECT * FROM attendance_previews WHERE id = ? AND created_at >= ${PREVIEW_TTL_SQL}`).get(cleanId);
  if (!preview) {
    return errorResponse(res, 'المعاينة غير موجودة أو انتهت صلاحيتها، يرجى رفع الملف مجدداً', 404);
  }
  if (preview.created_by !== user.id && user.role !== ROLES.SUPER_ADMIN) {
    return errorResponse(res, 'لا يمكنك اعتماد معاينة أنشأها مستخدم آخر', 403);
  }

  const day = JSON.parse(preview.days_json).find(d => d.date === date);
  if (!day) {
    return badRequest(res, `التاريخ ${date} غير موجود في هذا الملف`);
  }

  const existingDay = getDayInfo(date);
  if (existingDay && existingDay.status === 'COMMITTED' && !canRecommit(user)) {
    return errorResponse(res, 'تم اعتماد كشف هذا اليوم مسبقاً. إعادة الاعتماد محصورة بالسوبر أدمن أو من يملك صلاحية إعادة الاعتماد.', 403);
  }

  const outcome = processAttendanceForDay(date, day.employees, {
    persist: true,
    userId: user.id,
    rawPunchesJson: JSON.stringify(day.employees)
  });

  logAction(
    user.id,
    user.full_name,
    'اعتماد كشف بصمة يومي',
    `اعتماد كشف تاريخ ${date} (${outcome.records.length} موظف) من الملف [${preview.file_name}] sha256=${preview.file_sha256.slice(0, 16)}`
      + (existingDay ? ' [إعادة اعتماد]' : ''),
    req.clientIp
  );

  return successResponse(res, {
    date,
    isCommitted: true,
    stats: outcome.stats,
    records: outcome.records
  }, `تم حفظ واعتماد كشف البصمة ليوم ${date} بنجاح`);
}

/**
 * 3. فحص حالة يوم محدد
 */
function checkDayStatus(req, res) {
  const { date } = req.query;
  if (!isYmd(date)) {
    return badRequest(res, 'يرجى تحديد تاريخ صالح (YYYY-MM-DD)');
  }

  const day = getDayInfo(date);
  return successResponse(res, {
    date,
    isCommitted: Boolean(day && day.status === 'COMMITTED'),
    committedAt: day ? day.committed_at : null,
    committedByName: day ? day.committed_by_name : null,
    stats: day && day.stats_json ? JSON.parse(day.stats_json) : null
  });
}

/**
 * Hint: عدد الموظفين المشمولين بالكشوفات حالياً (لبطاقات لوحة المؤشرات)
 */
function countEligibleEmployees() {
  return db.prepare(`
    SELECT COUNT(*) as c FROM employees
    WHERE deleted_at IS NULL AND status = 'نشط' AND is_exempt = 0
      AND department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
  `).get().c;
}

/**
 * 4. جلب كشف البصمة اليومي المعتمد
 * Hint: السجل المعتمد هو مصدر الحقيقة؛ لا يُفلتر بحالة الموظف الحالية حتى لا يتغير التاريخ بأثر رجعي
 */
function getDailyAttendance(req, res) {
  let { date, department, status, search } = req.query;

  if (!date) {
    date = getBaghdadDateStr();
  }
  if (!isYmd(date)) {
    return badRequest(res, 'يرجى تحديد تاريخ صالح (YYYY-MM-DD)');
  }

  const committedDay = getDayInfo(date);

  let query = `
    SELECT
      a.id, a.date, a.department_snapshot, a.first_punch, a.last_punch, a.punch_count,
      a.status, a.late_minutes, a.early_leave_minutes,
      a.early_bonus_minutes, a.overtime_minutes, a.notes, a.year,
      e.id as employee_id, e.emp_code, e.name,
      COALESCE(a.department_snapshot, e.department) as department,
      e.status as emp_status, e.deleted_at as emp_deleted_at,
      e.phone, e.avatar_url
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

  if (search) {
    query += ' AND (e.name LIKE ? OR e.emp_code LIKE ?)';
    const term = `%${String(search).trim()}%`;
    params.push(term, term);
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const records = db.prepare(query).all(...params);
  const allDayRecords = db.prepare('SELECT status FROM attendance_records WHERE date = ?').all(date);

  const count = (pred) => allDayRecords.filter(pred).length;
  const stats = {
    date,
    total: allDayRecords.length,
    totalEmployees: allDayRecords.length,
    present: count(r => PRESENT_STATUSES.includes(r.status)),
    onTime: count(r => r.status === 'ON_TIME'),
    late: count(r => ['LATE', 'VERY_LATE'].includes(r.status)),
    absent: count(r => r.status === 'ABSENT'),
    onLeave: count(r => r.status === 'ON_LEAVE'),
    offDay: count(r => r.status === 'OFF_DAY'),
    holiday: count(r => r.status === 'HOLIDAY'),
    missedPunch: count(r => r.status === 'MISSED_PUNCH')
  };

  return successResponse(res, {
    date,
    isCommitted: Boolean(committedDay && committedDay.status === 'COMMITTED'),
    committedAt: committedDay ? committedDay.committed_at : null,
    committedByName: committedDay ? committedDay.committed_by_name : null,
    eligibleEmployees: countEligibleEmployees(),
    stats,
    records
  });
}

/**
 * 5. إعادة احتساب يوم معتمد من البصمات المحفوظة في الخادم
 * Hint: افتراضياً بنفس قواعد يوم الاعتماد، ومع useCurrentRules=true بالقواعد الحالية
 */
function recalculateDay(req, res) {
  const { date } = req.body;
  const user = req.user;
  const useCurrentRules = asBool(req.body.useCurrentRules);

  if (!isYmd(date)) {
    return badRequest(res, 'يرجى تحديد تاريخ صالح للإعادة (YYYY-MM-DD)');
  }

  if (!canRecommit(user)) {
    return errorResponse(res, 'إعادة احتساب واعتماد اليوم تتطلب صلاحية خاصة', 403);
  }

  const outcome = recalculateCommittedDayIfExists(date, user.id, { useCurrentRules });
  if (!outcome) {
    return errorResponse(res, 'هذا اليوم غير معتمد بعد، لا يوجد ما يُعاد احتسابه', 404);
  }

  logAction(
    user.id,
    user.full_name,
    'إعادة احتساب واعتماد الحضور',
    `إعادة احتساب كشف ${date} ${useCurrentRules ? 'بالقواعد الحالية' : 'بقواعد يوم الاعتماد'}`,
    req.clientIp
  );

  return successResponse(res, {
    date,
    isCommitted: true,
    stats: outcome.stats,
    records: outcome.records
  }, useCurrentRules
    ? `تمت إعادة احتساب يوم ${date} وفق القواعد الحالية`
    : `تمت إعادة احتساب يوم ${date} بنفس قواعد يوم الاعتماد`);
}

module.exports = {
  previewAttendance,
  commitAttendance,
  checkDayStatus,
  getDailyAttendance,
  recalculateDay,
  countEligibleEmployees
};
