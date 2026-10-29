/**
 * Hint: متحكم قوالب وجداول دوام الموظفين وأيام الراحة الأسبوعية (النقطة 17)
 * يدعم قوالب الشفتات، الجداول الثابتة والأسبوعية، ونسخ الأسبوع السابق
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { getBaghdadDateStr, getDayOfWeekFromYmd, addDaysYmd } = require('../../tools/timeUtils');
const { isYmd, isWorkDaysArray, asTrimmedString, toPositiveInt, badRequest } = require('../../shared/validators');

// Hint: استدعاء متأخر لتفادي الاعتماد الدائري مع محرك الحضور
function recalcRange(start, end, userId) {
  return require('../attendance/attendanceEngine').recalculateCommittedRange(start, end, userId);
}

/**
 * Hint: حساب يوم الأحد لبداية الأسبوع لأي تاريخ محدد دون تأثر بانحراف التوقيت العالمي UTC
 */
function getWeekSunday(dateStr) {
  const cleanDate = dateStr || getBaghdadDateStr();
  const day = getDayOfWeekFromYmd(cleanDate); // 0 = Sunday
  return addDaysYmd(cleanDate, -day);
}

/**
 * جلب جميع قوالب الدوام
 */
function listTemplates(req, res) {
  const templates = db.prepare('SELECT * FROM schedule_templates ORDER BY id ASC').all();
  const parsed = templates.map(t => ({
    ...t,
    workDays: JSON.parse(t.work_days_json)
  }));
  return successResponse(res, parsed);
}

/**
 * إنشاء قالب دوام جديد
 */
function createTemplate(req, res) {
  const { name, workDays } = req.body;
  const user = req.user;

  const cleanName = asTrimmedString(name, 120);
  if (!cleanName || !isWorkDaysArray(workDays)) {
    return badRequest(res, 'اسم القالب وقائمة أيام العمل (أرقام من 0 إلى 6) حقول إلزامية');
  }

  const stmt = db.prepare('INSERT INTO schedule_templates (name, work_days_json) VALUES (?, ?)');
  const result = stmt.run(cleanName, JSON.stringify([...workDays].sort()));

  logAction(user.id, user.full_name, 'إنشاء قالب دوام', `إنشاء القالب [${name}] بأيام العمل: ${workDays.join(',')}`);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إنشاء قالب الدوام بنجاح', 201);
}

/**
 * تعديل قالب دوام
 */
function updateTemplate(req, res) {
  const { id } = req.params;
  const { name, workDays } = req.body;
  const user = req.user;

  const template = db.prepare('SELECT * FROM schedule_templates WHERE id = ?').get(id);
  if (!template) {
    return errorResponse(res, 'القالب غير موجود', 404);
  }

  if (workDays !== undefined && !isWorkDaysArray(workDays)) {
    return badRequest(res, 'أيام العمل يجب أن تكون أرقاماً من 0 إلى 6 دون تكرار');
  }
  if (name !== undefined && !asTrimmedString(name, 120)) {
    return badRequest(res, 'اسم القالب غير صالح');
  }

  // Hint: تعديل القالب لا يغير الجداول المعيّنة مسبقاً لأنها تحفظ نسخة من الأيام لحظة التعيين
  const updatedName = name !== undefined ? asTrimmedString(name, 120) : template.name;
  const updatedWorkDays = workDays !== undefined ? JSON.stringify([...workDays].sort()) : template.work_days_json;

  db.prepare('UPDATE schedule_templates SET name = ?, work_days_json = ? WHERE id = ?').run(updatedName, updatedWorkDays, id);

  logAction(user.id, user.full_name, 'تعديل قالب دوام', `تعديل القالب [${updatedName}]`);

  return successResponse(res, null, 'تم تعديل قالب الدوام بنجاح');
}

/**
 * حذف قالب دوام
 */
