/**
 * Hint: ملف إعدادات الخادم والبيئة
 * يحدد المنافذ ومفاتيح التشفير ومسار قاعدة البيانات ومجلد المرفقات
 * المفاتيح السرية تُحفظ خارج مجلد data حتى لا تُنسخ مع قاعدة البيانات أو نسخها الاحتياطية
 */
require('dotenv').config({ quiet: true });
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const backendRoot = path.join(__dirname, '../..');

// التأكد من وجود مجلد البيانات data
const dataDir = path.join(backendRoot, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Hint: مجلد المفاتيح السرية (خارج data) — يمكن تغييره بمتغير البيئة KEYS_DIR
const KEYS_DIR = process.env.KEYS_DIR || path.join(backendRoot, '.keys');
if (!fs.existsSync(KEYS_DIR)) {
  fs.mkdirSync(KEYS_DIR, { recursive: true });
}
const keysPath = path.join(KEYS_DIR, 'secrets.json');
const legacySecretsPath = path.join(dataDir, '.secrets.json');

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return {};
  }
}

let secrets = fs.existsSync(keysPath) ? readJson(keysPath) : {};

// Hint: ترحيل لمرة واحدة من الموقع القديم data/.secrets.json إلى مجلد المفاتيح
if (fs.existsSync(legacySecretsPath) && !process.env.KEYS_DIR) {
  const legacy = readJson(legacySecretsPath);
  if (!secrets.jwtSecret && legacy.jwtSecret) secrets.jwtSecret = legacy.jwtSecret;
  if (!secrets.cipherKey && legacy.cipherKey) secrets.cipherKey = legacy.cipherKey;
}

let changed = false;
if (!secrets.jwtSecret) {
  secrets.jwtSecret = crypto.randomBytes(32).toString('hex');
  changed = true;
}
if (!secrets.cipherKey) {
  secrets.cipherKey = crypto.randomBytes(32).toString('hex');
  changed = true;
}
if (changed || !fs.existsSync(keysPath)) {
  fs.writeFileSync(keysPath, JSON.stringify(secrets, null, 2), { encoding: 'utf8', mode: 0o600 });
}
if (fs.existsSync(legacySecretsPath) && !process.env.KEYS_DIR) {
  try { fs.unlinkSync(legacySecretsPath); } catch (_) {}
}

const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';
const JWT_SECRET = process.env.JWT_SECRET || secrets.jwtSecret;
const CIPHER_KEY = Buffer.from(process.env.CIPHER_KEY || secrets.cipherKey, 'hex');
const DB_PATH = process.env.DB_PATH || path.join(dataDir, 'attendance.db');

// Hint: الأصول المسموحة لطلبات CORS (مفصولة بفواصل)؛ الأصل نفسه مسموح دائماً
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

// مجلد رفع الملفات (الصور الشخصية والشعارات)
const UPLOADS_DIR = process.env.UPLOADS_DIR || path.join(backendRoot, 'uploads');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

module.exports = {
  PORT,
  HOST,
  JWT_SECRET,
  CIPHER_KEY,
  DB_PATH,
  UPLOADS_DIR,
  ALLOWED_ORIGINS
};
