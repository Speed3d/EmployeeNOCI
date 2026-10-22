/**
 * Hint: محرك معالجة الحضور والغياب والتأخيرات الذكي (Attendance Intelligence Engine)
 * الإصدار الثاني المعتمد:
 * 1. استبعاد الموظفين غير النشطين أو الـ VIP أو الأقسام المستبعدة تماماً من الكشف
 * 2. تطبيق أولوية الحالة: عطلة رسمية -> يوم راحة (Off-Day) -> إجازة معتمدة -> بصمة دخول/خروج
 * 3. فحص البصمة المنفردة بعد الظهر كخروج فقط دون احتساب تأخير
 * 4. احتساب مكافأة الحضور المبكر والدوام الإضافي وفق العتبة المحددة
 * 5. دعم وضع المعاينة (Preview) دون كتابة ووضع الاعتماد (Commit) مع حفظ لقطة القسم
 */
const db = require('../../core/database');
const { ATTENDANCE_STATUS } = require('../../shared/constants');
const { timeToMinutes, extractTime } = require('../../tools/timeUtils');
const { getEmployeeWorkDays } = require('../schedules/scheduleController');

/**
 * جلب إعدادات النظام الحالية وقواعد الدوام والمكافأة
 */
function getSystemRules() {
  const rows = db.prepare('SELECT key, value FROM system_settings').all();
  const settings = {};
  for (const r of rows) {
    settings[r.key] = r.value;
  }

  const bonusMode = settings['bonus_mode'] || 'default';
  const earlyBonusTime = bonusMode === 'default' ? '09:00' : (settings['early_bonus_time'] || '09:00');
  const overtimeBonusTime = bonusMode === 'default' ? '15:00' : (settings['overtime_bonus_time'] || '15:00');

  return {
    workStartTime: settings['work_start_time'] || '10:00',
    workEndTime: settings['work_end_time'] || '15:00',
    bonusEnabled: settings['bonus_enabled'] === 'true',
    bonusMode,
    earlyBonusTime,
    overtimeBonusTime,
    activeYear: parseInt(settings['active_year'] || '2026', 10)
  };
}

/**
 * معالجة وحساب حالة الحضور ليوم محدد لجميع الموظفين المستحقين للكشف
 * @param {string} dateStr - التاريخ بصيغة "YYYY-MM-DD"
 * @param {Array} punchList - قائمة بيانات البصمات المستخرجة من الإكسل لهذا اليوم
 * @param {Object} options - { persist: boolean, userId: number, rawPunchesJson: string }
 */
