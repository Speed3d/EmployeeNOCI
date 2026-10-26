/**
 * Hint: سكربت سحب وتغذية موظفي المقر من ملف الإكسل الأساسي إلى قاعدة البيانات
 * يقرأ ملف اساس/اسماء موظفين المقر.xlsx ويدرج كافة السجلات مع الحفاظ على الأقسام والاستثناءات
 */
const path = require('path');
const db = require('../src/core/database');
const { parseMasterEmployeesFile } = require('../src/tools/excelHelper');

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

  const insertEmpStmt = db.prepare(`
    INSERT INTO employees (emp_code, name, department, status, is_exempt, exempt_reason)
    VALUES (@empCode, @name, @department, @status, @isExempt, @exemptReason)
    ON CONFLICT(emp_code) DO UPDATE SET
      name = excluded.name,
      department = excluded.department,
      status = excluded.status,
      is_exempt = excluded.is_exempt,
      exempt_reason = excluded.exempt_reason
  `);

  const insertDeptStmt = db.prepare(`
    INSERT OR IGNORE INTO departments (name, is_excluded)
    VALUES (?, ?)
  `);

  const insertMany = db.transaction((emps) => {
    for (const emp of emps) {
      insertEmpStmt.run(emp);

      // استبعاد الأقسام الخاصة كافتراضي (استقالة، تنسيب، متوفين)
      let isExcluded = 0;
      if (emp.status !== 'نشط' || emp.department.includes('استقالة') || emp.department.includes('تنسيب') || emp.department.includes('متوف')) {
        isExcluded = 1;
      }
      insertDeptStmt.run(emp.department, isExcluded);
    }
  });

  insertMany(employees);
  console.log(`✔ تم حفظ وتحديث ${employees.length} موظف في قاعدة البيانات بنجاح!`);

  // استعراض ملخص
  const total = db.prepare('SELECT COUNT(*) as count FROM employees').get().count;
  const depts = db.prepare('SELECT COUNT(*) as count FROM departments').get().count;
  console.log(`الإجمالي في القاعدة: ${total} موظف موزعين على ${depts} قسم/حالة.`);
}

if (require.main === module) {
  seedEmployees();
}

module.exports = seedEmployees;
