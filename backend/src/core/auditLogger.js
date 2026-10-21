/**
 * Hint: مسجل الحركات الأمني والتدقيق (Audit Logger)
 * يسجل كل عملية يقوم بها أي مستخدم (تسجيل دخول، رفع بصمة، تعديل موظف، تغيير إعدادات)
 */
const db = require('./database');

function logAction(userId, userName, action, details = '', ipAddress = '') {
  try {
    const stmt = db.prepare(`
      INSERT INTO audit_logs (user_id, user_name, action, details, ip_address)
      VALUES (?, ?, ?, ?, ?)
    `);
    stmt.run(userId || null, userName || 'زائر', action, typeof details === 'object' ? JSON.stringify(details) : details, ipAddress || 'محلي');
  } catch (error) {
    console.error('فشل تسجيل الحركة في سجل التدقيق:', error.message);
  }
}

module.exports = {
  logAction
};
