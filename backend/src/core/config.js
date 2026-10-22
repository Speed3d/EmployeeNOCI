/**
 * Hint: ملف إعدادات الخادم والبيئة
 * يحدد المنافذ ومفاتيح التشفير العشوائية الدائمة ومسار قاعدة البيانات ومجلد المرفقات
 */
require('dotenv').config();
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// التأكد من وجود مجلد البيانات data
const dataDir = path.join(__dirname, '../../data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// إنشاء أو تحميل مفاتيح الأمان العشوائية المستمرة لكل تثبيت
const secretsPath = path.join(dataDir, '.secrets.json');
let secrets = {};
if (fs.existsSync(secretsPath)) {
  try {
    secrets = JSON.parse(fs.readFileSync(secretsPath, 'utf8'));
  } catch (err) {
    secrets = {};
  }
}

if (!secrets.jwtSecret) {
  secrets.jwtSecret = process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');
}
if (!secrets.cipherKey) {
  secrets.cipherKey = process.env.CIPHER_KEY || crypto.randomBytes(32).toString('hex');
}

fs.writeFileSync(secretsPath, JSON.stringify(secrets, null, 2), 'utf8');

const PORT = process.env.PORT || 5000;
const JWT_SECRET = secrets.jwtSecret;
const CIPHER_KEY = Buffer.from(secrets.cipherKey, 'hex');
const DB_PATH = process.env.DB_PATH || path.join(dataDir, 'attendance.db');

// مجلد رفع الملفات (الصور الشخصية والشعارات)
const UPLOADS_DIR = path.join(__dirname, '../../uploads');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

module.exports = {
  PORT,
  JWT_SECRET,
  CIPHER_KEY,
  DB_PATH,
  UPLOADS_DIR
};
