/**
 * Hint: متحكم المصادقة وتسجيل الدخول والملف الشخصي وتغيير الصورة وكلمة المرور
 */
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../../core/database');
const { JWT_SECRET } = require('../../core/config');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { encrypt } = require('../../core/cryptoHelper');
const { isBlocked, recordFailure, clearFailures } = require('../../core/rateLimiter');
const { asTrimmedString, passwordPolicyError, badRequest } = require('../../shared/validators');

const SESSION_TTL = '7d';

/**
 * Hint: الشكل الموحد لبيانات المستخدم في كل الردود (الدخول و /auth/me والملف الشخصي)
 */
function serializeUser(u) {
  return {
    id: u.id,
    username: u.username,
    fullName: u.full_name,
    role: u.role,
    canManageExclusions: u.can_manage_exclusions === 1,
    canRecommit: u.can_recommit === 1,
    avatarUrl: u.avatar_url || null,
    mustChangePassword: u.must_change_password === 1
  };
}

function loadUser(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

function getSetting(key) {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key);
  return row ? row.value : null;
}

function issueToken(user) {
  return jwt.sign(
    { id: user.id, username: user.username, role: user.role, tv: user.token_version || 0 },
    JWT_SECRET,
    { expiresIn: SESSION_TTL }
  );
}

