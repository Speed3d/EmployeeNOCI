/**
 * Hint: نقطة الانطلاق الرئيسية لخادم النظام (Express Server)
 * يجمع كافة المسارات، يفعل حماية CORS، ويدمج نقاط الـ API مع استضافة الواجهة والملفات المرفوعة
 */
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const { PORT, HOST, UPLOADS_DIR } = require('./core/config');
const db = require('./core/database');

// استيراد المسارات المقسمة حسب الميزات (Features)
const authRoutes = require('./features/auth/authRoutes');
const attendanceRoutes = require('./features/attendance/attendanceRoutes');
const employeeRoutes = require('./features/employees/employeeRoutes');
const leaveRoutes = require('./features/leaves/leaveRoutes');
const settingRoutes = require('./features/settings/settingRoutes');
const auditRoutes = require('./features/audit_logs/auditRoutes');
const chatRoutes = require('./features/chat/chatRoutes');
const reportRoutes = require('./features/reports/reportRoutes');
const scheduleRoutes = require('./features/schedules/scheduleRoutes');
const backupRoutes = require('./features/backup/backupRoutes');

const app = express();

// تفعيل CORS للسماح بالاتصال من أي دومين أو محاكي أندرويد/آيفون أو متصفح ويب
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(express.json({ limit: '25mb' }));
app.use(express.urlencoded({ extended: true, limit: '25mb' }));

// استضافة مجلد المرفقات (الصور الشخصية والشعارات)
app.use('/uploads', express.static(UPLOADS_DIR));

// 1. فحص صحة الخادم وحالته العامة (Health Check)
app.get('/api/system/status', (req, res) => {
  const settingsRows = db.prepare('SELECT key, value FROM system_settings').all();
  const settings = {};
  for (const s of settingsRows) settings[s.key] = s.value;

  res.json({
    success: true,
    name: 'NOCI Attendance Intelligence API',
    version: '2.0.0',
    status: 'ONLINE',
    activeYear: settings['active_year'] || '2026',
    isMaintenance: settings['maintenance_mode'] === 'true',
    institutionName: settings['institution_name'] || 'اللجنة الأولمبية الوطنية العراقية (NOCI)',
    appTitle: settings['app_title'] || 'نظام متابعة حضور وانصراف موظفي المقر',
    logoUrl: settings['logo_url'] || '',
    announcementBanner: settings['announcement_banner_active'] === 'true' ? settings['announcement_banner_text'] : '',
    timestamp: new Date().toISOString()
  });
});

// 2. تسجيل مسارات الـ API المقسمة معمارياً
app.use('/api/auth', authRoutes);
app.use('/api/attendance', attendanceRoutes);
app.use('/api/employees', employeeRoutes);
app.use('/api/leaves', leaveRoutes);
app.use('/api/settings', settingRoutes);
app.use('/api/audit-logs', auditRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/schedules', scheduleRoutes);
app.use('/api/backup', backupRoutes);

// 3. استضافة ملفات الويب المجمعة من Flutter إن وجدت
const webBuildPath = path.join(__dirname, '../../app/build/web');
if (fs.existsSync(webBuildPath)) {
  app.use(express.static(webBuildPath));
  app.use((req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/uploads')) return next();
    res.sendFile(path.join(webBuildPath, 'index.html'));
  });
} else {
  app.get('/', (req, res) => {
    res.send(`
      <div style="font-family: Cairo, Tahoma, sans-serif; direction: rtl; text-align: center; padding: 50px;">
        <h1 style="color: #15315C;">🏛️ خادم نظام متابعة حضور وانصراف موظفي المقر (NOCI) يعمل بنجاح</h1>
        <p style="color: #555;">الـ API جاهز لاستقبال الطلبات على <code>/api</code></p>
      </div>
    `);
  });
}

// 4. معالج الأخطاء العام
app.use((err, req, res, next) => {
  // Hint: أخطاء multer (حجم الملف أو امتداد مرفوض) تُعامل كخطأ في الطلب لا كعطل في الخادم
  if (err && err.name === 'MulterError') {
    const message = err.code === 'LIMIT_FILE_SIZE' ? 'حجم الملف أكبر من الحد المسموح' : 'تعذر رفع الملف';
    return res.status(400).json({ success: false, message });
  }

  // Hint: احترام رمز الحالة المحدد في الخطأ (مثل JSON مكسور = 400)
  const status = Number(err && (err.status || err.statusCode)) || 500;
  if (status >= 500) {
    console.error('خطأ غير معالج في الخادم:', err);
    return res.status(500).json({ success: false, message: 'حدث خطأ داخلي في الخادم' });
  }

  const message = err.type === 'entity.parse.failed'
    ? 'صيغة البيانات المرسلة غير صالحة'
    : (err.expose !== false && err.message ? err.message : 'طلب غير صالح');
  return res.status(status).json({ success: false, message });
});

// تشغيل السيرفر
if (require.main === module) {
  app.listen(PORT, HOST, () => {
    console.log(`=======================================================`);
    console.log(`✔ خادم NOCI Attendance يعمل الآن بنجاح على:`);
    console.log(`  - محلياً: http://localhost:${PORT}`);
    console.log(`  - رابط الصحة: http://localhost:${PORT}/api/system/status`);
    console.log(`=======================================================`);
  });
}

module.exports = app;
