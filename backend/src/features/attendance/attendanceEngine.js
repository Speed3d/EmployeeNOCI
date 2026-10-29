/**
 * Hint: محرك معالجة الحضور والغياب والتأخيرات الذكي (Attendance Intelligence Engine)
 * 1. استبعاد الموظفين غير النشطين أو الـ VIP أو الأقسام المستبعدة أو المحذوفين من الكشف الجديد
 * 2. أولوية الحالة: عطلة رسمية -> يوم راحة (Off-Day) -> إجازة يوم كامل -> بصمة دخول/خروج
 * 3. الإذن الساعي (من/إلى) يعفي من التأخير أو الانصراف المبكر داخل فترته فقط
 * 4. فحص البصمة المنفردة بعد عتبة محددة كخروج فقط دون احتساب تأخير
 * 5. حفظ لقطة القواعد مع كل يوم معتمد، وإعادة الاحتساب تستخدمها افتراضياً لثبات التاريخ
 * 6. الموظف الذي شُمل في يوم معتمد يبقى فيه عند إعادة الاحتساب حتى لو تغيرت حالته لاحقاً
 */
const db = require('../../core/database');
const { ATTENDANCE_STATUS, LEAVE_TYPES } = require('../../shared/constants');
const { timeToMinutes, extractTime, getDayOfWeekFromYmd } = require('../../tools/timeUtils');
const { getEmployeeWorkDays } = require('../schedules/scheduleController');

const PRESENT_STATUSES = [ATTENDANCE_STATUS.ON_TIME, ATTENDANCE_STATUS.LATE, ATTENDANCE_STATUS.VERY_LATE, ATTENDANCE_STATUS.EARLY_LEAVE];

function minutesToHHMM(total) {
  const t = Math.max(0, Math.min(23 * 60 + 59, total));
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
}

/**
 * جلب إعدادات النظام الحالية وقواعد الدوام والمكافأة كلقطة كاملة قابلة للحفظ
 */
function getSystemRules() {
  const rows = db.prepare('SELECT key, value FROM system_settings').all();
  const settings = {};
  for (const r of rows) {
    settings[r.key] = r.value;
  }

  const workStartTime = settings['work_start_time'] || '10:00';
  const workEndTime = settings['work_end_time'] || '15:00';
  const bonusMode = settings['bonus_mode'] || 'default';

  // Hint: النمط الافتراضي يتبع أوقات الدوام: المكافأة المبكرة قبل البداية بساعة، والإضافي بعد نهاية الدوام
  const earlyBonusTime = bonusMode === 'default'
    ? minutesToHHMM(timeToMinutes(workStartTime) - 60)
    : (settings['early_bonus_time'] || '09:00');
  const overtimeBonusTime = bonusMode === 'default'
    ? workEndTime
    : (settings['overtime_bonus_time'] || workEndTime);

  return {
    workStartTime,
    workEndTime,
    bonusEnabled: settings['bonus_enabled'] === 'true',
    bonusMode,
    earlyBonusTime,
    overtimeBonusTime,
    singlePunchExitThreshold: settings['single_punch_exit_threshold'] || '12:30'
  };
}

/**
 * Hint: الموظفون المشمولون بكشف يوم محدد:
 * المشمولون حالياً (نشط، غير مستثنى، قسم غير مستبعد، غير محذوف) + كل من له سجل معتمد مسبقاً في نفس اليوم
 */
function getEmployeesForDay(dateStr) {
  return db.prepare(`
    SELECT e.*, a.department_snapshot AS existing_snapshot
    FROM employees e
    LEFT JOIN attendance_records a ON a.employee_id = e.id AND a.date = ?
    WHERE a.id IS NOT NULL
       OR (
         e.deleted_at IS NULL
         AND e.status = 'نشط'
         AND e.is_exempt = 0
         AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
       )
    ORDER BY CAST(e.emp_code AS INTEGER) ASC
  `).all(dateStr);
}