function deleteTemplate(req, res) {
  const { id } = req.params;
  const user = req.user;

  const template = db.prepare('SELECT * FROM schedule_templates WHERE id = ?').get(id);
  if (!template) {
    return errorResponse(res, 'القالب غير موجود', 404);
  }

  db.prepare('DELETE FROM schedule_templates WHERE id = ?').run(id);

  logAction(user.id, user.full_name, 'حذف قالب دوام', `حذف القالب [${template.name}]`);

  return successResponse(res, null, 'تم حذف قالب الدوام بنجاح');
}

/**
 * استعراض جداول الدوام لأسبوع محدد مع ربطها بالموظفين
 */
function getAssignments(req, res) {
  let { weekStartDate, department } = req.query;

  if (weekStartDate !== undefined && !isYmd(weekStartDate)) {
    return badRequest(res, 'تاريخ بداية الأسبوع غير صالح');
  }
  weekStartDate = getWeekSunday(weekStartDate || getBaghdadDateStr());

  // جلب كافة الموظفين النشطين وغير المستبعدين
  let query = `
    SELECT 
      e.id as employee_id, e.emp_code, e.name, e.department,
      ws.id as weekly_sched_id, ws.template_id as weekly_template_id, ws.work_days_json as weekly_work_days,
      fs.id as fixed_sched_id, fs.template_id as fixed_template_id, fs.work_days_json as fixed_work_days
    FROM employees e
    LEFT JOIN employee_schedules ws ON ws.employee_id = e.id AND ws.schedule_type = 'WEEKLY' AND ws.week_start_date = ?
    LEFT JOIN employee_schedules fs ON fs.employee_id = e.id AND fs.schedule_type = 'FIXED'
    WHERE e.status = 'نشط' 
      AND e.is_exempt = 0
      AND e.deleted_at IS NULL
      AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
  `;
  const params = [weekStartDate];

  if (department) {
    query += ' AND e.department = ?';
    params.push(department);
  }

  query += ' ORDER BY CAST(e.emp_code AS INTEGER) ASC';

  const rows = db.prepare(query).all(...params);

  // جلب كافة القوالب
  const templates = db.prepare('SELECT * FROM schedule_templates').all();
  const templateMap = new Map();
  for (const t of templates) {
    templateMap.set(t.id, { id: t.id, name: t.name, workDays: JSON.parse(t.work_days_json) });
  }

  const defaultWorkDays = [0, 1, 2, 3, 4]; // أحد إلى خميس

  const result = rows.map(r => {
    let activeType = 'DEFAULT';
    let templateName = 'الدوام الافتراضي (أحد - خميس)';
    let templateId = null;
    let workDays = defaultWorkDays;

    // Hint: نفس أولوية المحرك: نسخة الأيام المحفوظة أولاً، والقالب للاسم فقط
    const pick = (tplId, daysJson, type, customName) => {
      activeType = type;
      const t = tplId && templateMap.has(tplId) ? templateMap.get(tplId) : null;
      if (t) {
        templateName = t.name;
        templateId = t.id;
      } else {
        templateName = customName;
      }
      if (daysJson) workDays = JSON.parse(daysJson);
      else if (t) workDays = t.workDays;
    };

    if (r.weekly_sched_id) {
      pick(r.weekly_template_id, r.weekly_work_days, 'WEEKLY', 'مخصص أسبوعياً');
    } else if (r.fixed_sched_id) {
      pick(r.fixed_template_id, r.fixed_work_days, 'FIXED', 'مخصص ثابت');
    }

    // حساب أيام الأوف
    const allDays = [0, 1, 2, 3, 4, 5, 6];
    const offDays = allDays.filter(d => !workDays.includes(d));

    return {
      employeeId: r.employee_id,
      empCode: r.emp_code,
      name: r.name,
      department: r.department,
      weekStartDate,
      activeType,
      templateId,
      templateName,
      workDays,
      offDays
    };
  });

  return successResponse(res, {
    weekStartDate,
    total: result.length,
    assignments: result
  });
}

/**
 * تعيين جدول دوام لموظف أو مجموعة موظفين
 */
