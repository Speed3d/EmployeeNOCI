/**
 * Hint: اختبار تشغيل محرك البصمة الذكي على الملف النموذجي المرفق
 */
const path = require('path');
const { parseDailyAttendanceFile } = require('../src/tools/excelHelper');
const { processAttendanceForDay } = require('../src/features/attendance/attendanceEngine');

const sampleFile = path.join(__dirname, '../../اساس/نموذج كشف الحضور/20-10-2026.xlsx');
console.log('جاري فحص ملف البصمة اليومي:', sampleFile);

const parsed = parseDailyAttendanceFile(sampleFile);
console.log(`تم استخراج ${parsed.uniqueEmployeesCount} موظف من أصل ${parsed.totalPunchRows} حركة بصمة.`);
console.log('التاريخ المكتشف في الملف:', parsed.detectedDate);

const outcome = processAttendanceForDay(parsed.detectedDate, parsed.employees);
console.log('\n=== نتائج المعالجة والتشخيص لليوم: ===');
console.table(outcome.stats);

console.log('\nعينة من 5 موظفين مع تشخيص حالتهم:');
for (const r of outcome.records.slice(0, 5)) {
  console.log(`- كود [${r.empCode}] ${r.name} (${r.department}):`);
  console.log(`  الحالة: ${r.status} | أول بصمة: ${r.firstPunch} | آخر بصمة: ${r.lastPunch}`);
  console.log(`  تأخير: ${r.lateMinutes} د | انصراف مبكر: ${r.earlyLeaveMinutes} د | مكافأة مبكرة: ${r.earlyBonusMinutes} د | ملاحظات: ${r.notes}\n`);
}
