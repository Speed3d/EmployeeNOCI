/**
 * Hint: سكربت سحب وتغذية موظفي المقر من ملف الإكسل الأساسي إلى قاعدة البيانات
 * يقرأ ملف اساس/اسماء موظفين المقر.xlsx ويدرج كافة السجلات مع الحفاظ على الأقسام والاستثناءات
 */
const path = require('path');
const db = require('../src/core/database');
const { parseMasterEmployeesFile } = require('../src/tools/excelHelper');
const { importEmployees } = require('../src/features/employees/employeeService');

function seedEmployees(force = false) {
  // Hint: التحقق مما إذا كان السوبر أدمن قد قام بتصفير شامل مع حذف الموظفين عمداً لمنع البذر التلقائي عند التشغيل
  const wipedSetting = db.prepare("SELECT value FROM system_settings WHERE key = 'employees_wiped_manually'").get();
  const isWipedManually = wipedSetting && wipedSetting.value === 'true';

  const currentCount = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;
  if ((currentCount > 0 || isWipedManually) && !force && !process.argv.includes('--force')) {
    if (isWipedManually && currentCount === 0) {
      console.log('تم تخطي البذر التلقائي للموظفين (النظام في وضع التصفير الشامل الفارغ).');
    } else {
      console.log(`قاعدة البيانات تحتوي بالفعل على ${currentCount} موظف (تم تخطي إعادة البذر التلقائي).`);
    }
    return;
  }

  const excelPath = path.join(__dirname, '../../اساس/اسماء موظفين المقر.xlsx');
  console.log(`جاري قراءة ملف الموظفين من: ${excelPath}`);

  const employees = parseMasterEmployeesFile(excelPath);
  console.log(`تم استخراج ${employees.length} موظف من الملف.`);

  // Hint: نفس منطق الاستيراد المستخدم في واجهة النظام (مع استبعاد أقسام الاستقالة والتنسيب والمتوفين افتراضياً)
  const summary = importEmployees(employees, { markDepartmentsExcluded: true });
  console.log(`✔ تمت المعالجة: ${summary.added} جديد، ${summary.updated} محدّث، ${summary.unchanged} بلا تغيير.`);

  // استعراض ملخص
  const total = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;
  const depts = db.prepare('SELECT COUNT(*) as count FROM departments').get().count;
  console.log(`الإجمالي في القاعدة: ${total} موظف موزعين على ${depts} قسم/حالة.`);
}

if (require.main === module) {
  seedEmployees();
}

module.exports = seedEmployees;
