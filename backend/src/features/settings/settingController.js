/**
 * Hint: متحكم لوحة إعدادات السوبر أدمن، كشف كلمات المرور، تصفير النظام، وإدارة المستخدمين
 */
const bcrypt = require('bcryptjs');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { encrypt, decrypt } = require('../../core/cryptoHelper');
const { ROLES } = require('../../shared/constants');
const { createBackupFile } = require('../../core/backupScheduler');
const { isBlocked, recordFailure, clearFailures } = require('../../core/rateLimiter');
const {
  isHHMM, isHexColor, asBool, asTrimmedString, toPositiveInt, passwordPolicyError, badRequest
} = require('../../shared/validators');
const { timeToMinutes } = require('../../tools/timeUtils');
const seedEmployees = require('../../../scripts/seed_employees');

// Hint: المفاتيح المسموح بتعديلها ومدقق كل منها (أي مفتاح آخر يُرفض)
const SETTING_VALIDATORS = {
  institution_name: v => asTrimmedString(v, 200) !== null && String(v).trim() !== '',
  app_title: v => asTrimmedString(v, 200) !== null && String(v).trim() !== '',
  logo_url: v => v === '' || (typeof v === 'string' && /^(\/uploads\/branding\/[\w.-]+|https:\/\/\S{1,500})$/.test(v)),
  work_start_time: isHHMM,
  work_end_time: isHHMM,
  bonus_enabled: v => v === 'true' || v === 'false' || typeof v === 'boolean',
  bonus_mode: v => v === 'default' || v === 'custom',
  early_bonus_time: isHHMM,
  overtime_bonus_time: isHHMM,
  single_punch_exit_threshold: isHHMM,
  announcement_banner_text: v => asTrimmedString(v, 500) !== null,
  announcement_banner_active: v => v === 'true' || v === 'false' || typeof v === 'boolean',
  maintenance_mode: v => v === 'true' || v === 'false' || typeof v === 'boolean',
  color_active_leave: isHexColor,
  color_seconded: isHexColor,
  color_terminated: isHexColor,
  color_vip_exempt: isHexColor
};

function readSettings() {
  const settings = {};
  for (const r of db.prepare('SELECT key, value FROM system_settings').all()) {
    settings[r.key] = r.value;
  }
  return settings;
}

function countActiveSuperAdmins(excludeId = null) {
  return db.prepare(`
    SELECT COUNT(*) as c FROM users
    WHERE role = 'SUPER_ADMIN' AND is_active = 1 AND deleted_at IS NULL AND id != ?
  `).get(excludeId || 0).c;
}

// 1. إعدادات النظام العامة
function getSettings(req, res) {
  return successResponse(res, readSettings());
}

function updateSettings(req, res) {
  const entries = req.body;
  const user = req.user;

  if (!entries || typeof entries !== 'object' || Array.isArray(entries) || Object.keys(entries).length === 0) {
    return badRequest(res, 'لم يتم إرسال أي إعدادات للحفظ');
  }

  for (const [key, val] of Object.entries(entries)) {
    const validator = SETTING_VALIDATORS[key];
    if (!validator) {
      return badRequest(res, `الإعداد [${key}] غير معروف`);
    }
    if (!validator(val)) {
      return badRequest(res, `قيمة الإعداد [${key}] غير صالحة`);
    }
  }

  // Hint: التحقق من منطقية أوقات الدوام بعد دمج القيم الجديدة مع الحالية
  const merged = { ...readSettings(), ...Object.fromEntries(Object.entries(entries).map(([k, v]) => [k, String(v)])) };
  if (timeToMinutes(merged.work_end_time) <= timeToMinutes(merged.work_start_time)) {
    return badRequest(res, 'وقت نهاية الدوام يجب أن يكون بعد وقت بدايته');
  }
  const threshold = timeToMinutes(merged.single_punch_exit_threshold || '12:30');
  if (threshold <= timeToMinutes(merged.work_start_time) || threshold >= timeToMinutes(merged.work_end_time)) {
    return badRequest(res, 'عتبة البصمة المنفردة يجب أن تقع بين بداية الدوام ونهايته');
  }

  const upsert = db.prepare(`
    INSERT INTO system_settings (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `);
  db.transaction(() => {
    for (const [key, val] of Object.entries(entries)) {
      upsert.run(key, typeof val === 'string' ? val.trim() : String(val));
    }
  })();

  logAction(user.id, user.full_name, 'تعديل إعدادات النظام', entries, req.clientIp);

  return successResponse(res, null, 'تم حفظ الإعدادات بنجاح');
}