function processAttendanceForDay(dateStr, punchList = [], options = {}) {
  const { persist = false, userId = null, rawPunchesJson = null } = options;

  const rules = getSystemRules();
  const workStartMin = timeToMinutes(rules.workStartTime); // 600 min (10:00)
  const workEndMin = timeToMinutes(rules.workEndTime);     // 900 min (15:00)
  const earlyBonusMin = timeToMinutes(rules.earlyBonusTime); // 540 min (09:00)
  const overtimeBonusMin = timeToMinutes(rules.overtimeBonusTime); // 900 min (15:00)

  // 1. خريطة البصمات القادمة من الإكسل حسب كود الموظف
  const punchMap = new Map();
  for (const p of punchList) {
    punchMap.set(String(p.empCode).trim(), p);
  }

  // 2. جلب الموظفين النشطين وغير المستبعدين إدارياً
  // الموظف المستبعد (قسم مستبعد / غير نشط / VIP) لا يظهر إطلاقاً في الكشف
  const activeEmployees = db.prepare(`
    SELECT * FROM employees 
    WHERE status = 'نشط' 
      AND is_exempt = 0 
      AND department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
    ORDER BY CAST(emp_code AS INTEGER) ASC
  `).all();

  // 3. فحص هل اليوم عطلة رسمية
  const holiday = db.prepare('SELECT * FROM official_holidays WHERE date = ?').get(dateStr);

  // 4. جلب كافة الإجازات السارية في هذا التاريخ
  const leavesOnDate = db.prepare(`
    SELECT * FROM leaves 
    WHERE ? BETWEEN start_date AND end_date
  `).all(dateStr);
  const leaveMap = new Map();
  for (const l of leavesOnDate) {
    leaveMap.set(l.employee_id, l);
  }

  // يوم الأسبوع (0 = أحد، 1 = إثنين، ... 6 = سبت)
  const dayOfWeek = new Date(dateStr).getDay();

  const results = [];

  for (const emp of activeEmployees) {
    const empCode = String(emp.emp_code).trim();
    const punchData = punchMap.get(empCode);
    const leave = leaveMap.get(emp.id);

    let status = ATTENDANCE_STATUS.ABSENT;
    let firstPunch = null;
    let lastPunch = null;
    let punchCount = 0;
    let punchDetails = [];
    let lateMinutes = 0;
    let earlyLeaveMinutes = 0;
    let earlyBonusMinutes = 0;
    let overtimeMinutes = 0;
    let notes = '';

    // التحقق من جدول دوام الموظف لمعرفة أيام الراحة الأسبوعية (Off-Days)
    const empWorkDays = getEmployeeWorkDays(emp.id, dateStr);
    const isEmployeeOffDay = !empWorkDays.includes(dayOfWeek);

    // أولوية 1: عطلة رسمية معتمدة
    if (holiday) {
      status = ATTENDANCE_STATUS.HOLIDAY;
      notes = `عطلة رسمية: ${holiday.title}`;
    }
    // أولوية 2: يوم راحة أسبوعية (Off-Day) وفق جدول الدوام
    else if (isEmployeeOffDay) {
      status = ATTENDANCE_STATUS.OFF_DAY;
      if (punchData && punchData.firstPunch) {
        firstPunch = punchData.firstPunch;
        lastPunch = punchData.lastPunch;
        punchCount = punchData.punchCount;
        punchDetails = punchData.allPunches || [firstPunch];
        notes = 'حضور في يوم راحة أسبوعية (ملاحظة فقط دون احتساب إضافي)';
      } else {
        notes = 'يوم راحة أسبوعية';
      }
    }
    // أولوية 3: إجازة معتمدة مسجلة في النظام
    else if (leave) {
      status = ATTENDANCE_STATUS.ON_LEAVE;
      notes = `إجازة ${leave.leave_type}${leave.reason ? ` (${leave.reason})` : ''}`;
    }
    // أولوية 4: غائب بدون عذر (لا توجد بصمات)
    else if (!punchData || !punchData.firstPunch) {
      status = ATTENDANCE_STATUS.ABSENT;
      notes = 'غائب بدون عذر مسجل';
    }
    // أولوية 5: تحليل البصمات (حضور وانصراف)
    else {
      firstPunch = punchData.firstPunch;
      lastPunch = punchData.lastPunch;
      punchCount = punchData.punchCount;
      punchDetails = punchData.allPunches || [firstPunch];

      const entryTimeStr = extractTime(firstPunch);
      const exitTimeStr = extractTime(lastPunch);
      const entryMin = timeToMinutes(entryTimeStr);
      const exitMin = timeToMinutes(exitTimeStr);

      // في حال وجود بصمة واحدة فقط
      if (punchCount === 1) {
        // إذا كانت البصمة الوحيدة بعد الساعة 12:30 ظهراً (750 دقيقة) -> تعتبر بصمة خروج فقط
        if (entryMin && entryMin >= 750) {
          status = ATTENDANCE_STATUS.MISSED_PUNCH;
          firstPunch = null;
          lastPunch = punchData.firstPunch;
          notes = 'سجل بصمة خروج فقط (لم يبصم دخول صباحاً)';
        } else {
          // بصمة دخول صباحي فقط
          if (entryMin <= workStartMin) {
            status = ATTENDANCE_STATUS.ON_TIME;
            notes = 'حضور في الوقت المحدد | لم يسجل بصمة خروج';
          } else if (entryMin <= workStartMin + 30) {
            lateMinutes = entryMin - workStartMin;
            status = ATTENDANCE_STATUS.LATE;
            notes = `تأخير صباحي بسيط (${lateMinutes} دقيقة) | لم يسجل بصمة خروج`;
          } else {
            lateMinutes = entryMin - workStartMin;
            status = ATTENDANCE_STATUS.VERY_LATE;
            notes = `تأخير صباحي كبير (${lateMinutes} دقيقة) | لم يسجل بصمة خروج`;
          }
        }
      } else {
        // وجود بصمتين أو أكثر (دخول وخروج)
        // أ. فحص الحضور الصباحي
        if (entryMin !== null) {
          if (rules.bonusEnabled && entryMin < earlyBonusMin) {
            earlyBonusMinutes = earlyBonusMin - entryMin;
            status = ATTENDANCE_STATUS.ON_TIME;
            notes = `حضور مبكر بمكافأة (+${earlyBonusMinutes} د)`;
          } else if (entryMin <= workStartMin) {
            status = ATTENDANCE_STATUS.ON_TIME;
            notes = 'حضور في الوقت المحدد';
          } else if (entryMin <= workStartMin + 30) {
            lateMinutes = entryMin - workStartMin;
            status = ATTENDANCE_STATUS.LATE;
            notes = `تأخير صباحي بسيط (${lateMinutes} دقيقة)`;
          } else {
            lateMinutes = entryMin - workStartMin;
            status = ATTENDANCE_STATUS.VERY_LATE;
            notes = `تأخير صباحي كبير (${lateMinutes} دقيقة)`;
          }
        }

        // ب. فحص الانصراف المسائي
        if (exitMin !== null) {
          if (exitMin < workEndMin) {
            earlyLeaveMinutes = workEndMin - exitMin;
            const leaveNote = `انصراف مبكر قبل الدوام (${earlyLeaveMinutes} د)`;
            notes += (notes ? ' | ' : '') + leaveNote;

            if (status === ATTENDANCE_STATUS.ON_TIME) {
              status = ATTENDANCE_STATUS.EARLY_LEAVE;
            }
          } else if (rules.bonusEnabled && exitMin > overtimeBonusMin) {
            overtimeMinutes = exitMin - overtimeBonusMin;
            if (overtimeMinutes > 0) {
              notes += (notes ? ' | ' : '') + `دوام إضافي (+${overtimeMinutes} د)`;
            }
          }
        }
      }
    }

    results.push({
      employeeId: emp.id,
      empCode: emp.emp_code,
      name: emp.name,
      department: emp.department,
      departmentSnapshot: emp.department,
      date: dateStr,
      firstPunch,
      lastPunch,
      punchCount,
      punchDetails: JSON.stringify(punchDetails),
      status,
      lateMinutes,
      earlyLeaveMinutes,
      earlyBonusMinutes,
      overtimeMinutes,
      notes,
      year: rules.activeYear
    });
  }

  // حساب الإحصائيات العامة للكشف
  const stats = {
    date: dateStr,
    totalEmployees: results.length,
    present: results.filter(r => [ATTENDANCE_STATUS.ON_TIME, ATTENDANCE_STATUS.LATE, ATTENDANCE_STATUS.VERY_LATE, ATTENDANCE_STATUS.EARLY_LEAVE].includes(r.status)).length,
    onTime: results.filter(r => r.status === ATTENDANCE_STATUS.ON_TIME).length,
    late: results.filter(r => [ATTENDANCE_STATUS.LATE, ATTENDANCE_STATUS.VERY_LATE].includes(r.status)).length,
    absent: results.filter(r => r.status === ATTENDANCE_STATUS.ABSENT).length,
    onLeave: results.filter(r => r.status === ATTENDANCE_STATUS.ON_LEAVE).length,
    offDay: results.filter(r => r.status === ATTENDANCE_STATUS.OFF_DAY).length,
    holiday: results.filter(r => r.status === ATTENDANCE_STATUS.HOLIDAY).length
  };

  // 5. الحفظ في قاعدة البيانات فقط عند الاعتماد (persist: true)
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
      INSERT INTO attendance_days (date, status, committed_by, raw_punches_json, stats_json)
      VALUES (?, 'COMMITTED', ?, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        status = 'COMMITTED',
        committed_by = excluded.committed_by,
        committed_at = CURRENT_TIMESTAMP,
        raw_punches_json = excluded.raw_punches_json,
        stats_json = excluded.stats_json
    `);

    const saveTx = db.transaction(() => {
      saveDayStmt.run(dateStr, userId, rawPunchesJson || JSON.stringify(punchList), JSON.stringify(stats));
      for (const r of results) {
        saveRecordStmt.run(r);
      }
    });

    saveTx();
  }

  return {
    stats,
    records: results
  };
}

module.exports = {
  getSystemRules,
  processAttendanceForDay
};
