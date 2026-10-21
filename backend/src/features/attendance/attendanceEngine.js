/**
 * Hint: محرك معالجة الحضور والغياب والتأخيرات الذكي (Attendance Intelligence Engine)
 * يطبق كافة قواعد العمل بدقة:
 * - فحص الشخصيات القيادية المستثناة (VIP)
 * - فحص الأقسام المستبعدة (المنسبين، المستقيلين، المتوفين)
 * - فحص العطل الرسمية والجمعة والسبت
 * - فحص رصيد الإجازات والأذونات
 * - حساب دقائق التأخير وتلوين الخلايا (أخضر، أصفر، برتقالي، أحمر، أزرق، رمادي)
 * - حساب مكافآت الحضور المبكر والدوام الإضافي
 */
const db = require('../../core/database');
const { ATTENDANCE_STATUS } = require('../../shared/constants');
const { timeToMinutes, isWeekend, extractTime } = require('../../tools/timeUtils');

/**
 * جلب إعدادات النظام الحالية
 */
function getSystemRules() {
  const rows = db.prepare('SELECT key, value FROM system_settings').all();
  const settings = {};
  for (const r of rows) {
    settings[r.key] = r.value;
  }

  return {
    workStartTime: settings['work_start_time'] || '10:00',
    workEndTime: settings['work_end_time'] || '15:00',
    bonusEnabled: settings['bonus_enabled'] === 'true',
    bonusMode: settings['bonus_mode'] || 'default',
    earlyBonusTime: settings['early_bonus_time'] || '09:00',
    overtimeBonusTime: settings['overtime_bonus_time'] || '15:00',
    activeYear: parseInt(settings['active_year'] || '2026', 10)
  };
}

/**
 * معالجة وحساب حالة الحضور ليوم محدد لجميع الموظفين
 * @param {string} dateStr - التاريخ بصيغة "YYYY-MM-DD"
 * @param {Array} punchList - قائمة بيانات البصمات المستخرجة من الإكسل لهذا اليوم
 */