/**
 * رفع شعار المؤسسة وحفظه كملف ثابت
 */
function uploadLogo(req, res) {
  const file = req.file;
  const user = req.user;

  if (!file) {
    return errorResponse(res, 'يرجى اختيار ملف الصورة للشعار', 400);
  }

  const logoUrl = `/uploads/branding/${file.filename}`;
  db.prepare(`
    INSERT INTO system_settings (key, value) VALUES ('logo_url', ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `).run(logoUrl);

  logAction(user.id, user.full_name, 'تحديث شعار النظام', `رفع شعار جديد: ${logoUrl}`, req.clientIp);

  return successResponse(res, { logoUrl }, 'تم تحديث شعار النظام بنجاح');
}

// 2. إدارة المستخدمين والصلاحيات
function listUsers(req, res) {
  const users = db.prepare(`
    SELECT id, username, full_name, role, can_manage_exclusions, can_recommit, avatar_url, is_active,
           must_change_password, created_at
    FROM users
    WHERE deleted_at IS NULL
    ORDER BY id ASC
  `).all();

  return successResponse(res, users);
}

function createUser(req, res) {
  const { password, role, canManageExclusions, canRecommit } = req.body;
  const currentUser = req.user;
  const username = asTrimmedString(req.body.username, 60);
  const fullName = asTrimmedString(req.body.fullName, 120);

  if (!username || !password || !fullName || !role) {
    return badRequest(res, 'اسم المستخدم، كلمة المرور، الاسم الكامل، والرتبة حقول إلزامية');
  }
  if (!/^[A-Za-z0-9؀-ۿ._-]{3,60}$/.test(username)) {
    return badRequest(res, 'اسم المستخدم يجب أن يكون من 3 أحرف على الأقل بلا مسافات (أحرف أو أرقام أو . _ -)');
  }
  const policyError = passwordPolicyError(password);
  if (policyError) return badRequest(res, policyError);

  const cleanRole = role === ROLES.SUPER_ADMIN ? ROLES.SUPER_ADMIN : ROLES.DATA_ENTRY;

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) {
    return badRequest(res, 'اسم المستخدم مسجل مسبقاً، يرجى اختيار اسم آخر');
  }

  // Hint: كلمة المرور التي يحددها الأدمن مؤقتة ويجب على المستخدم تغييرها عند أول دخول
  const result = db.prepare(`
    INSERT INTO users (username, password_hash, encrypted_password, full_name, role, can_manage_exclusions, can_recommit, is_active, must_change_password)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1)
  `).run(
    username,
    bcrypt.hashSync(password, 10),
    encrypt(password),
    fullName,
    cleanRole,
    asBool(canManageExclusions) ? 1 : 0,
    asBool(canRecommit) ? 1 : 0
  );

  logAction(currentUser.id, currentUser.full_name, 'إنشاء مستخدم جديد', `إنشاء المستخدم [${username}] بالدور [${cleanRole}]`, req.clientIp);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إنشاء المستخدم بنجاح', 201);
}