function isHourlyLeave(leave) {
  return leave.leave_type === LEAVE_TYPES.HOURLY && leave.start_time && leave.end_time;
}

/**
 * Hint: تحليل الحضور الصباحي بالنسبة لبداية الدوام الفعلية (بعد تطبيق الإذن الساعي)
 */
function classifyEntry(entryMin, expectedStartMin, rules, earlyBonusMin) {
  if (rules.bonusEnabled && entryMin < earlyBonusMin) {
    const bonus = earlyBonusMin - entryMin;
    return { status: ATTENDANCE_STATUS.ON_TIME, late: 0, bonus, note: `حضور مبكر بمكافأة (+${bonus} د)` };
  }
  if (entryMin <= expectedStartMin) {
    return { status: ATTENDANCE_STATUS.ON_TIME, late: 0, bonus: 0, note: 'حضور في الوقت المحدد' };
  }
  const late = entryMin - expectedStartMin;
  if (late <= 30) {
    return { status: ATTENDANCE_STATUS.LATE, late, bonus: 0, note: `تأخير صباحي بسيط (${late} دقيقة)` };
  }
  return { status: ATTENDANCE_STATUS.VERY_LATE, late, bonus: 0, note: `تأخير صباحي كبير (${late} دقيقة)` };
}

/**
 * معالجة وحساب حالة الحضور ليوم محدد
 * @param {string} dateStr - التاريخ بصيغة "YYYY-MM-DD"
 * @param {Array} punchList - بصمات الموظفين لهذا اليوم (مصدرها الخادم فقط)
 * @param {Object} options - { persist, userId, rawPunchesJson, rules }
 */
