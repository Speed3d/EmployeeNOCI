/**
 * Hint: متحكم المصادقة وتسجيل الدخول والملف الشخصي وتغيير الصورة وكلمة المرور (النقطة 14)
 */
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../../core/database');
const { JWT_SECRET } = require('../../core/config');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { encrypt, decrypt } = require('../../core/cryptoHelper');

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

  const bannerSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('announcement_banner_text');
  const bannerActiveSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('announcement_banner_active');
  const maintenanceSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('maintenance_mode');
  const isMaintenance = maintenanceSetting && maintenanceSetting.value === 'true';

  // إذا كان النظام في وضع الصيانة، يُمنع غير السوبر أدمن من تسجيل الدخول
  if (isMaintenance && user.role !== 'SUPER_ADMIN') {
    logAction(user.id, user.full_name, 'محاولة دخول مرفوضة (وضع الصيانة)', 'النظام في وضع الصيانة حالياً', clientIp);
    return res.status(503).json({
      success: false,
      message: 'النظام في وضع الصيانة والتحديث حالياً، يرجى المحاولة لاحقاً',
      isMaintenance: true
    });
  }

  // إنشاء التوكن
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  logAction(user.id, user.full_name, 'تسجيل دخول ناجح', `تسجيل الدخول من ${clientIp}`, clientIp);

  const logoSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('logo_url');
  const institutionSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('institution_name');
  const appTitleSetting = db.prepare('SELECT value FROM system_settings WHERE key = ?').get('app_title');

  return successResponse(res, {
    token,
    user: {
      id: user.id,
      username: user.username,
      fullName: user.full_name,
      role: user.role,
      canManageExclusions: user.can_manage_exclusions === 1,
      canRecommit: user.can_recommit === 1,
      avatarUrl: user.avatar_url
    },
    systemStatus: {
      announcementBanner: bannerActiveSetting && bannerActiveSetting.value === 'true' ? (bannerSetting ? bannerSetting.value : '') : '',
      isMaintenance,
      logoUrl: logoSetting ? logoSetting.value : '',
      institutionName: institutionSetting ? institutionSetting.value : '',
      appTitle: appTitleSetting ? appTitleSetting.value : ''
    }
  }, 'تم تسجيل الدخول بنجاح');
}

function getMe(req, res) {
  const currentUser = db.prepare('SELECT id, username, full_name, role, can_manage_exclusions, can_recommit, avatar_url, is_active FROM users WHERE id = ?').get(req.user.id);
  return successResponse(res, { user: currentUser });
}

/**
 * تحديث الملف الشخصي للمستخدم الحالي (الاسم، كلمة المرور، الصورة)
 */
function updateProfile(req, res) {
  const { fullName, avatarUrl, oldPassword, newPassword } = req.body;
  const user = req.user;

  const currentDbUser = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id);
  if (!currentDbUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  let updatedName = fullName ? fullName.trim() : currentDbUser.full_name;
  let updatedAvatar = avatarUrl !== undefined ? avatarUrl : currentDbUser.avatar_url;

  let query = 'UPDATE users SET full_name = ?, avatar_url = ?';
  const params = [updatedName, updatedAvatar];

  // إذا طلب تغيير كلمة المرور
  if (newPassword) {
    if (!oldPassword) {
      return errorResponse(res, 'يرجى إدخال كلمة المرور الحالية لتأكيد التغيير', 400);
    }
    const isMatch = bcrypt.compareSync(oldPassword, currentDbUser.password_hash);
    if (!isMatch) {
      return errorResponse(res, 'كلمة المرور الحالية غير صحيحة', 400);
    }
    if (newPassword.trim().length < 6) {
      return errorResponse(res, 'يجب ألا تقل كلمة المرور الجديدة عن 6 خانات', 400);
    }

    const newHash = bcrypt.hashSync(newPassword.trim(), 10);
    const newEncrypted = encrypt(newPassword.trim());

    query += ', password_hash = ?, encrypted_password = ?';
    params.push(newHash, newEncrypted);
  }

  query += ' WHERE id = ?';
  params.push(user.id);

  db.prepare(query).run(...params);

  logAction(user.id, updatedName, 'تعديل الملف الشخصي', 'تم تحديث بيانات الملف الشخصي');

  const refreshed = db.prepare('SELECT id, username, full_name, role, can_manage_exclusions, can_recommit, avatar_url FROM users WHERE id = ?').get(user.id);

  return successResponse(res, refreshed, 'تم تحديث الملف الشخصي بنجاح');
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

  logAction(user.id, user.full_name, 'تحديث الصورة الشخصية', `رفع صورة شخصية جديدة: ${avatarUrl}`);

  return successResponse(res, { avatarUrl }, 'تم رفع وتحديث الصورة الشخصية بنجاح');
}

/**
 * التحقق من كلمة مرور المستخدم الحالي (تأكيد أمني للرقابة أو الحركات الحساسة)
 */
function verifyPassword(req, res) {
  let { password } = req.body;
  const user = req.user;

  if (!password) {
    return errorResponse(res, 'يرجى إدخال كلمة المرور للتأكيد الأمني', 400);
  }

  // تنظيف وتحويل الأرقام العربية الهندية (١٢٣) إلى أرقام إنجليزية (123) تحسباً لاختلاف لغات لوحة المفاتيح
  const cleanPwd = String(password).trim().replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d));

  // 1. فحص مع المستخدم الحالي
  const currentUser = db.prepare('SELECT id, password_hash, encrypted_password FROM users WHERE id = ?').get(user.id);
  let isValid = false;

  if (currentUser) {
    // مقارنة التجزئة
    if (currentUser.password_hash && bcrypt.compareSync(cleanPwd, currentUser.password_hash)) {
      isValid = true;
    }
    // مقارنة مع النسخة المشفرة المحفوظة للسوبر أدمن
    if (!isValid && currentUser.encrypted_password) {
      try {
        const dec = decrypt(currentUser.encrypted_password);
        if (dec && (dec === cleanPwd || dec.toLowerCase() === cleanPwd.toLowerCase())) {
          isValid = true;
        }
      } catch (_) {}
    }
  }

  // 2. إذا لم تتطابق، هل تطابق كلمة مرور أي حساب سوبر أدمن في النظام؟
  if (!isValid) {
    const superAdmins = db.prepare("SELECT id, password_hash, encrypted_password FROM users WHERE role = 'SUPER_ADMIN'").all();
    for (const sa of superAdmins) {
      if (sa.password_hash && bcrypt.compareSync(cleanPwd, sa.password_hash)) {
        isValid = true;
        break;
      }
      if (sa.encrypted_password) {
        try {
          const dec = decrypt(sa.encrypted_password);
          if (dec && (dec === cleanPwd || dec.toLowerCase() === cleanPwd.toLowerCase())) {
            isValid = true;
            break;
          }
        } catch (_) {}
      }
    }
  }

  if (!isValid) {
    return errorResponse(res, 'كلمة المرور غير صحيحة، يرجى التأكد والمحاولة ثانية', 403);
  }

  return successResponse(res, { verified: true }, 'تم التحقق من كلمة المرور بنجاح');
}

module.exports = {
  login,
  getMe,
  updateProfile,
  uploadAvatar,
  verifyPassword
};
