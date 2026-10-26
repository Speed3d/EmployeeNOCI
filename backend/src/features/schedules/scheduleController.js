/**
 * Hint: متحكم قوالب وجداول دوام الموظفين وأيام الراحة الأسبوعية (النقطة 17)
 * يدعم قوالب الشفتات، الجداول الثابتة والأسبوعية، ونسخ الأسبوع السابق
 */
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { getBaghdadDateStr, getDayOfWeekFromYmd, addDaysYmd } = require('../../tools/timeUtils');

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

  if (!name || !Array.isArray(workDays)) {
    return errorResponse(res, 'اسم القالب وقائمة أيام العمل حقول إلزامية', 400);
  }

  const stmt = db.prepare('INSERT INTO schedule_templates (name, work_days_json) VALUES (?, ?)');
  const result = stmt.run(name.trim(), JSON.stringify(workDays));

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

  const updatedName = name ? name.trim() : template.name;
  const updatedWorkDays = Array.isArray(workDays) ? JSON.stringify(workDays) : template.work_days_json;

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

  if (!weekStartDate) {
    weekStartDate = getWeekSunday(getBaghdadDateStr());
  }

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

    if (r.weekly_sched_id) {
      activeType = 'WEEKLY';
      if (r.weekly_template_id && templateMap.has(r.weekly_template_id)) {
        const t = templateMap.get(r.weekly_template_id);
        templateName = t.name;
        templateId = t.id;
        workDays = t.workDays;
      } else if (r.weekly_work_days) {
        templateName = 'مخصص أسبوعياً';
        workDays = JSON.parse(r.weekly_work_days);
      }
    } else if (r.fixed_sched_id) {
      activeType = 'FIXED';
      if (r.fixed_template_id && templateMap.has(r.fixed_template_id)) {
        const t = templateMap.get(r.fixed_template_id);
        templateName = t.name;
        templateId = t.id;
        workDays = t.workDays;
      } else if (r.fixed_work_days) {
        templateName = 'مخصص ثابت';
        workDays = JSON.parse(r.fixed_work_days);
      }
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
    return errorResponse(res, 'يرجى اختيار موظف واحد على الأقل', 400);
  }

  const type = scheduleType === 'WEEKLY' ? 'WEEKLY' : 'FIXED';
  const targetWeek = type === 'WEEKLY' ? (weekStartDate || getWeekSunday(getBaghdadDateStr())) : null;
  const workDaysJson = Array.isArray(workDays) ? JSON.stringify(workDays) : null;

  const deleteWeeklyStmt = db.prepare('DELETE FROM employee_schedules WHERE employee_id = ? AND schedule_type = \'WEEKLY\' AND week_start_date = ?');
  const deleteFixedStmt = db.prepare('DELETE FROM employee_schedules WHERE employee_id = ? AND schedule_type = \'FIXED\'');
  const insertStmt = db.prepare(`
    INSERT INTO employee_schedules (employee_id, schedule_type, template_id, week_start_date, work_days_json)
    VALUES (?, ?, ?, ?, ?)
  `);

  const tx = db.transaction(() => {
    for (const empId of employeeIds) {
      if (type === 'WEEKLY') {
        deleteWeeklyStmt.run(empId, targetWeek);
        insertStmt.run(empId, 'WEEKLY', templateId || null, targetWeek, workDaysJson);
      } else {
        deleteFixedStmt.run(empId);
        insertStmt.run(empId, 'FIXED', templateId || null, null, workDaysJson);
      }
    }
  });

  tx();

  logAction(
    user.id,
    user.full_name,
    'تعيين جدول دوام',
    `تعيين جدول [${type}] لـ ${employeeIds.length} موظف` + (targetWeek ? ` لأسبوع ${targetWeek}` : '')
  );

  return successResponse(res, null, 'تم تعيين جدول الدوام بنجاح');
}

/**
 * نسخ جدول الأسبوع السابق (النقطة 17)
 */
function copyPreviousWeek(req, res) {
  const { targetWeekStartDate } = req.body;
  const user = req.user;

  if (!targetWeekStartDate) {
    return errorResponse(res, 'يرجى تحديد تاريخ بداية الأسبوع المستهدف', 400);
  }

  // Hint: حساب الأسبوع السابق (قبل 7 أيام) بدقة دون انزلاق التاريخ بسبب فرق التوقيت
  const prevWeekStartDate = addDaysYmd(targetWeekStartDate, -7);

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
    deleteTargetStmt.run(targetWeekStartDate);
    for (const s of prevSchedules) {
      insertStmt.run(s.employee_id, s.template_id, targetWeekStartDate, s.work_days_json);
    }
  });

  tx();

  logAction(
    user.id,
    user.full_name,
    'نسخ جدول أسبوعي',
    `نسخ جدول الأسبوع السابق (${prevWeekStartDate}) إلى الأسبوع الجديد (${targetWeekStartDate}) لـ ${prevSchedules.length} موظف`
  );

  return successResponse(res, {
    copiedCount: prevSchedules.length,
    fromWeek: prevWeekStartDate,
    toWeek: targetWeekStartDate
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