function processAttendanceForDay(dateStr, punchList = [], options = {}) {
  const { persist = false, userId = null, rawPunchesJson = null } = options;
  const rules = options.rules || getSystemRules();

  const workStartMin = timeToMinutes(rules.workStartTime);
  const workEndMin = timeToMinutes(rules.workEndTime);
  const earlyBonusMin = timeToMinutes(rules.earlyBonusTime);
  const overtimeBonusMin = timeToMinutes(rules.overtimeBonusTime);
  const singlePunchExitMin = timeToMinutes(rules.singlePunchExitThreshold || '12:30');
  const year = parseInt(dateStr.slice(0, 4), 10);

  // 1. خريطة البصمات حسب كود الموظف
  const punchMap = new Map();
  for (const p of punchList) {
    punchMap.set(String(p.empCode).trim(), p);
  }

  // 2. الموظفون المشمولون بهذا اليوم
  const employees = getEmployeesForDay(dateStr);

  // 3. فحص هل اليوم عطلة رسمية
  const holiday = db.prepare('SELECT * FROM official_holidays WHERE date = ?').get(dateStr);

  // 4. الإجازات السارية: يوم كامل أو إذن ساعي
  const leavesOnDate = db.prepare('SELECT * FROM leaves WHERE ? BETWEEN start_date AND end_date').all(dateStr);
  const fullDayLeaves = new Map();
  const hourlyLeaves = new Map();
  for (const l of leavesOnDate) {
    if (isHourlyLeave(l)) {
      if (!hourlyLeaves.has(l.employee_id)) hourlyLeaves.set(l.employee_id, []);
      hourlyLeaves.get(l.employee_id).push(l);
    } else {
      fullDayLeaves.set(l.employee_id, l);
    }
  }

  // Hint: يوم الأسبوع (0 = أحد ... 6 = سبت) محسوب بشكل محايد زمنياً
  const dayOfWeek = getDayOfWeekFromYmd(dateStr);

  const results = [];

  for (const emp of employees) {
    const empCode = String(emp.emp_code).trim();
    const punchData = punchMap.get(empCode);
    const leave = fullDayLeaves.get(emp.id);
    const hourly = hourlyLeaves.get(emp.id) || [];
    const department = emp.existing_snapshot || emp.department;

    let status = ATTENDANCE_STATUS.ABSENT;
    let firstPunch = null;
    let lastPunch = null;
    let punchCount = 0;
    let punchDetails = [];
    let lateMinutes = 0;
    let earlyLeaveMinutes = 0;
    let earlyBonusMinutes = 0;
    let overtimeMinutes = 0;
    const notes = [];

    // Hint: تطبيق الإذن الساعي على بداية ونهاية الدوام المتوقعة
    let expectedStartMin = workStartMin;
    let expectedEndMin = workEndMin;
    for (const hl of hourly) {
      const ls = timeToMinutes(hl.start_time);
      const le = timeToMinutes(hl.end_time);
      if (ls <= workStartMin && le > workStartMin) {
        expectedStartMin = Math.max(expectedStartMin, Math.min(le, workEndMin));
      }
      if (le >= workEndMin && ls < workEndMin) {
        expectedEndMin = Math.min(expectedEndMin, Math.max(ls, workStartMin));
      }
      notes.push(`إذن ساعي (${hl.start_time} - ${hl.end_time})`);
    }

    const empWorkDays = getEmployeeWorkDays(emp.id, dateStr);
    const isEmployeeOffDay = !empWorkDays.includes(dayOfWeek);

    if (holiday) {
      // أولوية 1: عطلة رسمية معتمدة
      status = ATTENDANCE_STATUS.HOLIDAY;
      notes.length = 0;
      notes.push(`عطلة رسمية: ${holiday.title}`);
    } else if (isEmployeeOffDay) {
      // أولوية 2: يوم راحة أسبوعية وفق جدول الدوام
      status = ATTENDANCE_STATUS.OFF_DAY;
      notes.length = 0;
      if (punchData && punchData.firstPunch) {
        firstPunch = punchData.firstPunch;
        lastPunch = punchData.lastPunch;
        punchCount = punchData.punchCount;
        punchDetails = punchData.allPunches || [firstPunch];
        notes.push('حضور في يوم راحة أسبوعية (ملاحظة فقط دون احتساب إضافي)');
      } else {
        notes.push('يوم راحة أسبوعية');
      }
    } else if (leave) {
      // أولوية 3: إجازة يوم كامل
      status = ATTENDANCE_STATUS.ON_LEAVE;
      notes.length = 0;
      notes.push(`إجازة ${leave.leave_type}${leave.reason ? ` (${leave.reason})` : ''}`);
    } else if (!punchData || !punchData.firstPunch) {
      // أولوية 4: غائب بدون بصمات
      status = ATTENDANCE_STATUS.ABSENT;
      notes.unshift('غائب بدون عذر مسجل');
    } else {
      // أولوية 5: تحليل البصمات
      firstPunch = punchData.firstPunch;
      lastPunch = punchData.lastPunch;
      punchCount = punchData.punchCount;
      punchDetails = punchData.allPunches || [firstPunch];

      const entryMin = timeToMinutes(extractTime(firstPunch));
      const exitMin = timeToMinutes(extractTime(lastPunch));

      if (punchCount === 1) {
        if (entryMin === null) {
          status = ATTENDANCE_STATUS.MISSED_PUNCH;
          notes.unshift('بصمة ناقصة (تعذر قراءة توقيت البصمة)');
        } else if (entryMin >= singlePunchExitMin) {
          // البصمة الوحيدة بعد العتبة -> بصمة خروج فقط
          status = ATTENDANCE_STATUS.MISSED_PUNCH;
          firstPunch = null;
          lastPunch = punchData.firstPunch;
          notes.unshift('سجل بصمة خروج فقط (لم يبصم دخول صباحاً)');
        } else {
          const entry = classifyEntry(entryMin, expectedStartMin, rules, earlyBonusMin);
          status = entry.status;
          lateMinutes = entry.late;
          earlyBonusMinutes = entry.bonus;
          notes.unshift(`${entry.note} | لم يسجل بصمة خروج`);
        }
      } else {
        if (entryMin !== null) {
          const entry = classifyEntry(entryMin, expectedStartMin, rules, earlyBonusMin);
          status = entry.status;
          lateMinutes = entry.late;
          earlyBonusMinutes = entry.bonus;
          notes.unshift(entry.note);
        }

        if (exitMin !== null) {
          if (exitMin < expectedEndMin) {
            earlyLeaveMinutes = expectedEndMin - exitMin;
            notes.push(`انصراف مبكر قبل الدوام (${earlyLeaveMinutes} د)`);
            if (status === ATTENDANCE_STATUS.ON_TIME) {
              status = ATTENDANCE_STATUS.EARLY_LEAVE;
            }
          } else if (rules.bonusEnabled && exitMin > overtimeBonusMin) {
            overtimeMinutes = exitMin - overtimeBonusMin;
            notes.push(`دوام إضافي (+${overtimeMinutes} د)`);
          }
        }
      }
    }

    const detailsJson = JSON.stringify(punchDetails);
    const notesText = notes.join(' | ');

    // Hint: المفاتيح بصيغتي camelCase و snake_case لتطابق وضع المعاينة مع اليوم المعتمد
    results.push({
      employeeId: emp.id,
      employee_id: emp.id,
      empCode: emp.emp_code,
      emp_code: emp.emp_code,
      name: emp.name,
      department,
      departmentSnapshot: department,
      department_snapshot: department,
      date: dateStr,
      firstPunch,
      first_punch: firstPunch,
      lastPunch,
      last_punch: lastPunch,
      punchCount,
      punch_count: punchCount,
      punchDetails: detailsJson,
      punch_details: detailsJson,
      status,
      lateMinutes,
      late_minutes: lateMinutes,
      earlyLeaveMinutes,
      early_leave_minutes: earlyLeaveMinutes,
      earlyBonusMinutes,
      early_bonus_minutes: earlyBonusMinutes,
      overtimeMinutes,
      overtime_minutes: overtimeMinutes,
      notes: notesText,
      year
    });
  }

  const count = (pred) => results.filter(pred).length;
  const stats = {
    date: dateStr,
    total: results.length,
    totalEmployees: results.length,
    present: count(r => PRESENT_STATUSES.includes(r.status)),
    onTime: count(r => r.status === ATTENDANCE_STATUS.ON_TIME),
    late: count(r => [ATTENDANCE_STATUS.LATE, ATTENDANCE_STATUS.VERY_LATE].includes(r.status)),
    absent: count(r => r.status === ATTENDANCE_STATUS.ABSENT),
    onLeave: count(r => r.status === ATTENDANCE_STATUS.ON_LEAVE),
    offDay: count(r => r.status === ATTENDANCE_STATUS.OFF_DAY),
    holiday: count(r => r.status === ATTENDANCE_STATUS.HOLIDAY),
    missedPunch: count(r => r.status === ATTENDANCE_STATUS.MISSED_PUNCH)
  };

  // 5. الحفظ في قاعدة البيانات فقط عند الاعتماد
  if (persist) {
    const saveRecordStmt = db.prepare(`
      INSERT INTO attendance_records (
        employee_id, date, department_snapshot, first_punch, last_punch, punch_count,
        punch_details, status, late_minutes, early_leave_minutes,
        early_bonus_minutes, overtime_minutes, notes, year
      ) VALUES (
        @employeeId, @date, @departmentSnapshot, @firstPunch, @lastPunch, @punchCount,
        @punchDetails, @status, @lateMinutes, @earlyLeaveMinutes,
        @earlyBonusMinutes, @overtimeMinutes, @notes, @year
      ) ON CONFLICT(employee_id, date) DO UPDATE SET
        department_snapshot = excluded.department_snapshot,
        first_punch = excluded.first_punch,
        last_punch = excluded.last_punch,
        punch_count = excluded.punch_count,
        punch_details = excluded.punch_details,
        status = excluded.status,
        late_minutes = excluded.late_minutes,
        early_leave_minutes = excluded.early_leave_minutes,
        early_bonus_minutes = excluded.early_bonus_minutes,
        overtime_minutes = excluded.overtime_minutes,
        notes = excluded.notes,
        year = excluded.year
    `);

    const saveDayStmt = db.prepare(`
      INSERT INTO attendance_days (date, status, committed_by, raw_punches_json, stats_json, rules_json)
      VALUES (?, 'COMMITTED', ?, ?, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        status = 'COMMITTED',
        committed_by = excluded.committed_by,
        committed_at = CURRENT_TIMESTAMP,
        raw_punches_json = excluded.raw_punches_json,
        stats_json = excluded.stats_json,
        rules_json = excluded.rules_json
    `);

    db.transaction(() => {
      saveDayStmt.run(dateStr, userId, rawPunchesJson || JSON.stringify(punchList), JSON.stringify(stats), JSON.stringify(rules));
      for (const r of results) {
        saveRecordStmt.run(r);
      }
    })();
  }

  return { stats, records: results, rules };
}

