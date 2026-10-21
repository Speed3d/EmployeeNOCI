/**
 * Hint: محرك قاعدة البيانات SQLite باستخدام better-sqlite3
 * ينشئ الجداول، الفهارس، ويهيئ حساب السوبر أدمن والإعدادات الافتراضية
 */
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const { DB_PATH } = require('./config');

// التأكد من وجود مجلد البيانات data
const dbDir = path.dirname(DB_PATH);
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

const db = new Database(DB_PATH);
// تفعيل فحص المفاتيح الخارجية وأداء WAL الفائق
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

function initDatabase() {
  // 1. جدول المستخدمين
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      full_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'DATA_ENTRY',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

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

  // 4. جدول سجلات البصمة والحضور اليومي
  db.exec(`
    CREATE TABLE IF NOT EXISTS attendance_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id INTEGER NOT NULL,
      date TEXT NOT NULL,
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

  // 5. جدول الإجازات والأذونات
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

  // 6. جدول العطل والمناسبات الرسمية
  db.exec(`
    CREATE TABLE IF NOT EXISTS official_holidays (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      year INTEGER NOT NULL DEFAULT 2026,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 7. جدول سجل الحركات الأمني (Audit Log)
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

  // 8. جدول إعدادات النظام الشاملة
  db.exec(`
    CREATE TABLE IF NOT EXISTS system_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT UNIQUE NOT NULL,
      value TEXT NOT NULL,
      description TEXT
    );
  `);

  // 9. جدول المحادثة الفورية الداخلية
  db.exec(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sender_id INTEGER NOT NULL,
      sender_name TEXT NOT NULL,
      receiver_id INTEGER,
      message TEXT NOT NULL,
      is_read INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_chat_created ON chat_messages(created_at);
  `);

  // بذر الإعدادات الافتراضية الأولية إن لم تكن موجودة
  seedDefaultSettings();

  // بذر المستخدم الافتراضي (سوبر أدمن)
  seedDefaultAdmin();
}

// Hint: بذر الإعدادات الافتراضية
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

// Hint: بذر حساب السوبر أدمن الافتراضي
function seedDefaultAdmin() {
  const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
  if (userCount === 0) {
    const salt = bcrypt.genSaltSync(10);
    const hash = bcrypt.hashSync('Admin@123456', salt);
    db.prepare(`
      INSERT INTO users (username, password_hash, full_name, role, is_active)
      VALUES (?, ?, ?, 'SUPER_ADMIN', 1)
    `).run('admin', hash, 'مدير النظام (سوبر أدمن)');
    console.log('✔ تم إنشاء حساب السوبر أدمن الافتراضي: (اسم المستخدم: admin | كلمة المرور: Admin@123456)');
  }
}

// تهيئة الجداول فور استدعاء الملف
initDatabase();

module.exports = db;
