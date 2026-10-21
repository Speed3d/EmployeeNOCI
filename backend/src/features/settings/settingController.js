/**
 * Hint: متحكم لوحة إعدادات السوبر أدمن، إدارة المستخدمين، وصيانة النظام
 */
const bcrypt = require('bcryptjs');
const db = require('../../core/database');
const { logAction } = require('../../core/auditLogger');
const { successResponse, errorResponse } = require('../../shared/responseHelper');

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
  const settingsToUpdate = req.body; // { key: value, ... }
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

// 2. إدارة المستخدمين (حصرياً للسوبر أدمن)
function listUsers(req, res) {
  const users = db.prepare(`
    SELECT id, username, full_name, role, is_active, created_at
    FROM users
    ORDER BY id ASC
  `).all();

  return successResponse(res, users);
}

function createUser(req, res) {
  const { username, password, fullName, role } = req.body;
  const currentUser = req.user;

  if (!username || !password || !fullName || !role) {
    return errorResponse(res, 'اسم المستخدم، كلمة المرور، الاسم الكامل، والرتبة حقول إلزامية', 400);
  }

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username.trim());
  if (existing) {
    return errorResponse(res, 'اسم المستخدم مستخدم مسبقاً، يرجى اختيار اسم آخر', 400);
  }

  const hash = bcrypt.hashSync(password, 10);
  const stmt = db.prepare(`
    INSERT INTO users (username, password_hash, full_name, role, is_active)
    VALUES (?, ?, ?, ?, 1)
  `);

  const result = stmt.run(username.trim(), hash, fullName.trim(), role);

  logAction(currentUser.id, currentUser.full_name, 'إنشاء مستخدم جديد', `إنشاء المستخدم [${username}] بالدور [${role}]`);

  return successResponse(res, { id: result.lastInsertRowid }, 'تم إنشاء المستخدم بنجاح', 201);
}

function updateUser(req, res) {
  const { id } = req.params;
  const { fullName, role, isActive, newPassword } = req.body;
  const currentUser = req.user;

  const targetUser = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!targetUser) {
    return errorResponse(res, 'المستخدم غير موجود', 404);
  }

  // حماية: لا يمكن تعطيل أو تنزيل رتبة السوبر أدمن إذا كان هو المستخدم الوحيد
  if (targetUser.role === 'SUPER_ADMIN' && currentUser.id === targetUser.id && isActive === 0) {
    return errorResponse(res, 'لا يمكنك تعطيل حسابك الشخصي (السوبر أدمن)', 400);
  }

  let query = 'UPDATE users SET full_name = ?, role = ?, is_active = ?';
  const params = [
    fullName || targetUser.full_name,
    role || targetUser.role,
    isActive !== undefined ? (isActive ? 1 : 0) : targetUser.is_active
  ];

  if (newPassword && newPassword.trim().length >= 6) {
    query += ', password_hash = ?';
    params.push(bcrypt.hashSync(newPassword.trim(), 10));
  }

  query += ' WHERE id = ?';
  params.push(id);

  db.prepare(query).run(...params);

  logAction(currentUser.id, currentUser.full_name, 'تعديل مستخدم', `تعديل بيانات المستخدم [${targetUser.username}]`);

  return successResponse(res, null, 'تم تحديث بيانات المستخدم بنجاح');
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

// 3. الترحيل السنوي
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
  listUsers,
  createUser,
  updateUser,
  deleteUser,
  switchActiveYear
};