function assignSchedule(req, res) {
  const { employeeIds, scheduleType, templateId, workDays, weekStartDate } = req.body;
  const user = req.user;

  if (!Array.isArray(employeeIds) || employeeIds.length === 0) {
    return badRequest(res, 'يرجى اختيار موظف واحد على الأقل');
  }
  const ids = employeeIds.map(toPositiveInt);
  if (ids.some(id => id === null)) {
    return badRequest(res, 'قائمة الموظفين تحتوي معرفات غير صالحة');
  }

  const type = scheduleType === 'WEEKLY' ? 'WEEKLY' : 'FIXED';
  if (weekStartDate !== undefined && weekStartDate !== null && !isYmd(weekStartDate)) {
    return badRequest(res, 'تاريخ بداية الأسبوع غير صالح');
  }
  // Hint: تطبيع بداية الأسبوع إلى يوم الأحد دائماً حتى يطابق بحث المحرك
  const targetWeek = type === 'WEEKLY' ? getWeekSunday(weekStartDate || getBaghdadDateStr()) : null;

  // Hint: حفظ نسخة من أيام العمل دائماً (من القالب أو التخصيص) ليبقى التاريخ ثابتاً عند تعديل القوالب
  let resolvedDays = null;
  let resolvedTemplateId = null;
  if (templateId !== undefined && templateId !== null) {
    resolvedTemplateId = toPositiveInt(templateId);
    const tpl = resolvedTemplateId && db.prepare('SELECT work_days_json FROM schedule_templates WHERE id = ?').get(resolvedTemplateId);
    if (!tpl) return badRequest(res, 'قالب الدوام المحدد غير موجود');
    resolvedDays = JSON.parse(tpl.work_days_json);
  } else if (isWorkDaysArray(workDays)) {
    resolvedDays = [...workDays].sort();
  } else {
    return badRequest(res, 'يرجى اختيار قالب دوام أو تحديد أيام العمل (أرقام من 0 إلى 6)');
  }
  const workDaysJson = JSON.stringify(resolvedDays);

  const deleteWeeklyStmt = db.prepare("DELETE FROM employee_schedules WHERE employee_id = ? AND schedule_type = 'WEEKLY' AND week_start_date = ?");
  const deleteFixedStmt = db.prepare("DELETE FROM employee_schedules WHERE employee_id = ? AND schedule_type = 'FIXED'");
  const insertStmt = db.prepare(`
    INSERT INTO employee_schedules (employee_id, schedule_type, template_id, week_start_date, work_days_json)
    VALUES (?, ?, ?, ?, ?)
  `);

  db.transaction(() => {
    for (const empId of ids) {
      if (type === 'WEEKLY') {
        deleteWeeklyStmt.run(empId, targetWeek);
        insertStmt.run(empId, 'WEEKLY', resolvedTemplateId, targetWeek, workDaysJson);
      } else {
        deleteFixedStmt.run(empId);
        insertStmt.run(empId, 'FIXED', resolvedTemplateId, null, workDaysJson);
      }
    }
  })();

  // Hint: إعادة احتساب الأيام المعتمدة المتأثرة (أسبوع الجدول الأسبوعي، أو كل الأيام للجدول الثابت)
  const recalculatedDays = type === 'WEEKLY'
    ? recalcRange(targetWeek, addDaysYmd(targetWeek, 6), user.id)
    : recalcRange('0000-01-01', '9999-12-31', user.id);

  logAction(
    user.id,
    user.full_name,
    'تعيين جدول دوام',
    `تعيين جدول [${type}] لـ ${ids.length} موظف` + (targetWeek ? ` لأسبوع ${targetWeek}` : '') + ` (أُعيد احتساب ${recalculatedDays} يوم معتمد)`,
    req.clientIp
  );

  return successResponse(res, { recalculatedDays }, recalculatedDays > 0
    ? `تم تعيين جدول الدوام وإعادة احتساب ${recalculatedDays} يوم معتمد متأثر`
    : 'تم تعيين جدول الدوام بنجاح');
}

/**
 * نسخ جدول الأسبوع السابق (النقطة 17)
 */
