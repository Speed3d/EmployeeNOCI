/**
 * Hint: منطق مشترك للموظفين يُستخدم من المتحكم وسكربت البذر
 * - نقل الموظف بين الأقسام مع تسجيله في سجل التنقلات
 * - استيراد قائمة الموظفين من الإكسل مع ملخص تفصيلي
 */
const db = require('../../core/database');

const EMPLOYEE_STATUSES = ['نشط', 'استقالة', 'تنسيب', 'متوفى', 'منتهية خدماته'];

/**
 * Hint: نقل موظف داخل معاملة قائمة؛ يُسجل في employee_transfers إن توفر منفذ العملية
 */
function transferInTx(employeeId, fromDept, toDept, userId, reason = '') {
  db.prepare('INSERT OR IGNORE INTO departments (name) VALUES (?)').run(toDept);
  db.prepare('UPDATE employees SET department = ? WHERE id = ?').run(toDept, employeeId);
  if (userId) {
    db.prepare(`
      INSERT INTO employee_transfers (employee_id, from_department, to_department, transferred_by, reason)
      VALUES (?, ?, ?, ?, ?)
    `).run(employeeId, fromDept, toDept, userId, reason || '');
  }
}

/**
 * Hint: استيراد/تحديث الموظفين من قائمة مستخرجة من ملف الإكسل الأساسي
 * - لا يلغي استثناء VIP اليدوي (يُضبط الاستثناء فقط عندما يشير الملف لمنصب قيادي)
 * - تغيير القسم يمر بسجل التنقلات
 * - الموظفون الموجودون في النظام وغير الموجودين في الملف يُعرضون فقط دون تعديل
 * @param {Array} list - ناتج parseMasterEmployeesFile
 * @param {Object} options - { userId, markDepartmentsExcluded }
 */
function importEmployees(list, { userId = null, markDepartmentsExcluded = false } = {}) {
  const summary = { added: 0, updated: 0, transferred: 0, unchanged: 0, restored: 0, missingFromFile: [] };

  const findStmt = db.prepare('SELECT * FROM employees WHERE emp_code = ?');
  const insertStmt = db.prepare(`
    INSERT INTO employees (emp_code, name, department, status, is_exempt, exempt_reason)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  const updateStmt = db.prepare(`
    UPDATE employees SET name = ?, status = ?, is_exempt = ?, exempt_reason = ?, deleted_at = NULL WHERE id = ?
  `);
  const insertDeptStmt = db.prepare('INSERT OR IGNORE INTO departments (name, is_excluded) VALUES (?, ?)');

  const codesInFile = new Set();

  db.transaction(() => {
    for (const e of list) {
      codesInFile.add(e.empCode);
      const isSpecialDept = e.status !== 'نشط';
      insertDeptStmt.run(e.department, markDepartmentsExcluded && isSpecialDept ? 1 : 0);

      const existing = findStmt.get(e.empCode);
      if (!existing) {
        insertStmt.run(e.empCode, e.name, e.department, e.status, e.isExempt, e.exemptReason || '');
        summary.added++;
        continue;
      }

      // Hint: الاستثناء اليدوي يبقى ما لم يحدد الملف منصباً قيادياً صراحة
      const isExempt = e.isExempt ? 1 : existing.is_exempt;
      const exemptReason = e.isExempt ? e.exemptReason : existing.exempt_reason;

      let changed = existing.name !== e.name
        || existing.status !== e.status
        || existing.is_exempt !== isExempt
        || (existing.exempt_reason || '') !== (exemptReason || '');

      if (existing.deleted_at) {
        summary.restored++;
        changed = true;
      }

      if (existing.department !== e.department) {
        transferInTx(existing.id, existing.department, e.department, userId, 'تحديث من ملف الموظفين');
        summary.transferred++;
      }

      if (changed) {
        updateStmt.run(e.name, e.status, isExempt, exemptReason || '', existing.id);
        summary.updated++;
      } else if (existing.department === e.department) {
        summary.unchanged++;
      }
    }
  })();

  summary.missingFromFile = db.prepare('SELECT id, emp_code, name, department, status FROM employees WHERE deleted_at IS NULL ORDER BY CAST(emp_code AS INTEGER)')
    .all()
    .filter(e => !codesInFile.has(e.emp_code));

  return summary;
}

module.exports = {
  EMPLOYEE_STATUSES,
  transferInTx,
  importEmployees
};
