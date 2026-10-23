/**
 * Hint: متحكم لوحة إعدادات السوبر أدمن، كشف كلمات المرور، تصفير النظام، وإدارة المستخدمين
 */
const bcrypt = require('bcryptjs');
const path = require('path');
const fs = require('fs');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');
const { encrypt, decrypt } = require('../../core/cryptoHelper');
const { ROLES } = require('../../shared/constants');

// 1. إعدادات النظام العامة
function getSettings(req, res) {
  const rows = db.prepare('SELECT key, value, description FROM system_settings').all();
  const settings = {};
  for (const r of rows) {
    settings[r.key] = r.value;
  }
  return successResponse(res, settings);
}

function updateSettings(req, res) {
  const settingsToUpdate = req.body;
  const user = req.user;

  const updateStmt = db.prepare('UPDATE system_settings SET value = ? WHERE key = ?');
  const insertStmt = db.prepare('INSERT OR IGNORE INTO system_settings (key, value) VALUES (?, ?)');

  const runUpdates = db.transaction((entries) => {
    for (const [key, val] of Object.entries(entries)) {
      const res = updateStmt.run(String(val), key);
      if (res.changes === 0) {
        insertStmt.run(key, String(val));
      }
    }
  });

  runUpdates(settingsToUpdate);

  logAction(user.id, user.full_name, 'تعديل إعدادات النظام', settingsToUpdate);

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
  const updateRes = db.prepare('UPDATE system_settings SET value = ? WHERE key = ?').run(logoUrl, 'logo_url');
  if (updateRes.changes === 0) {
    db.prepare('INSERT INTO system_settings (key, value) VALUES (?, ?)').run('logo_url', logoUrl);
  }

  logAction(user.id, user.full_name, 'تحديث شعار النظام', `رفع شعار جديد: ${logoUrl}`);

  return successResponse(res, { logoUrl }, 'تم تحديث شعار النظام بنجاح');
}

// 2. إدارة المستخدمين والصلاحيات
function listUsers(req, res) {
  const users = db.prepare(`
    SELECT id, username, full_name, role, can_manage_exclusions, can_recommit, avatar_url, is_active, created_at
    FROM users
    ORDER BY id ASC
  `).all();

  return successResponse(res, users);
}

function createUser(req, res) {
  const { username, password, fullName, role, canManageExclusions, canRecommit } = req.body;
  const currentUser = req.user;

  if (!username || !password || !fullName || !role) {
    return errorResponse(res, 'اسم المستخدم، كلمة المرور، الاسم الكامل، والرتبة حقول إلزامية', 400);
  }

  const cleanRole = role === ROLES.SUPER_ADMIN ? ROLES.SUPER_ADMIN : ROLES.DATA_ENTRY;

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username.trim());
  if (existing) {
    return errorResponse(res, 'اسم المستخدم مسجل مسبقاً، يرجى اختيار اسم آخر', 400);
  }

  const hash = bcrypt.hashSync(password, 10);
  const encrypted = encrypt(password);

  const stmt = db.prepare(`
    INSERT INTO users (username, password_hash, encrypted_password, full_name, role, can_manage_exclusions, can_recommit, is_active)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1)
  `);

  const result = stmt.run(
    username.trim(),
    hash,
    encrypted,
    fullName.trim(),
    cleanRole,
    canManageExclusions ? 1 : 0,
    canRecommit ? 1 : 0
  );

  logAction(currentUser.id, currentUser.full_name, 'إنشاء مستخدم جديد', `إنشاء المستخدم [${username}] بالدور [${cleanRole}]`);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إنشاء المستخدم بنجاح', 201);
}

function updateUser(req, res) {
  const { id } = req.params;
  const { fullName, role, isActive, newPassword, canManageExclusions, canRecommit } = req.body;
  const currentUser = req.user;

  const targetUser = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  if (targetUser.role === ROLES.SUPER_ADMIN && currentUser.id === targetUser.id && isActive === 0) {
    return errorResponse(res, 'لا يمكنك تعطيل حسابك الشخصي (السوبر أدمن)', 400);
  }

  const cleanRole = role ? (role === ROLES.SUPER_ADMIN ? ROLES.SUPER_ADMIN : ROLES.DATA_ENTRY) : targetUser.role;

  let query = `
    UPDATE users SET 
      full_name = ?, 
      role = ?, 
      is_active = ?,
      can_manage_exclusions = ?,
      can_recommit = ?
  `;
  const params = [
    fullName ? fullName.trim() : targetUser.full_name,
    cleanRole,
    isActive !== undefined ? (isActive ? 1 : 0) : targetUser.is_active,
    canManageExclusions !== undefined ? (canManageExclusions ? 1 : 0) : targetUser.can_manage_exclusions,
    canRecommit !== undefined ? (canRecommit ? 1 : 0) : targetUser.can_recommit
  ];

  if (newPassword && newPassword.trim().length >= 6) {
    query += ', password_hash = ?, encrypted_password = ?';
    params.push(bcrypt.hashSync(newPassword.trim(), 10));
    params.push(encrypt(newPassword.trim()));
  }

  query += ' WHERE id = ?';
  params.push(id);

  db.prepare(query).run(...params);

  logAction(currentUser.id, currentUser.full_name, 'تعديل مستخدم', `تعديل بيانات المستخدم [${targetUser.username}]`);

  return successResponse(res, null, 'تم تحديث بيانات المستخدم بنجاح');
}

