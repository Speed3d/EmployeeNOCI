/**
 * Hint: ملف إعدادات الخادم والبيئة
 * يحدد المنافذ ومفاتيح التشفير ومسار قاعدة البيانات
 */
require('dotenv').config();
const path = require('path');

const PORT = process.env.PORT || 5000;
const JWT_SECRET = process.env.JWT_SECRET || 'noci_attendance_super_secret_jwt_key_2026';
const DB_PATH = process.env.DB_PATH || path.join(__dirname, '../../data/attendance.db');

module.exports = {
  PORT,
  JWT_SECRET,
  DB_PATH
};