/**
 * Hint: البصمات الخام المحفوظة ليوم معتمد (مصدرها الخادم)، مع بديل احتياطي من السجلات للأيام القديمة
 */
function getStoredPunches(dateStr) {
  const day = db.prepare('SELECT raw_punches_json FROM attendance_days WHERE date = ?').get(dateStr);
  if (day && day.raw_punches_json) {
    try {
      return JSON.parse(day.raw_punches_json);
    } catch (_) {
      // يُكمل للبديل الاحتياطي
    }
  }

  const stored = db.prepare(`
    SELECT a.first_punch, a.last_punch, a.punch_count, a.punch_details, e.emp_code, e.name, e.department
    FROM attendance_records a
    JOIN employees e ON e.id = a.employee_id
    WHERE a.date = ? AND (a.first_punch IS NOT NULL OR a.last_punch IS NOT NULL)
  `).all(dateStr);

  return stored.map(s => {
    let all;
    try { all = s.punch_details ? JSON.parse(s.punch_details) : null; } catch (_) { all = null; }
    return {
      empCode: s.emp_code,
      name: s.name,
      department: s.department,
      firstPunch: s.first_punch || s.last_punch,
      lastPunch: s.last_punch || s.first_punch,
      punchCount: s.punch_count || 1,
      allPunches: all || [s.first_punch || s.last_punch]
    };
  });
}

