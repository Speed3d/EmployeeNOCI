/**
 * Hint: الحماية من هجمات التخمين (Brute-Force) وتحديد عنوان العميل الحقيقي
 * - خلف Cloudflare Tunnel يصل الطلب من loopback، فيُعتمد CF-Connecting-IP فقط في هذه الحالة
 * - لا يُعتمد X-Forwarded-For إطلاقاً لأنه قابل للتزوير من العميل
 * - عدّادان مستقلان: لكل عنوان IP ولكل هدف (اسم مستخدم أو حساب)، فتغيير العنوان لا يتجاوز الحظر
 */
const WINDOW_MS = 15 * 60 * 1000;
const MAX_PER_IP = 15;
const MAX_PER_TARGET = 10;

const attempts = new Map();

function isLoopback(addr) {
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

function getClientIp(req) {
  const remote = (req.socket && req.socket.remoteAddress) || 'unknown';
  if (isLoopback(remote)) {
    const cf = req.headers['cf-connecting-ip'];
    if (typeof cf === 'string' && cf.trim() && cf.length <= 64) return cf.trim();
  }
  return remote;
}

// Hint: وسيط يثبت العنوان الحقيقي في req.clientIp لاستخدامه في سجل الحركات
function attachClientIp(req, res, next) {
  req.clientIp = getClientIp(req);
  next();
}

function getRecord(key) {
  const rec = attempts.get(key);
  if (!rec) return null;
  if (Date.now() - rec.firstAt > WINDOW_MS) {
    attempts.delete(key);
    return null;
  }
  return rec;
}

function keysFor(scope, req, target) {
  const keys = [{ key: `${scope}:ip:${getClientIp(req)}`, max: MAX_PER_IP }];
  if (target !== undefined && target !== null && target !== '') {
    keys.push({ key: `${scope}:target:${String(target).toLowerCase()}`, max: MAX_PER_TARGET });
  }
  return keys;
}

function isBlocked(scope, req, target) {
  return keysFor(scope, req, target).some(({ key, max }) => {
    const rec = getRecord(key);
    return rec && rec.count >= max;
  });
}

function recordFailure(scope, req, target) {
  const now = Date.now();
  for (const { key } of keysFor(scope, req, target)) {
    const rec = getRecord(key);
    if (rec) rec.count += 1;
    else attempts.set(key, { count: 1, firstAt: now });
  }
}

function clearFailures(scope, req, target) {
  for (const { key } of keysFor(scope, req, target)) attempts.delete(key);
}

// تنظيف دوري للسجلات المنتهية
setInterval(() => {
  const now = Date.now();
  for (const [key, rec] of attempts) {
    if (now - rec.firstAt > WINDOW_MS) attempts.delete(key);
  }
}, WINDOW_MS).unref();

module.exports = {
  getClientIp,
  attachClientIp,
  isBlocked,
  recordFailure,
  clearFailures
};