function processAttendanceForDay(dateStr, punchList = []) {
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

  // 2. جلب جميع الموظفين من القاعدة
  const allEmployees = db.prepare('SELECT * FROM employees').all();

  // 3. جلب الأقسام المستبعدة
  const excludedDepts = new Set(
    db.prepare('SELECT name FROM departments WHERE is_excluded = 1').all().map(d => d.name)
  );

  // 4. فحص هل اليوم عطلة رسمية أو جمعة/سبت
  const isOffDay = isWeekend(dateStr);
  const holiday = db.prepare('SELECT * FROM official_holidays WHERE date = ?').get(dateStr);

  // 5. جلب كافة الإجازات السارية في هذا التاريخ
  const leavesOnDate = db.prepare(`
    SELECT * FROM leaves 
    WHERE ? BETWEEN start_date AND end_date
  `).all(dateStr);
  const leaveMap = new Map();
  for (const l of leavesOnDate) {
    leaveMap.set(l.employee_id, l);
  }

  const results = [];

  for (const emp of allEmployees) {
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

    // حالة 1: الموظف مستثنى VIP (الأمين العام، الأمين المالي، المستشارين)
    if (emp.is_exempt === 1) {
      status = ATTENDANCE_STATUS.VIP_EXEMPT;
      notes = emp.exempt_reason || 'مستثنى إدارياً من البصمة';
    }
    // حالة 2: القسم مستبعد بالكامل (استقالة، تنسيب، متوفين، إلخ)
    else if (excludedDepts.has(emp.department) || emp.status !== 'نشط') {
      status = ATTENDANCE_STATUS.DEPT_EXCLUDED;
      notes = `قسم مستبعد: ${emp.department} (${emp.status})`;
    }
    // حالة 3: عطلة رسمية أو عطلة نهاية أسبوع
    else if (holiday) {
      status = ATTENDANCE_STATUS.VIP_EXEMPT;
      notes = `عطلة رسمية: ${holiday.title}`;
    } else if (isOffDay) {
      status = ATTENDANCE_STATUS.VIP_EXEMPT;
      notes = 'عطلة نهاية الأسبوع (الجمعة/السبت)';
    }
    // حالة 4: الموظف لديه إجازة مسجلة في النظام
    else if (leave) {
      status = ATTENDANCE_STATUS.ON_LEAVE;
      notes = `إجازة ${leave.leave_type}${leave.reason ? ` (${leave.reason})` : ''}`;
    }
    // حالة 5: لا توجد بصمات والموظف غير مجاز وغير مستثنى -> غائب
    else if (!punchData || !punchData.firstPunch) {
      status = ATTENDANCE_STATUS.ABSENT;
      notes = 'غائب بدون عذر مسجل';
    }
    // حالة 6: توجد بصمة للموظف -> نحلل الدخول والخروج
    else {
      firstPunch = punchData.firstPunch;
      lastPunch = punchData.lastPunch;
      punchCount = punchData.punchCount;
      punchDetails = punchData.allPunches || [firstPunch];

      const entryTimeStr = extractTime(firstPunch);
      const exitTimeStr = extractTime(lastPunch);
      const entryMin = timeToMinutes(entryTimeStr);
      const exitMin = timeToMinutes(exitTimeStr);

      // أ. فحص الحضور الصباحي
      if (entryMin !== null) {
        // حضور مبكر ومكافأة
        if (rules.bonusEnabled && entryMin <= earlyBonusMin) {
          earlyBonusMinutes = workStartMin - entryMin;
          status = ATTENDANCE_STATUS.ON_TIME;
          notes = `حضور مبكر بمكافأة (+${earlyBonusMinutes} د)`;
        }
        // حضور نظامي في الوقت (حتى 10:00)
        else if (entryMin <= workStartMin) {
          status = ATTENDANCE_STATUS.ON_TIME;
          notes = 'حضور في الوقت المحدد';
        }
        // تأخير بسيط (10:01 إلى 10:30)
        else if (entryMin <= workStartMin + 30) {
          lateMinutes = entryMin - workStartMin;
          status = ATTENDANCE_STATUS.LATE;
          notes = `تأخير صباحي بسيط (${lateMinutes} دقيقة)`;
        }
        // تأخير كبير (بعد 10:30)
        else {
          lateMinutes = entryMin - workStartMin;
          status = ATTENDANCE_STATUS.VERY_LATE;
          notes = `تأخير صباحي كبير (${lateMinutes} دقيقة)`;
        }
      }

      // ب. فحص الانصراف المسائي
      if (punchCount === 1) {
        // بصمة واحدة فقط
        if (entryMin && entryMin < 780) { // قبل الساعة 13:00 ظهرأً
          notes += (notes ? ' | ' : '') + 'لم يسجل بصمة خروج';
        } else {
          notes = 'سجل بصمة خروج فقط (لم يبصم دخول)';
          status = ATTENDANCE_STATUS.MISSED_PUNCH;
        }
      } else if (exitMin !== null) {
        // انصراف مبكر قبل الساعة 3:00 (15:00)
        if (exitMin < workEndMin) {
          earlyLeaveMinutes = workEndMin - exitMin;
          const leaveNote = `انصراف مبكر قبل الدوام (${earlyLeaveMinutes} د)`;
          notes += (notes ? ' | ' : '') + leaveNote;

          if (status === ATTENDANCE_STATUS.ON_TIME) {
            status = ATTENDANCE_STATUS.EARLY_LEAVE;
          }
        }
        // دوام إضافي بعد وقت الدوام ومكافأة
        else if (rules.bonusEnabled && exitMin >= overtimeBonusMin) {
          overtimeMinutes = exitMin - workEndMin;
          if (overtimeMinutes > 0) {
            notes += (notes ? ' | ' : '') + `دوام إضافي (+${overtimeMinutes} د)`;
          }
        }
      }
    }

    results.push({
      employeeId: emp.id,
      empCode: emp.emp_code,
      name: emp.name,
      department: emp.department,
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

  // 7. حفظ النتائج في قاعدة البيانات (حفظ أو تحديث السجلات لليوم)
  const saveStmt = db.prepare(`
    INSERT INTO attendance_records (
      employee_id, date, first_punch, last_punch, punch_count,
      punch_details, status, late_minutes, early_leave_minutes,
      early_bonus_minutes, overtime_minutes, notes, year
    ) VALUES (
      @employeeId, @date, @firstPunch, @lastPunch, @punchCount,
      @punchDetails, @status, @lateMinutes, @earlyLeaveMinutes,
      @earlyBonusMinutes, @overtimeMinutes, @notes, @year
    ) ON CONFLICT(employee_id, date) DO UPDATE SET
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

  const saveMany = db.transaction((records) => {
    for (const r of records) {
      saveStmt.run(r);
    }
  });

  saveMany(results);

  // إحصائيات سريعة للنتيجة
  const stats = {
    date: dateStr,
    totalEmployees: results.length,
    present: results.filter(r => [ATTENDANCE_STATUS.ON_TIME, ATTENDANCE_STATUS.LATE, ATTENDANCE_STATUS.VERY_LATE, ATTENDANCE_STATUS.EARLY_LEAVE].includes(r.status)).length,
    onTime: results.filter(r => r.status === ATTENDANCE_STATUS.ON_TIME).length,
    late: results.filter(r => r.status === ATTENDANCE_STATUS.LATE).length,
    veryLate: results.filter(r => r.status === ATTENDANCE_STATUS.VERY_LATE).length,
    earlyLeave: results.filter(r => r.earlyLeaveMinutes > 0).length,
    absent: results.filter(r => r.status === ATTENDANCE_STATUS.ABSENT).length,
    onLeave: results.filter(r => r.status === ATTENDANCE_STATUS.ON_LEAVE).length,
    vipExempt: results.filter(r => r.status === ATTENDANCE_STATUS.VIP_EXEMPT).length,
    deptExcluded: results.filter(r => r.status === ATTENDANCE_STATUS.DEPT_EXCLUDED).length
  };

  return {
    stats,
    records: results
  };
}

module.exports = {
  getSystemRules,
  processAttendanceForDay
};