function copyPreviousWeek(req, res) {
  const { targetWeekStartDate } = req.body;
  const user = req.user;

  if (!isYmd(targetWeekStartDate)) {
    return badRequest(res, 'يرجى تحديد تاريخ بداية الأسبوع المستهدف بصيغة صالحة');
  }

  // Hint: تطبيع الأسبوع المستهدف إلى الأحد ثم حساب الأسبوع السابق (قبل 7 أيام)
  const targetWeek = getWeekSunday(targetWeekStartDate);
  const prevWeekStartDate = addDaysYmd(targetWeek, -7);

  // جلب كافة جداول الأسبوع السابق
  const prevSchedules = db.prepare(`
    SELECT employee_id, template_id, work_days_json 
    FROM employee_schedules 
    WHERE schedule_type = 'WEEKLY' AND week_start_date = ?
  `).all(prevWeekStartDate);

  if (prevSchedules.length === 0) {
    return errorResponse(res, `لا توجد جداول أسبوعية مسجلة في الأسبوع السابق (${prevWeekStartDate}) لنسخها`, 404);
  }

  const deleteTargetStmt = db.prepare('DELETE FROM employee_schedules WHERE schedule_type = \'WEEKLY\' AND week_start_date = ?');
  const insertStmt = db.prepare(`
    INSERT INTO employee_schedules (employee_id, schedule_type, template_id, week_start_date, work_days_json)
    VALUES (?, 'WEEKLY', ?, ?, ?)
  `);

  const tx = db.transaction(() => {
    deleteTargetStmt.run(targetWeek);
    for (const s of prevSchedules) {
      insertStmt.run(s.employee_id, s.template_id, targetWeek, s.work_days_json);
    }
  });

  tx();

  const recalculatedDays = recalcRange(targetWeek, addDaysYmd(targetWeek, 6), user.id);

  logAction(
    user.id,
    user.full_name,
    'نسخ جدول أسبوعي',
    `نسخ جدول الأسبوع السابق (${prevWeekStartDate}) إلى الأسبوع الجديد (${targetWeek}) لـ ${prevSchedules.length} موظف`,
    req.clientIp
  );

  return successResponse(res, {
    copiedCount: prevSchedules.length,
    fromWeek: prevWeekStartDate,
    toWeek: targetWeek,
    recalculatedDays
  }, `تم نسخ جدول الأسبوع السابق بنجاح (${prevSchedules.length} موظف)`);
}

/**
 * دالة برمجية مساعدة لجلب أيام العمل لموظف في تاريخ محدد (يستخدمها محرك الحضور)
 */
function getEmployeeWorkDays(employeeId, dateStr) {
  const weekSunday = getWeekSunday(dateStr);

  // 1. جدول أسبوعي لهذا الأسبوع تحديداً
  const weekly = db.prepare(`
    SELECT es.work_days_json, st.work_days_json as tmpl_work_days
    FROM employee_schedules es
    LEFT JOIN schedule_templates st ON st.id = es.template_id
    WHERE es.employee_id = ? AND es.schedule_type = 'WEEKLY' AND es.week_start_date = ?
  `).get(employeeId, weekSunday);

  if (weekly) {
    const raw = weekly.work_days_json || weekly.tmpl_work_days;
    if (raw) return JSON.parse(raw);
  }

  // 2. جدول ثابت دائم
  const fixed = db.prepare(`
    SELECT es.work_days_json, st.work_days_json as tmpl_work_days
    FROM employee_schedules es
    LEFT JOIN schedule_templates st ON st.id = es.template_id
    WHERE es.employee_id = ? AND es.schedule_type = 'FIXED'
  `).get(employeeId);

  if (fixed) {
    const raw = fixed.work_days_json || fixed.tmpl_work_days;
    if (raw) return JSON.parse(raw);
  }

  // 3. الافتراضي: أحد إلى خميس [0, 1, 2, 3, 4] (الجمعة والسبت راحة)
  return [0, 1, 2, 3, 4];
}

module.exports = {
  listTemplates,
  createTemplate,
  updateTemplate,
  deleteTemplate,
  getAssignments,
  assignSchedule,
  copyPreviousWeek,
  getEmployeeWorkDays,
  getWeekSunday
};
