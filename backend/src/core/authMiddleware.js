/**
 * Hint: وسيط التحقق من الهوية والأمان وفحص الصلاحيات (RBAC)
 * يتحقق من صحة التوكن، ويفحص وضع الصيانة لمنع المستخدمين العاديين أثنائها
 */
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('./config');
const db = require('./database');
const { ROLES } = require('../shared/constants');

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = (authHeader && authHeader.split(' ')[1]) || req.query.token;

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'غير مصرح: يرجى تسجيل الدخول أولاً'
    });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({
        success: false,
        message: 'انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول'
      });
    }

    // جلب بيانات المستخدم الفعلية من القاعدة للتأكد من أنه لا يزال نشطاً
    const currentUser = db.prepare('SELECT id, username, full_name, role, is_active FROM users WHERE id = ?').get(user.id);
    if (!currentUser || !currentUser.is_active) {
      return res.status(403).json({
        success: false,
        message: 'الحساب معطل أو غير موجود، يرجى مراجعة السوبر أدمن'
      });
    }

    req.user = currentUser;

    // فحص وضع الصيانة (Maintenance Mode)
    // إذا كان مفعلاً، يُسمح فقط للسوبر أدمن بالمرور، وتُمنع بقية الرتب
    const maintenanceSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('maintenance_mode');
    const isMaintenance = maintenanceSetting && maintenanceSetting.value === 'true';

    if (isMaintenance && req.user.role !== ROLES.SUPER_ADMIN) {
      return res.status(503).json({
        success: false,
        message: 'النظام في وضع الصيانة والتحديث حالياً، يرجى المحاولة لاحقاً',
        is_maintenance: true
      });
    }

    next();
  });
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
  requireSuperAdmin,
  requireRoles
};