function login(req, res) {
  const username = typeof req.body.username === 'string' ? asTrimmedString(req.body.username, 100) : null;
  const password = typeof req.body.password === 'string' ? req.body.password : null;
  const clientIp = req.clientIp;

  if (!username || !password) {
    return badRequest(res, 'يرجى إدخال اسم المستخدم وكلمة المرور');
  }

  if (isBlocked('login', req, username)) {
    return errorResponse(res, 'تم تجاوز الحد المسموح لمحاولات تسجيل الدخول. يرجى الانتظار 15 دقيقة ثم المحاولة مجدداً', 429);
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ? AND deleted_at IS NULL').get(username);
  // Hint: نفس الرسالة لاسم غير موجود أو كلمة خاطئة أو حساب معطل حتى لا يُكشف وجود الحسابات
  const passwordOk = user ? bcrypt.compareSync(password, user.password_hash) : false;

  if (!user || !passwordOk) {
    recordFailure('login', req, username);
    logAction(user ? user.id : null, user ? user.full_name : username, 'محاولة دخول فاشلة', user ? 'كلمة المرور غير صحيحة' : 'اسم المستخدم غير موجود', clientIp);
    return errorResponse(res, 'بيانات الدخول غير صحيحة', 401);
  }

  if (!user.is_active) {
    logAction(user.id, user.full_name, 'محاولة دخول مرفوضة', 'الحساب معطل', clientIp);
    return errorResponse(res, 'هذا الحساب معطل، يرجى مراجعة المشرف', 403);
  }

  clearFailures('login', req, username);

  const isMaintenance = getSetting('maintenance_mode') === 'true';

  // إذا كان النظام في وضع الصيانة، يُمنع غير السوبر أدمن من تسجيل الدخول
  if (isMaintenance && user.role !== 'SUPER_ADMIN') {
    logAction(user.id, user.full_name, 'محاولة دخول مرفوضة (وضع الصيانة)', 'النظام في وضع الصيانة حالياً', clientIp);
    return res.status(503).json({
      success: false,
      code: 'MAINTENANCE',
      message: 'النظام في وضع الصيانة والتحديث حالياً، يرجى المحاولة لاحقاً',
      isMaintenance: true
    });
  }

  const token = issueToken(user);

  logAction(user.id, user.full_name, 'تسجيل دخول ناجح', `تسجيل الدخول من ${clientIp}`, clientIp);

  return successResponse(res, {
    token,
    user: serializeUser(user),
    systemStatus: {
      announcementBanner: getSetting('announcement_banner_active') === 'true' ? (getSetting('announcement_banner_text') || '') : '',
      isMaintenance,
      logoUrl: getSetting('logo_url') || '',
      institutionName: getSetting('institution_name') || '',
      appTitle: getSetting('app_title') || '',
      activeYear: getSetting('active_year') || '2026'
    }
  }, 'تم تسجيل الدخول بنجاح');
}

function getMe(req, res) {
  return successResponse(res, { user: serializeUser(loadUser(req.user.id)) });
}

/**
 * تحديث الملف الشخصي للمستخدم الحالي (الاسم، كلمة المرور، الصورة)
 * Hint: تغيير كلمة المرور يُبطل كل الجلسات السابقة ويُرجع رمزاً جديداً للجلسة الحالية
 */
function updateProfile(req, res) {
  const { avatarUrl, oldPassword, newPassword } = req.body;
  const current = loadUser(req.user.id);
  if (!current) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  let updatedName = current.full_name;
  if (req.body.fullName !== undefined) {
    updatedName = asTrimmedString(req.body.fullName, 120);
    if (!updatedName) return badRequest(res, 'الاسم الكامل غير صالح');
  }

  let updatedAvatar = current.avatar_url;
  if (avatarUrl !== undefined) {
    if (avatarUrl !== null && (typeof avatarUrl !== 'string' || !/^\/uploads\/avatars\/[\w.-]+$/.test(avatarUrl))) {
      return badRequest(res, 'رابط الصورة الشخصية غير صالح');
    }
    updatedAvatar = avatarUrl;
  }

  // Hint: أثناء إلزام تغيير كلمة المرور المؤقتة لا يُسمح إلا بتغييرها
  if (current.must_change_password && !newPassword) {
    return errorResponse(res, 'يجب تغيير كلمة المرور المؤقتة أولاً', 403);
  }

  let query = 'UPDATE users SET full_name = ?, avatar_url = ?';
  const params = [updatedName, updatedAvatar];
  let passwordChanged = false;

  if (newPassword !== undefined && newPassword !== null && newPassword !== '') {
    if (typeof oldPassword !== 'string' || !oldPassword) {
      return badRequest(res, 'يرجى إدخال كلمة المرور الحالية لتأكيد التغيير');
    }
    if (isBlocked('profile', req, current.id)) {
      return errorResponse(res, 'تم تجاوز الحد المسموح للمحاولات. يرجى الانتظار ثم المحاولة مجدداً', 429);
    }
    if (!bcrypt.compareSync(oldPassword, current.password_hash)) {
      recordFailure('profile', req, current.id);
      return badRequest(res, 'كلمة المرور الحالية غير صحيحة');
    }
    const policyError = passwordPolicyError(newPassword);
    if (policyError) return badRequest(res, policyError);
    if (newPassword === oldPassword) {
      return badRequest(res, 'كلمة المرور الجديدة يجب أن تختلف عن الحالية');
    }
    clearFailures('profile', req, current.id);

    query += ', password_hash = ?, encrypted_password = ?, must_change_password = 0, token_version = token_version + 1';
    params.push(bcrypt.hashSync(newPassword, 10), encrypt(newPassword));
    passwordChanged = true;
  }

  query += ' WHERE id = ?';
  params.push(current.id);
  db.prepare(query).run(...params);

  logAction(current.id, updatedName, 'تعديل الملف الشخصي', passwordChanged ? 'تم تحديث بيانات الملف الشخصي وتغيير كلمة المرور' : 'تم تحديث بيانات الملف الشخصي', req.clientIp);

  const refreshed = loadUser(current.id);
  return successResponse(res, {
    user: serializeUser(refreshed),
    // Hint: رمز جديد يحل محل القديم بعد تغيير كلمة المرور
    token: passwordChanged ? issueToken(refreshed) : undefined
  }, 'تم تحديث الملف الشخصي بنجاح');
}

/**
 * رفع صورة شخصية لحساب المستخدم
 */
function uploadAvatar(req, res) {
  const file = req.file;
  const user = req.user;

  if (!file) {
    return errorResponse(res, 'يرجى اختيار صورة للرفع', 400);
  }

  const avatarUrl = `/uploads/avatars/${file.filename}`;
  db.prepare('UPDATE users SET avatar_url = ? WHERE id = ?').run(avatarUrl, user.id);

  logAction(user.id, user.full_name, 'تحديث الصورة الشخصية', `رفع صورة شخصية جديدة: ${avatarUrl}`, req.clientIp);

  return successResponse(res, { avatarUrl }, 'تم رفع وتحديث الصورة الشخصية بنجاح');
}

/**
 * Hint: التحقق من كلمة مرور المستخدم الحالي فقط (bcrypt) كتأكيد أمني قبل العمليات الحساسة في الواجهة
 */
function verifyPassword(req, res) {
  const user = req.user;
  const password = typeof req.body.password === 'string' ? req.body.password : '';

  if (!password) {
    return badRequest(res, 'يرجى إدخال كلمة المرور للتأكيد الأمني');
  }

  if (isBlocked('verify', req, user.id)) {
    return errorResponse(res, 'تم تجاوز الحد المسموح لمحاولات التحقق الأمني. يرجى الانتظار قليلاً ثم المحاولة مجدداً', 429);
  }

  const current = loadUser(user.id);
  if (!current || !bcrypt.compareSync(password, current.password_hash)) {
    recordFailure('verify', req, user.id);
    return errorResponse(res, 'كلمة المرور غير صحيحة', 403);
  }

  clearFailures('verify', req, user.id);
  return successResponse(res, { verified: true }, 'تم التحقق من كلمة المرور بنجاح');
}

module.exports = {
  login,
  getMe,
  updateProfile,
  uploadAvatar,
  verifyPassword,
  serializeUser,
  issueToken
};
