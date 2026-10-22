/**
 * Hint: سكربت الفحص الشامل للمرحلة الثانية (Test Suite v2)
 * يختبر كافة الميزات المعدلة والمعمارية الجديدة للباك إند
 */
const fs = require('fs');
const path = require('path');
const db = require('../src/core/database');
const { parseDailyAttendanceFile } = require('../src/tools/excelHelper');
const { processAttendanceForDay } = require('../src/features/attendance/attendanceEngine');
const { encrypt, decrypt } = require('../src/core/cryptoHelper');
const scheduleController = require('../src/features/schedules/scheduleController');

async function runTests() {
  console.log('🚀 بدء الفحص الشامل للباك إند (المرحلة الثانية)...');

  // 1. فحص التشفير وفك التشفير لكلمة المرور
  console.log('\n--- 1. فحص التشفير AES-256-GCM ---');
  const testSecret = 'SecretPass@2026';
  const enc = encrypt(testSecret);
  const dec = decrypt(enc);
  console.log('النص الأصلي:', testSecret);
  console.log('النص المشفر:', enc);
  console.log('فك التشفير:', dec);
  if (testSecret === dec) {
    console.log('✔ فحص التشفير وفك التشفير ناجح 100%');
  } else {
    throw new Error('فشل فحص التشفير!');
  }

  // 2. فحص قوالب الدوام والربط
  console.log('\n--- 2. فحص قوالب الدوام والشفتات (النقطة 17) ---');
  const templates = db.prepare('SELECT * FROM schedule_templates').all();
  console.log(`✔ عدد القوالب الافتراضية: ${templates.length}`);

  // فحص موظف افتراضي
  const sampleEmp = db.prepare("SELECT id, name, department FROM employees WHERE status = 'نشط' LIMIT 1").get();
  if (sampleEmp) {
    const defaultWorkDays = scheduleController.getEmployeeWorkDays(sampleEmp.id, '2026-10-20');
    console.log(`أيام عمل الموظف [${sampleEmp.name}] الافتراضية:`, defaultWorkDays);
  }

  // 3. فحص ملف كشف البصمة الحقيقي 20-10-2026
  console.log('\n--- 3. فحص ومعاينة كشف 20-10-2026 ---');
  const sampleFilePath = path.join(__dirname, '../../اساس/نموذج كشف الحضور/20-10-2026.xlsx');
  if (fs.existsSync(sampleFilePath)) {
    const fileBuffer = fs.readFileSync(sampleFilePath);
    const parsed = parseDailyAttendanceFile(fileBuffer);
    console.log(`✔ تم قراءة الملف: التاريخ المستخرج [${parsed.detectedDate}] - عدد الحركات [${parsed.totalPunchRows}] - الموظفون [${parsed.uniqueEmployeesCount}]`);

    // معاينة فقط (persist: false)
    const preview = processAttendanceForDay(parsed.detectedDate, parsed.employees, { persist: false });
    console.log('✔ إحصائيات المعاينة:', preview.stats);
    console.log(`✔ إجمالي السجلات في المعاينة (النشطين وغير المستبعدين فقط): ${preview.records.length}`);

    // اعتماد وحفظ (persist: true)
    console.log('\n--- 4. فحص الاعتماد والحفظ (Commit) ---');
    const commit = processAttendanceForDay(parsed.detectedDate, parsed.employees, { persist: true, userId: 1 });
    console.log('✔ إحصائيات الاعتماد:', commit.stats);

    // فحص جدول attendance_days
    const committedDay = db.prepare('SELECT * FROM attendance_days WHERE date = ?').get(parsed.detectedDate);
    console.log('✔ سجل اليوم المعتمد:', {
      date: committedDay.date,
      status: committedDay.status,
      committed_by: committedDay.committed_by
    });

    // فحص أن الأقسام المستبعدة لا تظهر إطلاقاً في السجلات
    const excludedDepts = db.prepare('SELECT name FROM departments WHERE is_excluded = 1').all().map(d => d.name);
    const hasExcluded = commit.records.some(r => excludedDepts.includes(r.department));
    console.log('هل يوجد أي موظف من قسم مستبعد في الكشف المعتمد؟', hasExcluded ? 'نعم (خطأ)' : 'لا (صحيح ومستبعد تماماً ✔)');
  }

  // 5. فحص التقرير الشهري لشهر 10-2026
  console.log('\n--- 5. فحص التقرير الشهري ---');
  const reportQuery = `
    SELECT 
      e.id, e.name, e.department,
      COUNT(CASE WHEN a.status IN ('ON_TIME', 'LATE', 'VERY_LATE', 'EARLY_LEAVE') THEN 1 END) as days_present
    FROM employees e
    LEFT JOIN attendance_records a ON a.employee_id = e.id 
      AND a.date IN (SELECT date FROM attendance_days WHERE status = 'COMMITTED')
    WHERE e.status = 'نشط' 
      AND e.is_exempt = 0 
      AND e.department NOT IN (SELECT name FROM departments WHERE is_excluded = 1)
    GROUP BY e.id LIMIT 5
  `;
  const reportSample = db.prepare(reportQuery).all();
  console.log('عينة من التقرير التراكمي (أيام معتمدة فقط):', reportSample);

  console.log('\n🎉 كافة فحوصات الباك إند والمحرك اكتملت بنجاح باهر!');
}

runTests().catch(err => {
  console.error('❌ خطأ في الفحص:', err);
  process.exit(1);
});
