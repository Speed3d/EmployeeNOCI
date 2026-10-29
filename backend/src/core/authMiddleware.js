/**
 * Hint: وسيط التحقق من الهوية والأمان وفحص الصلاحيات (RBAC)
 * - الرمز يُقبل من ترويسة Authorization فقط (لا من الرابط)
 * - الرمز المنتهي أو غير الصالح أو المُبطَل (token_version) = 401 مع رمز SESSION_EXPIRED
 * - الحساب المعطّل أو المحذوف = 401 مع رمز ACCOUNT_DISABLED
 * - كلمة المرور المؤقتة تمنع كل العمليات عدا تغييرها = 403 مع رمز PASSWORD_CHANGE_REQUIRED
 * - وضع الصيانة يمنع غير السوبر أدمن = 503 مع رمز MAINTENANCE
 */
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('./config');
const db = require('./database');
const { ROLES } = require('../shared/constants');

// Hint: المسارات المسموحة أثناء إلزام تغيير كلمة المرور المؤقتة
const PASSWORD_CHANGE_ALLOWED = new Set(['/api/auth/me', '/api/auth/profile']);

function deny(res, status, code, message, extra = {}) {
  return res.status(status).json({ success: false, code, message, ...extra });
}

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = typeof authHeader === 'string' && authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : null;

  if (!token) {
    return deny(res, 401, 'SESSION_EXPIRED', 'غير مصرح: يرجى تسجيل الدخول أولاً');
  }

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (_) {
    return deny(res, 401, 'SESSION_EXPIRED', 'انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول');
  }

  if (payload.purpose) {
    // رموز التنزيل المؤقتة لا تصلح للمصادقة العامة
    return deny(res, 401, 'SESSION_EXPIRED', 'رمز غير صالح لهذه العملية');
  }

  // جلب بيانات المستخدم الفعلية من القاعدة للتأكد من أنه لا يزال نشطاً وأن الرمز لم يُبطَل
  const currentUser = db.prepare(`
    SELECT id, username, full_name, role, is_active, can_manage_exclusions, can_recommit,
           token_version, must_change_password, deleted_at
    FROM users WHERE id = ?
  `).get(payload.id);

  if (!currentUser || !currentUser.is_active || currentUser.deleted_at) {
    return deny(res, 401, 'ACCOUNT_DISABLED', 'الحساب معطل أو غير موجود، يرجى مراجعة السوبر أدمن');
  }
  if ((payload.tv || 0) !== currentUser.token_version) {
    return deny(res, 401, 'SESSION_EXPIRED', 'انتهت صلاحية الجلسة بسبب تغيير بيانات الحساب، يرجى إعادة تسجيل الدخول');
  }

  req.user = currentUser;

  if (currentUser.must_change_password && !PASSWORD_CHANGE_ALLOWED.has(req.baseUrl + req.path)) {
    return deny(res, 403, 'PASSWORD_CHANGE_REQUIRED', 'يجب تغيير كلمة المرور المؤقتة قبل استخدام النظام');
  }

  // فحص وضع الصيانة: يُسمح فقط للسوبر أدمن بالمرور
  const maintenanceSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('maintenance_mode');
  const isMaintenance = maintenanceSetting && maintenanceSetting.value === 'true';

  if (isMaintenance && req.user.role !== ROLES.SUPER_ADMIN) {
    return deny(res, 503, 'MAINTENANCE', 'النظام في وضع الصيانة والتحديث حالياً، يرجى المحاولة لاحقاً', { is_maintenance: true });
  }

  next();
}

/**
 * Hint: مصادقة روابط التنزيل بتذكرة قصيرة العمر مرتبطة بنوع الملف ومعاملاته
 * تُستخدم بدل تمرير رمز الجلسة في الرابط
 */
function authenticateDownloadTicket(kind, paramNames) {
  return (req, res, next) => {
    const ticket = req.query.ticket;
    if (typeof ticket !== 'string' || !ticket) {
      return deny(res, 401, 'SESSION_EXPIRED', 'رابط التنزيل غير صالح أو منتهي الصلاحية');
    }
    let payload;
    try {
      payload = jwt.verify(ticket, JWT_SECRET);
    } catch (_) {
      return deny(res, 401, 'SESSION_EXPIRED', 'رابط التنزيل غير صالح أو منتهي الصلاحية');
    }
    if (payload.purpose !== 'download' || payload.kind !== kind) {
      return deny(res, 401, 'SESSION_EXPIRED', 'رابط التنزيل لا يخص هذا الملف');
    }
    const params = payload.params || {};
    for (const p of paramNames) {
      const expected = params[p] === undefined || params[p] === null ? '' : String(params[p]);
      const actual = req.query[p] === undefined ? '' : String(req.query[p]);
      if (expected !== actual) {
        return deny(res, 401, 'SESSION_EXPIRED', 'رابط التنزيل لا يطابق الملف المطلوب');
      }
    }
    const user = db.prepare(`
      SELECT id, username, full_name, role, is_active, can_manage_exclusions, can_recommit, token_version, deleted_at
      FROM users WHERE id = ?
    `).get(payload.uid);
    if (!user || !user.is_active || user.deleted_at || user.token_version !== payload.tv) {
      return deny(res, 401, 'ACCOUNT_DISABLED', 'الحساب غير صالح لتنزيل هذا الملف');
    }
    req.user = user;
    next();
  };
}

// Hint: حارس حصر الوصول للسوبر أدمن فقط
function requireSuperAdmin(req, res, next) {
  if (req.user && req.user.role === ROLES.SUPER_ADMIN) {
    return next();
  }
  return res.status(403).json({
    success: false,
    message: 'عذراً، هذه العملية محصورة بالسوبر أدمن فقط'
  });
}

// Hint: حارس السماح لأدوار محددة
function requireRoles(allowedRoles = []) {
  return (req, res, next) => {
    if (req.user && (req.user.role === ROLES.SUPER_ADMIN || allowedRoles.includes(req.user.role))) {
      return next();
    }
    return res.status(403).json({
      success: false,
      message: 'ليس لديك الصلاحية الكافية للوصول إلى هذا القسم'
    });
  };
}

module.exports = {
  authenticateToken,
  authenticateDownloadTicket,
  requireSuperAdmin,
  requireRoles
};
