/**
 * Hint: أدوات مساعدة للاختبارات الآلية
 * كل ملف اختبار يعمل في عملية مستقلة بقاعدة بيانات ومفاتيح ومجلد رفع مؤقتة، فلا تُلمس بيانات الإنتاج أبداً
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'noci-test-'));
process.env.DB_PATH = path.join(tmpRoot, 'test.db');
process.env.KEYS_DIR = path.join(tmpRoot, 'keys');
process.env.UPLOADS_DIR = path.join(tmpRoot, 'uploads');
process.env.NOCI_DISABLE_AUTO_BACKUP = '1';
process.env.NOCI_INITIAL_ADMIN_PASSWORD = 'Admin@123456';

const xlsx = require('xlsx');
const app = require('../src/app');
const db = require('../src/core/database');

const ROOT = path.join(__dirname, '../..');
const MASTER_FILE = path.join(ROOT, 'اساس', 'اسماء موظفين المقر.xlsx');
const SAMPLE_DAY_FILE = path.join(ROOT, 'اساس', 'نموذج كشف الحضور', '20-10-2026.xlsx');
const ADMIN_PASSWORD = 'Admin2026pass';

let server;
let base;

async function start() {
  await new Promise(resolve => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}/api`;
}

async function stop() {
  await new Promise(resolve => server.close(resolve));
  db.close();
}

async function api(method, url, body, token, headers = {}) {
  const h = { ...headers };
  if (body !== undefined) h['Content-Type'] = 'application/json';
  if (token) h.Authorization = `Bearer ${token}`;
  const res = await fetch(base + url, {
    method,
    headers: h,
    body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body))
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch (_) { data = text; }
  return { status: res.status, body: data, headers: res.headers };
}

async function upload(url, fileOrBuffer, token, fileName = 'file.xlsx') {
  const buf = Buffer.isBuffer(fileOrBuffer) ? fileOrBuffer : fs.readFileSync(fileOrBuffer);
  const name = Buffer.isBuffer(fileOrBuffer) ? fileName : path.basename(fileOrBuffer);
  const fd = new FormData();
  fd.append('file', new Blob([buf]), name);
  const res = await fetch(base + url, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: fd });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch (_) { data = text; }
  return { status: res.status, body: data };
}

async function login(username, password) {
  const r = await api('POST', '/auth/login', { username, password });
  if (r.status !== 200) throw new Error(`login failed for ${username}: ${r.status} ${JSON.stringify(r.body)}`);
  return r.body.data;
}

// Hint: دخول الأدمن الافتراضي مع تغيير كلمة المرور المؤقتة الإلزامي
async function adminToken() {
  const first = await api('POST', '/auth/login', { username: 'admin', password: ADMIN_PASSWORD });
  if (first.status === 200) return first.body.data.token;
  const initial = await login('admin', 'Admin@123456');
  const changed = await api('PUT', '/auth/profile', { oldPassword: 'Admin@123456', newPassword: ADMIN_PASSWORD }, initial.token);
  if (changed.status !== 200) throw new Error('admin password change failed: ' + JSON.stringify(changed.body));
  return (await login('admin', ADMIN_PASSWORD)).token;
}

// Hint: بناء ملف بصمة إكسل من صفوف [كود، وقت]
function makePunchFile(rows) {
  const wb = xlsx.utils.book_new();
  const aoa = [['المعرف', 'الاسم', 'القسم', 'الوقت'], ...rows.map(([code, ts]) => [`'${code}`, 'موظف', 'قسم', ts])];
  xlsx.utils.book_append_sheet(wb, xlsx.utils.aoa_to_sheet(aoa), 'Sheet1');
  return xlsx.write(wb, { type: 'buffer', bookType: 'xlsx' });
}

// Hint: معاينة ملف ثم اعتماد يوم محدد منه عبر معرف المعاينة
async function previewAndCommit(token, buffer, date) {
  const prev = await upload('/attendance/preview', buffer, token, 'day.xlsx');
  if (prev.status !== 200) throw new Error('preview failed: ' + JSON.stringify(prev.body));
  const commit = await api('POST', '/attendance/commit', { previewId: prev.body.data.previewId, date }, token);
  if (commit.status !== 200) throw new Error('commit failed: ' + JSON.stringify(commit.body));
  return commit.body.data;
}

function activeEmployee(offset = 0) {
  return db.prepare(`
    SELECT id, emp_code FROM employees
    WHERE status = 'نشط' AND is_exempt = 0 AND deleted_at IS NULL
    ORDER BY CAST(emp_code AS INTEGER) LIMIT 1 OFFSET ?
  `).get(offset);
}

module.exports = {
  db,
  start,
  stop,
  api,
  upload,
  login,
  adminToken,
  makePunchFile,
  previewAndCommit,
  activeEmployee,
  MASTER_FILE,
  SAMPLE_DAY_FILE,
  ADMIN_PASSWORD,
  get base() { return base; }
};
