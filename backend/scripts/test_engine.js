/**
 * Hint: عرض توضيحي لتشغيل محرك البصمة على الملف النموذجي (معاينة فقط، بلا حفظ)
 * للاختبارات الآلية الفعلية استخدم: npm test
 */
const path = require('path');
const { parseDailyAttendanceFile } = require('../src/tools/excelHelper');
const { processAttendanceForDay } = require('../src/features/attendance/attendanceEngine');

const sampleFile = path.join(__dirname, '../../اساس/نموذج كشف الحضور/20-10-2026.xlsx');
console.log('جاري فحص ملف البصمة اليومي:', sampleFile);

const parsed = parseDailyAttendanceFile(sampleFile);
console.log(`تم استخراج ${parsed.totalPunchRows} حركة بصمة في ${parsed.days.length} يوم (صفوف غير صالحة: ${parsed.invalidRows}).`);

for (const day of parsed.days) {
  const outcome = processAttendanceForDay(day.date, day.employees);
  console.log(`\n=== نتائج اليوم ${day.date} (${day.employees.length} موظف بصم) ===`);
  console.table(outcome.stats);

  console.log('\nعينة من 5 موظفين مع تشخيص حالتهم:');
  for (const r of outcome.records.slice(0, 5)) {
    console.log(`- كود [${r.empCode}] ${r.name} (${r.department}):`);
    console.log(`  الحالة: ${r.status} | أول بصمة: ${r.firstPunch} | آخر بصمة: ${r.lastPunch}`);
    console.log(`  تأخير: ${r.lateMinutes} د | انصراف مبكر: ${r.earlyLeaveMinutes} د | مكافأة مبكرة: ${r.earlyBonusMinutes} د | ملاحظات: ${r.notes}\n`);
  }
}
