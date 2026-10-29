/**
 * Hint: مشرف تشغيل الخادم في الخلفية
 * - يشغّل src/app.js ويعيد تشغيله تلقائياً بعد 3 ثوانٍ إذا توقف لأي سبب
 * - يكتب مخرجات الخادم وأخطاءه في backend/logs/server.log مع تدوير الملف عند 5MB والاحتفاظ بـ 5 نسخ
 * التشغيل: npm run start:supervised  (يستخدمه run-silent.vbs و "تشغيل النظام.bat")
 */
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const BACKEND_DIR = path.join(__dirname, '..');
const LOG_DIR = path.join(BACKEND_DIR, 'logs');
const LOG_FILE = path.join(LOG_DIR, 'server.log');
const MAX_LOG_BYTES = 5 * 1024 * 1024;
const KEEP_LOGS = 5;
const RESTART_DELAY_MS = 3000;

fs.mkdirSync(LOG_DIR, { recursive: true });

function rotateIfNeeded() {
  try {
    if (!fs.existsSync(LOG_FILE) || fs.statSync(LOG_FILE).size < MAX_LOG_BYTES) return;
    for (let i = KEEP_LOGS - 1; i >= 1; i--) {
      const from = `${LOG_FILE}.${i}`;
      if (fs.existsSync(from)) fs.renameSync(from, `${LOG_FILE}.${i + 1}`);
    }
    fs.renameSync(LOG_FILE, `${LOG_FILE}.1`);
    const overflow = `${LOG_FILE}.${KEEP_LOGS + 1}`;
    if (fs.existsSync(overflow)) fs.unlinkSync(overflow);
  } catch (err) {
    process.stderr.write(`تعذر تدوير ملف السجل: ${err.message}\n`);
  }
}

function log(line) {
  rotateIfNeeded();
  const stamp = new Date().toISOString();
  fs.appendFileSync(LOG_FILE, `[${stamp}] ${line}\n`, 'utf8');
}

let stopping = false;
let child = null;

function start() {
  log('▶ تشغيل الخادم...');
  child = spawn(process.execPath, [path.join(BACKEND_DIR, 'src', 'app.js')], {
    cwd: BACKEND_DIR,
    env: process.env,
    windowsHide: true
  });

  const pipe = (stream, prefix) => {
    stream.setEncoding('utf8');
    stream.on('data', chunk => {
      for (const line of chunk.split(/\r?\n/)) {
        if (line.trim()) log(`${prefix}${line}`);
      }
    });
  };
  pipe(child.stdout, '');
  pipe(child.stderr, '[خطأ] ');

  child.on('exit', (code, signal) => {
    log(`■ توقف الخادم (code=${code}, signal=${signal})`);
    child = null;
    if (!stopping) {
      log(`↻ إعادة التشغيل خلال ${RESTART_DELAY_MS / 1000} ثوانٍ`);
      setTimeout(start, RESTART_DELAY_MS);
    }
  });
}

function shutdown() {
  stopping = true;
  if (child) child.kill();
  setTimeout(() => process.exit(0), 500);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

start();
