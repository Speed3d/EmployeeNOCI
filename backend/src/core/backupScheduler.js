/**
 * Hint: النسخ الاحتياطي التلقائي لقاعدة البيانات
 * - نسخة عند الإقلاع إذا مر أكثر من 24 ساعة على آخر نسخة تلقائية، ثم كل 24 ساعة
 * - الاحتفاظ بآخر 30 نسخة تلقائية فقط؛ النسخ اليدوية لا تُحذف تلقائياً
 */
const fs = require('fs');
const path = require('path');
const db = require('./database');

const BACKUPS_DIR = path.join(path.dirname(db.name), 'backups');
const AUTO_PREFIX = 'auto_';
const KEEP_AUTO = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

function ensureBackupsDir() {
  if (!fs.existsSync(BACKUPS_DIR)) {
    fs.mkdirSync(BACKUPS_DIR, { recursive: true });
  }
}

// Hint: طابع زمني بتوقيت بغداد صالح لأسماء الملفات (YYYY-MM-DD_HH-mm-ss)
function baghdadStamp(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Baghdad',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  }).format(date).replace(/[/:]/g, '-').replace(', ', '_');
}

/**
 * Hint: إنشاء نسخة احتياطية متسقة باسم محدد البادئة؛ ترمي خطأ عند الفشل
 */
async function createBackupFile(prefix = 'backup_noci_') {
  ensureBackupsDir();
  const filename = `${prefix}${baghdadStamp()}.db`;
  const destPath = path.join(BACKUPS_DIR, filename);
  db.pragma('wal_checkpoint(TRUNCATE)');
  await db.backup(destPath);
  return { filename, destPath, size: fs.statSync(destPath).size };
}

function listAutoBackups() {
  if (!fs.existsSync(BACKUPS_DIR)) return [];
  return fs.readdirSync(BACKUPS_DIR)
    .filter(f => f.startsWith(AUTO_PREFIX) && f.endsWith('.db'))
    .map(f => ({ f, t: fs.statSync(path.join(BACKUPS_DIR, f)).mtimeMs }))
    .sort((a, b) => b.t - a.t);
}

async function runAutoBackupIfDue() {
  const latest = listAutoBackups()[0];
  if (latest && Date.now() - latest.t < DAY_MS) return null;

  const result = await createBackupFile(AUTO_PREFIX);
  for (const old of listAutoBackups().slice(KEEP_AUTO)) {
    try { fs.unlinkSync(path.join(BACKUPS_DIR, old.f)); } catch (_) {}
  }
  console.log(`✔ نسخة احتياطية تلقائية: ${result.filename}`);
  return result;
}

function startAutoBackups() {
  const run = () => runAutoBackupIfDue().catch(err => console.error('فشل النسخ الاحتياطي التلقائي:', err.message));
  run();
  const timer = setInterval(run, 60 * 60 * 1000);
  timer.unref();
  return timer;
}

module.exports = {
  BACKUPS_DIR,
  createBackupFile,
  runAutoBackupIfDue,
  startAutoBackups,
  baghdadStamp
};