function updateUser(req, res) {
  const id = toPositiveInt(req.params.id);
  const { role, isActive, newPassword, canManageExclusions, canRecommit } = req.body;
  const currentUser = req.user;

  const targetUser = id && db.prepare('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  let fullName = targetUser.full_name;
  if (req.body.fullName !== undefined) {
    fullName = asTrimmedString(req.body.fullName, 120);
    if (!fullName) return badRequest(res, 'الاسم الكامل غير صالح');
  }

  const newRole = role !== undefined ? (role === ROLES.SUPER_ADMIN ? ROLES.SUPER_ADMIN : ROLES.DATA_ENTRY) : targetUser.role;
  const newActive = isActive !== undefined ? (asBool(isActive) ? 1 : 0) : targetUser.is_active;
  const isSelf = targetUser.id === currentUser.id;

  // Hint: منع المستخدم من تعطيل نفسه أو تخفيض رتبته، ومنع ترك النظام بلا سوبر أدمن نشط
  if (isSelf && (newActive === 0 || newRole !== targetUser.role)) {
    return badRequest(res, 'لا يمكنك تعطيل حسابك أو تغيير رتبتك بنفسك');
  }
  const losesSuperAdmin = targetUser.role === ROLES.SUPER_ADMIN && targetUser.is_active === 1
    && (newRole !== ROLES.SUPER_ADMIN || newActive === 0);
  if (losesSuperAdmin && countActiveSuperAdmins(targetUser.id) === 0) {
    return badRequest(res, 'لا يمكن تنفيذ التعديل لأنه سيترك النظام بدون أي سوبر أدمن نشط');
  }

  let query = 'UPDATE users SET full_name = ?, role = ?, is_active = ?, can_manage_exclusions = ?, can_recommit = ?';
  const params = [
    fullName,
    newRole,
    newActive,
    canManageExclusions !== undefined ? (asBool(canManageExclusions) ? 1 : 0) : targetUser.can_manage_exclusions,
    canRecommit !== undefined ? (asBool(canRecommit) ? 1 : 0) : targetUser.can_recommit
  ];

  // Hint: إبطال الجلسات عند تغيير الرتبة أو التعطيل أو كلمة المرور
  let revokeSessions = newRole !== targetUser.role || newActive !== targetUser.is_active;

  if (newPassword !== undefined && newPassword !== null && newPassword !== '') {
    const policyError = passwordPolicyError(newPassword);
    if (policyError) return badRequest(res, policyError);
    query += ', password_hash = ?, encrypted_password = ?, must_change_password = ?';
    // إعادة التعيين من الأدمن تجعل كلمة المرور مؤقتة (عدا حسابه الشخصي)
    params.push(bcrypt.hashSync(newPassword, 10), encrypt(newPassword), isSelf ? 0 : 1);
    revokeSessions = true;
  }

  if (revokeSessions) {
    query += ', token_version = token_version + 1';
  }

  query += ' WHERE id = ?';
  params.push(id);
  db.prepare(query).run(...params);

  logAction(currentUser.id, currentUser.full_name, 'تعديل مستخدم', `تعديل بيانات المستخدم [${targetUser.username}]`, req.clientIp);

  return successResponse(res, null, 'تم تحديث بيانات المستخدم بنجاح');
}

/**
 * كشف كلمة المرور لمستخدم محدد (حصري للسوبر أدمن)
 * Hint: يتطلب كلمة مرور الأدمن نفسه ويتحقق منها الخادم، مع حد للمحاولات وتسجيل أمني لكل كشف
 */
function revealPassword(req, res) {
  const id = toPositiveInt(req.params.id);
  const currentUser = req.user;
  const adminPassword = typeof req.body.adminPassword === 'string' ? req.body.adminPassword : '';

  if (!adminPassword) {
    return badRequest(res, 'يرجى إدخال كلمة مرورك للتأكيد');
  }
  if (isBlocked('reveal', req, currentUser.id)) {
    return errorResponse(res, 'تم تجاوز الحد المسموح للمحاولات. يرجى الانتظار ثم المحاولة مجدداً', 429);
  }

  const admin = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(currentUser.id);
  if (!admin || !bcrypt.compareSync(adminPassword, admin.password_hash)) {
    recordFailure('reveal', req, currentUser.id);
    logAction(currentUser.id, currentUser.full_name, 'محاولة كشف كلمة مرور فاشلة', `كلمة مرور الأدمن غير صحيحة (المستخدم المستهدف #${id})`, req.clientIp);
    return errorResponse(res, 'كلمة مرورك غير صحيحة', 403);
  }
  clearFailures('reveal', req, currentUser.id);

  const targetUser = id && db.prepare('SELECT id, username, full_name, encrypted_password FROM users WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  const plainPassword = targetUser.encrypted_password ? decrypt(targetUser.encrypted_password) : '';
  if (!plainPassword) {
    return errorResponse(res, 'لا توجد كلمة مرور قابلة للعرض لهذا المستخدم (ربما أُنشئ بنسخة قديمة أو من تثبيت آخر)، يرجى إعادة تعيين كلمة المرور له.', 404);
  }

  logAction(
    currentUser.id,
    currentUser.full_name,
    'كشف كلمة مرور',
    `قام السوبر أدمن بكشف كلمة مرور المستخدم [${targetUser.username}] (${targetUser.full_name})`,
    req.clientIp
  );

  return successResponse(res, {
    userId: targetUser.id,
    username: targetUser.username,
    fullName: targetUser.full_name,
    password: plainPassword
  }, 'تم فك تشفير كلمة المرور بنجاح');
}

/**
 * Hint: حذف ناعم للمستخدم: يُعطَّل ويُخفى ويُبطَل رمزه، ويبقى أثره في السجلات والتنقلات والمحادثات
 */
function deleteUser(req, res) {
  const id = toPositiveInt(req.params.id);
  const currentUser = req.user;

  if (id === currentUser.id) {
    return badRequest(res, 'لا يمكنك حذف حسابك الشخصي');
  }

  const targetUser = id && db.prepare('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }
  if (targetUser.role === ROLES.SUPER_ADMIN && targetUser.is_active === 1 && countActiveSuperAdmins(targetUser.id) === 0) {
    return badRequest(res, 'لا يمكن حذف آخر سوبر أدمن نشط');
  }

  db.prepare(`
    UPDATE users SET deleted_at = datetime('now'), is_active = 0, token_version = token_version + 1
    WHERE id = ?
  `).run(id);

  logAction(currentUser.id, currentUser.full_name, 'حذف مستخدم', `حذف المستخدم [${targetUser.username}]`, req.clientIp);

  return successResponse(res, null, 'تم حذف المستخدم بنجاح');
}

/**
 * 3. زر تصفير النظام وإعادة الضبط (حصري للسوبر أدمن مع التحقق من كلمة المرور)
 * Hint: يدعم وضعين للتصفير يختارهما السوبر أدمن من النافذة:
 * - factory_default: مسح كافة السجلات والحركات والمستخدمين الإضافيين والقوالب المخصصة وسجل التدقيق، وإعادة الإعدادات وقائمة الموظفين لنسخة الإكسل الأصلية.
 * - wipe_all: مسح شامل بالكامل بما في ذلك الموظفون والأقسام ليصبح النظام فارغاً تماماً (0 موظف).
 */
async function resetDatabase(req, res) {
  const { resetMode = 'factory_default' } = req.body;
  const user = req.user;
  const password = typeof req.body.password === 'string' ? req.body.password : '';

  if (!password) {
    return badRequest(res, 'يرجى إدخال كلمة مرور السوبر أدمن للتأكيد قبل التصفير');
  }
  if (resetMode !== 'factory_default' && resetMode !== 'wipe_all') {
    return badRequest(res, 'وضع التصفير غير معروف');
  }
  if (isBlocked('reset', req, user.id)) {
    return errorResponse(res, 'تم تجاوز الحد المسموح للمحاولات. يرجى الانتظار ثم المحاولة مجدداً', 429);
  }

  const currentAdmin = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(user.id);
  if (!currentAdmin || !bcrypt.compareSync(password, currentAdmin.password_hash)) {
    recordFailure('reset', req, user.id);
    return errorResponse(res, 'كلمة المرور غير صحيحة، تم إلغاء عملية التصفير لأسباب أمنية', 403);
  }
  clearFailures('reset', req, user.id);

  // Hint: نسخة أمان إلزامية قبل التصفير؛ إذا فشلت يُلغى التصفير بالكامل حفاظاً على البيانات
  try {
    await createBackupFile('pre_reset_safety_');
  } catch (backupErr) {
    console.error('تعذر أخذ نسخة الأمان قبل التصفير:', backupErr);
    return errorResponse(res, 'تعذر إنشاء نسخة الأمان الإلزامية قبل التصفير، لذلك تم إلغاء العملية دون أي تغيير', 500);
  }

  const isWipeAll = resetMode === 'wipe_all';

  // تنفيذ التصفير الشامل للجداول الحركية والإعدادات والمستخدمين والقوالب
  db.transaction(() => {
    db.exec('DELETE FROM attendance_records;');
    db.exec('DELETE FROM attendance_days;');
    db.exec('DELETE FROM attendance_previews;');
    db.exec('DELETE FROM leaves;');
    db.exec('DELETE FROM official_holidays;');
    db.exec('DELETE FROM employee_schedules;');
    db.exec('DELETE FROM schedule_templates;');
    db.exec('DELETE FROM employee_transfers;');
    db.exec('DELETE FROM chat_messages;');
    db.exec('DELETE FROM chat_members;');
    db.exec('DELETE FROM chat_channels;');
    db.exec('DELETE FROM audit_logs;');

    // حذف جميع المستخدمين الإضافيين فعلياً والإبقاء على حسابات السوبر أدمن فقط (التصفير هدفه المسح)
    db.prepare("DELETE FROM users WHERE id != ? AND role != 'SUPER_ADMIN'").run(user.id);

    // تصفير إعدادات النظام وإعادتها للقيم الافتراضية للمصنع
    db.exec('DELETE FROM system_settings;');

    // مسح الموظفين والأقسام لإعادة بنائها أو تركها فارغة حسب وضع التصفير
    db.exec('DELETE FROM employees;');
    db.exec('DELETE FROM departments;');

    // تصفير عدادات الترقيم التلقائي للجداول المصفرة
    db.exec(`
      DELETE FROM sqlite_sequence WHERE name IN (
        'employees', 'departments', 'attendance_records', 'leaves',
        'official_holidays', 'employee_schedules', 'schedule_templates',
        'employee_transfers', 'chat_channels', 'chat_messages', 'audit_logs', 'system_settings'
      );
    `);

    db.seedDefaultSettings();
    db.seedScheduleTemplates();

    // تسجيل حالة البذر التلقائي للموظفين
    db.prepare('INSERT OR REPLACE INTO system_settings (key, value, description) VALUES (?, ?, ?)').run(
      'employees_wiped_manually',
      isWipeAll ? 'true' : 'false',
      'منع البذر التلقائي للموظفين عند اختيار التصفير الشامل الفارغ'
    );
  })();

  // إذا اختار السوبر أدمن إعادة الضبط لنقطة البداية الأصلية، نعيد تغذية الموظفين والأقسام من ملف الإكسل الأساسي
  if (!isWipeAll) {
    try {
      seedEmployees(true);
    } catch (seedErr) {
      console.error('خطأ أثناء إعادة تغذية الموظفين الأصلية:', seedErr.message);
    }
  }

  try {
    db.pragma('wal_checkpoint(TRUNCATE)');
  } catch (_) {}

  const actionDesc = isWipeAll
    ? 'قام السوبر أدمن بالتصفير الشامل الكامل (مع حذف كافة الموظفين والأقسام والمستخدمين والإعدادات والسجلات ليصبح النظام فارغاً تماماً)'
    : 'قام السوبر أدمن بإعادة ضبط المصنع لنقطة البداية الأصلية (مسح كافة الحركات والمستخدمين الإضافيين والقوالب المخصصة وإعادة الإعدادات وقائمة الموظفين للنسخة الأصلية)';

  logAction(user.id, user.full_name, 'تصفير النظام وإعادة الضبط', actionDesc, req.clientIp);

  return successResponse(
    res,
    { resetMode, settings: readSettings() },
    isWipeAll
      ? 'تم التصفير الشامل بالكامل وحذف جميع الموظفين والأقسام والسجلات والإعدادات بنجاح!'
      : 'تمت إعادة ضبط النظام لنقطة البداية الأصلية وإعادة قائمة الموظفين والإعدادات للوضع الافتراضي بنجاح!'
  );
}

// 4. الترحيل السنوي
function switchActiveYear(req, res) {
  const year = toPositiveInt(req.body.year || req.body.newYear);
  const user = req.user;

  if (!year || year < 2020 || year > 2100) {
    return badRequest(res, 'يرجى تحديد سنة صحيحة من 4 أرقام (مثال: 2027)');
  }

  db.prepare(`
    INSERT INTO system_settings (key, value) VALUES ('active_year', ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `).run(String(year));

  logAction(user.id, user.full_name, 'ترحيل السنة المالية/الإدارية', `تم تفعيل السنة [${year}] كسنة نشطة للنظام`, req.clientIp);

  return successResponse(res, { activeYear: String(year) }, `تم تفعيل السنة ${year} بنجاح مع بقاء كافة بيانات السنوات السابقة محفوظة`);
}

module.exports = {
  getSettings,
  updateSettings,
  uploadLogo,
  listUsers,
  createUser,
  updateUser,
  revealPassword,
  deleteUser,
  resetDatabase,
  switchActiveYear
};