/**
 * Hint: إعادة احتساب يوم معتمد. تستخدم لقطة القواعد المحفوظة لذلك اليوم ما لم يُطلب صراحة استخدام القواعد الحالية
 */
function recalculateCommittedDayIfExists(dateStr, userId = null, { useCurrentRules = false } = {}) {
  const day = db.prepare("SELECT * FROM attendance_days WHERE date = ? AND status = 'COMMITTED'").get(dateStr);
  if (!day) return null;

  let rules = null;
  if (!useCurrentRules && day.rules_json) {
    try { rules = JSON.parse(day.rules_json); } catch (_) { rules = null; }
  }

  const punchList = getStoredPunches(dateStr);
  return processAttendanceForDay(dateStr, punchList, {
    persist: true,
    userId: userId || day.committed_by,
    rawPunchesJson: JSON.stringify(punchList),
    rules: rules || getSystemRules()
  });
}

/**
 * Hint: إعادة احتساب كل الأيام المعتمدة ضمن فترة (تُستدعى بعد تغيير الإجازات أو العطل أو الجداول)
 */
function recalculateCommittedRange(startDate, endDate, userId = null) {
  const days = db.prepare(`
    SELECT date FROM attendance_days
    WHERE date BETWEEN ? AND ? AND status = 'COMMITTED'
    ORDER BY date ASC
  `).all(startDate, endDate);
  for (const d of days) {
    recalculateCommittedDayIfExists(d.date, userId);
  }
  return days.length;
}

module.exports = {
  PRESENT_STATUSES,
  getSystemRules,
  processAttendanceForDay,
  recalculateCommittedDayIfExists,
  recalculateCommittedRange,
  getStoredPunches
};