/**
 * كشف كلمة المرور لمستخدم محدد (حصري للسوبر أدمن مع تسجيل أمني صارم - النقطة 15)
 */
function revealPassword(req, res) {
  const { id } = req.params;
  const currentUser = req.user;

  const targetUser = db.prepare('SELECT id, username, full_name, encrypted_password FROM users WHERE id = ?').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  let plainPassword = '';
  if (targetUser.encrypted_password) {
    plainPassword = decrypt(targetUser.encrypted_password);
  }

  if (!plainPassword) {
    return errorResponse(res, 'لا توجد كلمة مرور مشفرة قابلة للعرض لهذا المستخدم (ربما تم إنشاؤه بنسخة قديمة)، يرجى إعادة تعيين كلمة المرور له.', 404);
  }

  // تسجيل عملية الكشف في سجل الحركات الأمني بالوقت والـ IP
  logAction(
    currentUser.id,
    currentUser.full_name,
    'كشف كلمة مرور',
    `قام السوبر أدمن بكشف كلمة مرور المستخدم [${targetUser.username}] (${targetUser.full_name})`
  );

  return successResponse(res, {
    userId: targetUser.id,
    username: targetUser.username,
    fullName: targetUser.full_name,
    password: plainPassword
  }, 'تم فك تشفير كلمة المرور بنجاح');
}

function deleteUser(req, res) {
  const { id } = req.params;
  const currentUser = req.user;

  if (parseInt(id, 10) === currentUser.id) {
    return errorResponse(res, 'لا يمكنك حذف حسابك الشخصي', 400);
  }

  const targetUser = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  db.prepare('DELETE FROM users WHERE id = ?').run(id);

  logAction(currentUser.id, currentUser.full_name, 'حذف مستخدم', `حذف المستخدم [${targetUser.username}]`);

  return successResponse(res, null, 'تم حذف المستخدم بنجاح');
}

/**
 * 3. زر تصفير النظام وإعادة الضبط (حصري للسوبر أدمن مع التحقق من كلمة المرور)
 */
function resetDatabase(req, res) {
  const { password } = req.body;
  const user = req.user;

  if (!password) {
    return errorResponse(res, 'يرجى إدخال كلمة مرور السوبر أدمن للتأكيد قبل التصفير', 400);
  }

  // التحقق من صحة كلمة المرور الخاصة بالسوبر أدمن الحالي
  const currentAdmin = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(user.id);
  const isValid = bcrypt.compareSync(password, currentAdmin.password_hash);

  if (!isValid) {
    return errorResponse(res, 'كلمة المرور غير صحيحة، تم إلغاء عملية التصفير لأسباب أمنية', 403);
  }

  // تنفيذ التصفير الشامل للجداول الحركية
  const resetTx = db.transaction(() => {
    db.exec('DELETE FROM attendance_records;');
    db.exec('DELETE FROM attendance_days;');
    db.exec('DELETE FROM leaves;');
    db.exec('DELETE FROM employee_schedules;');
    db.exec('DELETE FROM employee_transfers;');
    db.exec('DELETE FROM chat_messages;');
    db.exec('DELETE FROM chat_members;');
    db.exec('DELETE FROM chat_channels;');
  });

  resetTx();

  logAction(
    user.id,
    user.full_name,
    'تصفير النظام وإعادة الضبط',
    'قام السوبر أدمن بتصفير كافة سجلات الحضور والإجازات والجداول والمحادثات والتنقلات بنجاح'
  );

  return successResponse(res, null, 'تم تصفير النظام بنجاح، كافة سجلات الحضور والإجازات والجداول تم مسحها وإعادة النظام لنقطة البداية');
}

// 4. الترحيل السنوي
function switchActiveYear(req, res) {
  const { year } = req.body;
  const user = req.user;

  if (!year || isNaN(year)) {
    return errorResponse(res, 'يرجى تحديد سنة صحيحة (مثال: 2027)', 400);
  }

  db.prepare('UPDATE system_settings SET value = ? WHERE key = ?').run(String(year), 'active_year');

  logAction(user.id, user.full_name, 'ترحيل السنة المالية/الإدارية', `تم تفعيل السنة [${year}] كسنة نشطة للنظام`);

  return successResponse(res, { activeYear: year }, `تم تفعيل السنة ${year} بنجاح مع بقاء كافة بيانات السنوات السابقة محفوظة`);
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
