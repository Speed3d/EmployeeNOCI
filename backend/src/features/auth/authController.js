/**
 * Hint: متحكم المصادقة وتسجيل الدخول وإدارة الجلسات
 */
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../../core/database');
const { JWT_SECRET } = require('../../core/config');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

function login(req, res) {
  const { username, password } = req.body;
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  if (!username || !password) {
    return errorResponse(res, 'يرجى إدخال اسم المستخدم وكلمة المرور', 400);
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username.trim());
  if (!user) {
    logAction(null, username, 'محاولة دخول فاشلة', 'اسم المستخدم غير موجود', clientIp);
    return errorResponse(res, 'بيانات الدخول غير صحيحة', 401);
  }

  if (!user.is_active) {
    logAction(user.id, user.full_name, 'محاولة دخول مرفوضة', 'الحساب معطل', clientIp);
    return errorResponse(res, 'هذا الحساب معطل، يرجى مراجعة المشرف', 403);
  }

  const isPasswordValid = bcrypt.compareSync(password, user.password_hash);
  if (!isPasswordValid) {
    logAction(user.id, user.full_name, 'محاولة دخول فاشلة', 'كلمة المرور غير صحيحة', clientIp);
    return errorResponse(res, 'بيانات الدخول غير صحيحة', 401);
  }

  // إنشاء التوكن
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  logAction(user.id, user.full_name, 'تسجيل دخول ناجح', `تسجيل الدخول من ${clientIp}`, clientIp);

  // جلب إعدادات التنبيه والصيانة لإرسالها فوراً مع بيانات الدخول
  const bannerSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('announcement_banner_text');
  const bannerActiveSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('announcement_banner_active');
  const maintenanceSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('maintenance_mode');

  return successResponse(res, {
    token,
    user: {
      id: user.id,
      username: user.username,
      fullName: user.full_name,
      role: user.role
    },
    systemStatus: {
      announcementBanner: bannerActiveSetting && bannerActiveSetting.value === 'true' ? (bannerSetting ? bannerSetting.value : '') : '',
      isMaintenance: maintenanceSetting && maintenanceSetting.value === 'true'
    }
  }, 'تم تسجيل الدخول بنجاح');
}

function getMe(req, res) {
  const user = req.user;
  return successResponse(res, { user });
}

function changePassword(req, res) {
  const { oldPassword, newPassword } = req.body;
  const user = req.user;

  if (!oldPassword || !newPassword) {
    return errorResponse(res, 'يرجى تقديم كلمة المرور الحالية والجديدة', 400);
  }

  if (newPassword.length < 6) {
    return errorResponse(res, 'يجب ألا تقل كلمة المرور الجديدة عن 6 خانات', 400);
  }

  const currentDbUser = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(user.id);
  const isMatch = bcrypt.compareSync(oldPassword, currentDbUser.password_hash);
  if (!isMatch) {
    return errorResponse(res, 'كلمة المرور الحالية غير صحيحة', 400);
  }

  const newHash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(newHash, user.id);

  logAction(user.id, user.full_name, 'تغيير كلمة المرور', 'تم تحديث كلمة المرور الشخصية');
  return successResponse(res, null, 'تم تغيير كلمة المرور بنجاح');
}

module.exports = {
  login,
  getMe,
  changePassword
};
