/**
 * Hint: محرك قاعدة البيانات SQLite باستخدام better-sqlite3
 * ينشئ الجداول، الفهارس، الترحيلات التلقائية، ويهيئ حساب السوبر أدمن والقوالب الافتراضية
 */
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const { DB_PATH } = require('./config');
const { encrypt } = require('./cryptoHelper');
const { ROLES } = require('../shared/constants');

// التأكد من وجود مجلد البيانات data
const dbDir = path.dirname(DB_PATH);
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

const db = new Database(DB_PATH);
// تفعيل فحص المفاتيح الخارجية وأداء WAL الفائق
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Hint: دالة مساعدة للتحقق من وجود عمود في جدول معين
function columnExists(tableName, columnName) {
  const columns = db.prepare(`PRAGMA table_info(${tableName})`).all();
  return columns.some(c => c.name === columnName);
}

function initDatabase() {
  // 1. جدول المستخدمين
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      encrypted_password TEXT,
      full_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'DATA_ENTRY',
      can_manage_exclusions INTEGER NOT NULL DEFAULT 0,
      can_recommit INTEGER NOT NULL DEFAULT 0,
      avatar_url TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // ترحيل أعمدة المستخدمين للنسخ القديمة
  if (!columnExists('users', 'encrypted_password')) {
    db.exec('ALTER TABLE users ADD COLUMN encrypted_password TEXT;');
  }
  if (!columnExists('users', 'can_manage_exclusions')) {
    db.exec('ALTER TABLE users ADD COLUMN can_manage_exclusions INTEGER NOT NULL DEFAULT 0;');
  }
  if (!columnExists('users', 'can_recommit')) {
    db.exec('ALTER TABLE users ADD COLUMN can_recommit INTEGER NOT NULL DEFAULT 0;');
  }
  if (!columnExists('users', 'avatar_url')) {
    db.exec('ALTER TABLE users ADD COLUMN avatar_url TEXT;');
  }

  // ترحيل الرتب القديمة إلى النظام الثنائي (SUPER_ADMIN و DATA_ENTRY فقط)
  db.prepare(`
    UPDATE users 
    SET role = 'DATA_ENTRY' 
    WHERE role NOT IN ('SUPER_ADMIN', 'DATA_ENTRY')
  `).run();

  // 2. جدول الأقسام وحالة الاستثناء الافتراضية
  db.exec(`
    CREATE TABLE IF NOT EXISTS departments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      is_excluded INTEGER NOT NULL DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 3. جدول الموظفين
  db.exec(`
    CREATE TABLE IF NOT EXISTS employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      emp_code TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      department TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'نشط',
      is_exempt INTEGER NOT NULL DEFAULT 0,
      exempt_reason TEXT,
      phone TEXT,
      address TEXT,
      hire_date TEXT,
      avatar_url TEXT,
      notes TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_emp_code ON employees(emp_code);
    CREATE INDEX IF NOT EXISTS idx_emp_dept ON employees(department);
  `);

  // 4. جدول قوالب الدوام (Schedule Templates)
  db.exec(`
    CREATE TABLE IF NOT EXISTS schedule_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      work_days_json TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 5. جدول جداول دوام الموظفين (Employee Schedules: Fixed or Weekly)
  db.exec(`
    CREATE TABLE IF NOT EXISTS employee_schedules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      schedule_type TEXT NOT NULL DEFAULT 'FIXED',
      template_id INTEGER,
      week_start_date TEXT,
      work_days_json TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY (template_id) REFERENCES schedule_templates(id) ON DELETE SET NULL
    );
    CREATE INDEX IF NOT EXISTS idx_sched_emp ON employee_schedules(employee_id);
    CREATE INDEX IF NOT EXISTS idx_sched_week ON employee_schedules(week_start_date);
  `);

  // 6. جدول الأيام المعتمدة (Attendance Days - Commit Ledger)
  db.exec(`
    CREATE TABLE IF NOT EXISTS attendance_days (
      date TEXT PRIMARY KEY,
      status TEXT NOT NULL DEFAULT 'COMMITTED',
      committed_by INTEGER,
      committed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      raw_punches_json TEXT,
      stats_json TEXT,
      FOREIGN KEY (committed_by) REFERENCES users(id) ON DELETE SET NULL
    );
  `);

  // 7. جدول سجلات البصمة والحضور اليومي
  db.exec(`
    CREATE TABLE IF NOT EXISTS attendance_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      department_snapshot TEXT,
      first_punch TEXT,
      last_punch TEXT,
      punch_count INTEGER DEFAULT 0,
      punch_details TEXT,
      status TEXT NOT NULL,
      late_minutes INTEGER DEFAULT 0,
      early_leave_minutes INTEGER DEFAULT 0,
      early_bonus_minutes INTEGER DEFAULT 0,
      overtime_minutes INTEGER DEFAULT 0,
      notes TEXT,
      year INTEGER NOT NULL DEFAULT 2026,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      UNIQUE(employee_id, date)
    );
    CREATE INDEX IF NOT EXISTS idx_att_date ON attendance_records(date);
    CREATE INDEX IF NOT EXISTS idx_att_emp_date ON attendance_records(employee_id, date);
    CREATE INDEX IF NOT EXISTS idx_att_year ON attendance_records(year);
  `);

  if (!columnExists('attendance_records', 'department_snapshot')) {
    db.exec('ALTER TABLE attendance_records ADD COLUMN department_snapshot TEXT;');
  }

  // 8. جدول الإجازات والأذونات
  db.exec(`
    CREATE TABLE IF NOT EXISTS leaves (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      leave_type TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      hours REAL DEFAULT 0,
      reason TEXT,
      approved_by TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_leaves_dates ON leaves(start_date, end_date);
  `);

  // 9. جدول العطل والمناسبات الرسمية
  db.exec(`
    CREATE TABLE IF NOT EXISTS official_holidays (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      year INTEGER NOT NULL DEFAULT 2026,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 10. جدول سجل تنقلات الموظفين بين الأقسام (Employee Transfers Ledger)
  db.exec(`
    CREATE TABLE IF NOT EXISTS employee_transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      from_department TEXT NOT NULL,
      to_department TEXT NOT NULL,
      transferred_by INTEGER NOT NULL,
      reason TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE,
      FOREIGN KEY (transferred_by) REFERENCES users(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_transfers_emp ON employee_transfers(employee_id);
  `);

  // 11. جدول سجل الحركات الأمني (Audit Log)
  db.exec(`
    CREATE TABLE IF NOT EXISTS audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      user_name TEXT,
      action TEXT NOT NULL,
      details TEXT,
      ip_address TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs(created_at);
  `);

  // 12. جدول إعدادات النظام الشاملة
  db.exec(`
    CREATE TABLE IF NOT EXISTS system_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT UNIQUE NOT NULL,
      value TEXT NOT NULL,
      description TEXT
    );
  `);

  // 13. جداول المحادثات الفورية (قنوات خاصة وجماعية ورقابة)
  db.exec(`
    CREATE TABLE IF NOT EXISTS chat_channels (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      is_group INTEGER DEFAULT 0,
      created_by INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS chat_members (
      channel_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (channel_id, user_id),
      FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS chat_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      channel_id INTEGER,
      sender_id INTEGER NOT NULL,
      sender_name TEXT NOT NULL,
      receiver_id INTEGER,
      message TEXT NOT NULL,
      is_read INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (channel_id) REFERENCES chat_channels(id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
    );
  `);

  if (!columnExists('chat_messages', 'channel_id')) {
    db.exec('ALTER TABLE chat_messages ADD COLUMN channel_id INTEGER;');
  }

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_chat_channel ON chat_messages(channel_id);
    CREATE INDEX IF NOT EXISTS idx_chat_created ON chat_messages(created_at);
  `);

  // بذر الإعدادات الافتراضية والقوالب وحساب السوبر أدمن
  seedDefaultSettings();
  seedScheduleTemplates();
  seedDefaultAdmin();
}

// Hint: بذر الإعدادات الافتراضية للنظام
function seedDefaultSettings() {
  const defaults = [
    { key: 'institution_name', value: 'اللجنة الأولمبية الوطنية العراقية (NOCI)', description: 'اسم المؤسسة الرسمي' },
    { key: 'app_title', value: 'نظام متابعة حضور وانصراف موظفي المقر', description: 'عنوان النظام في الترويسة' },
    { key: 'logo_url', value: '', description: 'رابط شعار المؤسسة' },
    { key: 'work_start_time', value: '10:00', description: 'وقت بدء الدوام الرسمي' },
    { key: 'work_end_time', value: '15:00', description: 'وقت نهاية الدوام الرسمي' },
    { key: 'bonus_enabled', value: 'true', description: 'تفعيل احتساب مكافأة الحضور المبكر والإضافي' },
    { key: 'bonus_mode', value: 'default', description: 'نمط المكافأة: default (09:00 و 15:00) أو custom' },
    { key: 'early_bonus_time', value: '09:00', description: 'وقت احتساب الحضور المبكر كمكافأة' },
    { key: 'overtime_bonus_time', value: '15:00', description: 'وقت بدء احتساب الدوام الإضافي كمكافأة' },
    { key: 'announcement_banner_text', value: '', description: 'نص شريط الإعلانات والتعاميم العلوي' },
    { key: 'announcement_banner_active', value: 'false', description: 'حالة إظهار شريط التنبيهات العلوي' },
    { key: 'maintenance_mode', value: 'false', description: 'وضع الصيانة لإيقاف دخول المستخدمين العاديين' },
    { key: 'active_year', value: '2026', description: 'السنة المالية/الإدارية النشطة حالياً' }
  ];

  const insertStmt = db.prepare(`
    INSERT OR IGNORE INTO system_settings (key, value, description)
    VALUES (?, ?, ?)
  `);

  for (const s of defaults) {
    insertStmt.run(s.key, s.value, s.description);
  }
}

// Hint: بذر قوالب الدوام الافتراضية (النقطة 17)
function seedScheduleTemplates() {
  const count = db.prepare('SELECT COUNT(*) as c FROM schedule_templates').get().c;
  if (count === 0) {
    const defaultTemplates = [
      { name: 'الدوام الافتراضي (أحد - خميس | الجمعة والسبت راحة)', work_days_json: JSON.stringify([0, 1, 2, 3, 4]) },
      { name: 'دوام 6 أيام (الجمعة راحة فقط)', work_days_json: JSON.stringify([0, 1, 2, 3, 4, 6]) },
      { name: 'دوام كامل 7 أيام (بدون راحة أسبوعية)', work_days_json: JSON.stringify([0, 1, 2, 3, 4, 5, 6]) },
      { name: 'شفت 4 أيام دوام (الخميس والجمعة والسبت راحة)', work_days_json: JSON.stringify([0, 1, 2, 3]) },
      { name: 'شفت بديل (راحة الأحد والإثنين والجمعة)', work_days_json: JSON.stringify([2, 3, 4, 6]) }
    ];

    const stmt = db.prepare('INSERT INTO schedule_templates (name, work_days_json) VALUES (?, ?)');
    for (const t of defaultTemplates) {
      stmt.run(t.name, t.work_days_json);
    }
    console.log('✔ تم إنشاء قوالب الدوام الافتراضية بنجاح');
  }
}

// Hint: بذر وتحديث حساب السوبر أدمن الافتراضي
function seedDefaultAdmin() {
  const defaultPlainPassword = 'Admin@123456';
  const adminUser = db.prepare("SELECT * FROM users WHERE username = 'admin'").get();

  if (!adminUser) {
    const salt = bcrypt.genSaltSync(10);
    const hash = bcrypt.hashSync(defaultPlainPassword, salt);
    const encrypted = encrypt(defaultPlainPassword);

    db.prepare(`
      INSERT INTO users (username, password_hash, encrypted_password, full_name, role, can_manage_exclusions, can_recommit, is_active)
      VALUES (?, ?, ?, ?, 'SUPER_ADMIN', 1, 1, 1)
    `).run('admin', hash, encrypted, 'مدير النظام (سوبر أدمن)');
    console.log('✔ تم إنشاء حساب السوبر أدمن الافتراضي: (admin / Admin@123456)');
  } else {
    // تحديث كلمة المرور المشفرة إن لم تكن مسجلة
    if (!adminUser.encrypted_password) {
      const encrypted = encrypt(defaultPlainPassword);
      db.prepare(`
        UPDATE users 
        SET encrypted_password = ?, can_manage_exclusions = 1, can_recommit = 1, role = 'SUPER_ADMIN'
        WHERE id = ?
      `).run(encrypted, adminUser.id);
    }
  }
}

// تهيئة الجداول وترقيتها
initDatabase();

module.exports = db;
