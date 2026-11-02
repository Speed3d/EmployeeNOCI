"""
Hint: مولّد خريطة الملفات والموسوعة المعمارية للمشروع
يُنتج من مصدر بيانات واحد ملفين متطابقين المحتوى:
  - اساس/File_Tree_Employee_NOCI.md   (للقراءة في المحرر و GitHub)
  - اساس/File_Tree_Employee_NOCI.html (صفحة تفاعلية: تبويبات، شجرة قابلة للطي، بحث)
التنسيق (CSS) يُقرأ من ملف HTML الحالي ويُعاد استخدامه كما هو.

التشغيل بعد أي تغيير في بنية المشروع:
    python toolkit/generate_file_tree.py
"""
import html
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD_PATH = os.path.join(ROOT, 'اساس', 'File_Tree_Employee_NOCI.md')
HTML_PATH = os.path.join(ROOT, 'اساس', 'File_Tree_Employee_NOCI.html')
VERSION = '2.0.0'
UPDATED = '2026-11-02'

# ---------------------------------------------------------------------------
# 1. الشجرة: (الاسم، الوصف، [الأبناء]) — الأبناء None للملف
# ---------------------------------------------------------------------------
TREE = ('D:\\Employee NOCI', 'المجلد الجذري للمشروع', [
    ('app/', 'تطبيق Flutter (ويب، ويندوز، أندرويد، آيفون)', [
        ('lib/', 'الشيفرة المصدرية Dart', [
            ('main.dart', 'نقطة البداية: الثيم، والتوجيه بين الدخول وتغيير كلمة المرور والصيانة والتطبيق', None),
            ('core/', 'النواة المركزية', [
                ('api_client.dart', 'عميل الاتصال: مهلة الطلبات، ومعالجة 401/503/كلمة مؤقتة، وروابط التنزيل المؤقتة', None),
                ('auth_provider.dart', 'حالة الجلسة والصلاحيات وهوية المؤسسة، وتحديث الصلاحيات كل 5 دقائق', None),
                ('constants.dart', 'رقم الإصدار، وتسميات الحالات وألوانها', None),
                ('theme.dart', 'الثيم الموحد وألوان الحالات', None),
            ]),
            ('features/', 'الشاشات حسب الميزة', [
                ('attendance/', 'كشف الحضور', [
                    ('attendance_screen.dart', 'الكشف اليومي، والمعاينة متعددة الأيام، والاعتماد، وإعادة الاحتساب، والتصدير', None),
                    ('upload_dialog.dart', 'نافذة رفع ملف البصمة: معاينة فقط أو اعتماد مباشر لكل الأيام', None),
                ]),
                ('audit_logs/', 'سجل الحركات', [
                    ('audit_logs_screen.dart', 'استعراض وفلترة الحركات بتوقيت بغداد', None),
                ]),
                ('auth/', 'المصادقة', [
                    ('login_screen.dart', 'الدخول، وتذكر البيانات، وضبط عنوان الخادم', None),
                    ('change_password_screen.dart', 'تغيير كلمة المرور المؤقتة الإلزامي', None),
                    ('maintenance_screen.dart', 'شاشة وضع الصيانة لغير الأدمن', None),
                    ('profile_dialog.dart', 'الملف الشخصي: الاسم والصورة وكلمة المرور', None),
                ]),
                ('chat/', 'المحادثة', [
                    ('chat_screen.dart', 'المحادثات والمجموعات، وتحميل الرسائل الأقدم، والرقابة للأدمن', None),
                ]),
                ('dashboard/', 'لوحة المؤشرات', [
                    ('dashboard_screen.dart', '5 بطاقات مؤشرات، وعدد الموظفين المشمولين، وتنبيه اليوم غير المعتمد', None),
                ]),
                ('employees/', 'الموظفون', [
                    ('employees_screen.dart', 'السجل الملوّن، والملف الشخصي، والنقل، والمحذوفين والاستعادة، وملخص الاستيراد', None),
                    ('employee_dialog.dart', 'نافذة إضافة وتعديل موظف', None),
                ]),
                ('leaves/', 'الإجازات والعطل', [
                    ('leaves_screen.dart', 'الإجازات (والإذن الساعي بوقت من/إلى)، والأرشيف، والعطل الرسمية', None),
                ]),
                ('reports/', 'التقارير', [
                    ('reports_screen.dart', 'التقرير الشهري للأيام المعتمدة وتصديره', None),
                ]),
                ('schedules/', 'جداول الدوام', [
                    ('schedules_screen.dart', 'تعيينات الأسبوع، والتنقل بين الأسابيع، ونسخ الأسبوع السابق', None),
                    ('widgets/', 'نوافذ الشاشة', [
                        ('assign_schedule_dialog.dart', 'نافذة تعيين جدول بقالب أو أيام مخصصة', None),
                        ('template_dialogs.dart', 'إنشاء وتعديل وحذف القوالب، وأسماء أيام الأسبوع', None),
                    ]),
                ]),
                ('settings/', 'الإعدادات (7 تبويبات)', [
                    ('settings_screen.dart', 'قواعد الدوام، والهوية، والألوان، والأقسام، والمستخدمون، والنسخ، والصيانة', None),
                    ('widgets/', 'نوافذ وعناصر الشاشة', [
                        ('security_dialogs.dart', 'نوافذ التأكيد الأمني بكلمة المرور', None),
                        ('reset_dialog.dart', 'نافذة تصفير النظام بخياريها', None),
                        ('color_setting_item.dart', 'منتقي الألوان ومعاينتها، وتحويل الألوان النصية', None),
                    ]),
                ]),
            ]),
            ('shared/', 'عناصر مشتركة', [
                ('main_layout.dart', 'الإطار العام: القائمة الجانبية، والشريط العلوي، وشريطا التعاميم والصيانة', None),
                ('kpi_card.dart', 'بطاقة المؤشر', None),
                ('status_badge.dart', 'شارة الحالة الملونة', None),
                ('custom_button.dart', 'زر موحد التصميم', None),
            ]),
            ('tools/', 'أدوات', [
                ('date_formatter.dart', 'الأشهر العراقية، وتحويل طوابع UTC إلى توقيت بغداد', None),
                ('responsive.dart', 'نقاط التجاوب (هاتف، لوحي، سطح مكتب)', None),
            ]),
        ]),
        ('test/', 'اختبارات Flutter', [
            ('api_client_test.dart', 'معالجة 401/503/كلمة مؤقتة وأخطاء الشبكة وروابط التنزيل', None),
            ('date_formatter_test.dart', 'الأشهر العراقية وتحويل التوقيت', None),
            ('widget_test.dart', 'اختبار بناء التطبيق', None),
        ]),
        ('web/', 'ملفات الويب (index.html و manifest بالعربية)', []),
        ('android/ windows/ ios/ macos/ linux/', 'منصات البناء', []),
        ('analysis_options.yaml', 'قواعد flutter_lints كاملة دون إخفاء أي تحذير', None),
        ('pubspec.yaml', 'المكتبات ورقم الإصدار', None),
    ]),
    ('backend/', 'الخادم (Node.js + Express 5 + SQLite)', [
        ('src/', 'الشيفرة المصدرية', [
            ('app.js', 'التجميع: helmet و CORS وتحديد عنوان العميل والمسارات واستضافة الويب ومعالج الأخطاء والنسخ التلقائي', None),
            ('core/', 'النواة', [
                ('config.js', 'المنفذ والمضيف والمسارات والمفاتيح (من backend/.keys) ومتغيرات البيئة', None),
                ('database.js', 'الجداول والترحيلات المرقّمة والبذر الافتراضي', None),
                ('authMiddleware.js', 'المصادقة و token_version وتذاكر التنزيل والصلاحيات والصيانة', None),
                ('rateLimiter.js', 'الحماية من التخمين وتحديد العنوان الحقيقي خلف Cloudflare', None),
                ('backupScheduler.js', 'النسخ التلقائي اليومي والدالة المشتركة لإنشاء النسخ', None),
                ('cryptoHelper.js', 'تشفير AES-256-GCM لنسخة كلمة المرور القابلة للكشف', None),
                ('auditLogger.js', 'تسجيل الحركات', None),
            ]),
            ('features/', 'الوحدات', [
                ('attendance/', 'الحضور', [
                    ('attendanceEngine.js', 'محرك الاحتساب: الأولويات، والإذن الساعي، ولقطة القواعد، وإعادة الاحتساب', None),
                    ('attendanceController.js', 'المعاينة المحفوظة، والاعتماد بالمعرّف، والكشف اليومي، وإعادة الاحتساب', None),
                    ('attendanceRoutes.js', 'مسارات /api/attendance', None),
                ]),
                ('auth/', 'المصادقة (authController, authRoutes)', []),
                ('employees/', 'الموظفون (employeeController, employeeRoutes, employeeService للنقل والاستيراد)', []),
                ('leaves/', 'الإجازات والعطل (leaveController, leaveRoutes)', []),
                ('schedules/', 'جداول الدوام (scheduleController, scheduleRoutes)', []),
                ('reports/', 'التقارير والتصدير (reportController, reportRoutes)', []),
                ('downloads/', 'تذاكر التنزيل المؤقتة (downloadRoutes)', []),
                ('settings/', 'الإعدادات والمستخدمون والتصفير (settingController, settingRoutes)', []),
                ('backup/', 'النسخ والاستعادة (backupController, backupRoutes)', []),
                ('chat/', 'المحادثة (chatController, chatRoutes)', []),
                ('audit_logs/', 'سجل الحركات (auditController, auditRoutes)', []),
            ]),
            ('shared/', 'مشترك', [
                ('constants.js', 'الأدوار والحالات وأنواع الإجازات والألوان', None),
                ('responseHelper.js', 'قوالب الرد الموحدة و httpError', None),
                ('validators.js', 'التحقق من المدخلات وسياسة كلمات المرور', None),
            ]),
            ('tools/', 'أدوات', [
                ('excelHelper.js', 'تحليل ملف الموظفين وملف البصمة (تقسيم حسب اليوم)', None),
                ('timeUtils.js', 'توقيت بغداد وحساب الأيام وحدود اليوم بتوقيت UTC', None),
            ]),
        ]),
        ('scripts/', 'سكربتات', [
            ('run-forever.js', 'مشرف يعيد تشغيل الخادم عند التعطل مع سجل دوّار', None),
            ('seed_employees.js', 'بذر الموظفين من ملف اساس', None),
            ('test_engine.js', 'عرض توضيحي للمحرك على الملف النموذجي', None),
        ]),
        ('test/', 'الاختبارات الآلية (node:test، 37 اختباراً على قواعد مؤقتة)', [
            ('helpers.js', 'تهيئة قاعدة ومفاتيح مؤقتة ودوال مساعدة', None),
            ('attendance.test.js', 'المحرك والمعاينة والاعتماد والتقارير التاريخية', None),
            ('security.test.js', 'الجلسات والصلاحيات وكلمات المرور والترويسات والتذاكر', None),
            ('chat_backup.test.js', 'المحادثة والنسخ الاحتياطي والتوقيت', None),
        ]),
        ('vendor/xlsx-0.20.3.tgz', 'مكتبة SheetJS الرسمية المحدّثة', None),
        ('data/', 'القاعدة والنسخ والملفات المؤقتة (غير مرفوع إلى git)', []),
        ('.keys/', 'مفاتيح الجلسات والتشفير (غير مرفوع، احتفظ بنسخة آمنة)', []),
        ('logs/', 'سجل الخادم عند التشغيل عبر المشرف (غير مرفوع)', []),
        ('uploads/', 'الصور الشخصية والشعار', []),
        ('package.json', 'المكتبات والأوامر: start و start:supervised و test و seed', None),
    ]),
    ('toolkit/', 'أدوات التشغيل والنشر', [
        ('run-local.bat', 'تشغيل في نافذة ظاهرة', None),
        ('install-startup-service.bat', 'التشغيل التلقائي مع الويندوز عبر المشرف', None),
        ('run-silent.vbs', 'تشغيل المشرف في الخلفية دون نافذة', None),
        ('stop-server.bat', 'إيقاف المشرف ثم الخادم', None),
        ('setup-cloudflare-tunnel.ps1', 'إعداد نفق Cloudflare للدومين', None),
        ('generate_file_tree.py', 'مولّد هذه الخريطة (Markdown و HTML)', None),
    ]),
    ('خطط/', 'التوثيق: المرجع الشامل، ودليل التثبيت، والتقرير، والخطط، وسجل الإنجاز', []),
    ('اساس/', 'ملف الموظفين الأساسي، ونموذج كشف البصمة، وهذه الخريطة', []),
    ('releases/', 'الإصدارات المبنية (غير مرفوع إلى git)', []),
    ('تشغيل النظام.bat', 'تشغيل الخادم في نافذة ظاهرة وفتح المتصفح', None),
    ('إيقاف النظام.bat', 'إيقاف المشرف ثم أي خادم على المنفذ 5000', None),
    ('README.md · CHANGELOG.md · PROJECT_RULES.md', 'النبذة، وسجل الإصدارات، وقواعد المشروع', None),
])

# ---------------------------------------------------------------------------
# 2. بطاقات الواجهة والخادم: (العنوان، الملف، الوصف، [المسارات]، الجداول، لماذا)
# ---------------------------------------------------------------------------
FRONTEND = [
    ('كشف الحضور اليومي', 'attendance_screen.dart',
     'الشاشة التشغيلية اليومية: الكشف المعتمد لأي تاريخ، والمعاينة قبل الاعتماد مع اختيار اليوم عند تعدد الأيام في الملف، وإعادة الاحتساب، والتصدير.',
     ['POST /api/attendance/preview', 'POST /api/attendance/commit', 'GET /api/attendance/daily', 'POST /api/attendance/recalculate', 'POST /api/downloads/ticket'],
     'attendance_previews, attendance_days, attendance_records',
     'فصل التحليل عن الحفظ، وحفظ المعاينة في الخادم حتى لا يمكن اعتماد بيانات معدّلة من المتصفح.'),
    ('سجل الموظفين', 'employees_screen.dart',
     'السجل الملوّن حسب الحالة، والملف الشخصي (إجازات وتنقلات وحضور)، والنقل بين الأقسام، والاستيراد مع ملخص، وإظهار المحذوفين واستعادتهم.',
     ['GET /api/employees', 'POST /api/employees/:id/transfer', 'DELETE /api/employees/:id', 'POST /api/employees/:id/restore', 'POST /api/employees/import-excel'],
     'employees, employee_transfers, departments',
     'الحذف أرشفة حتى يبقى تاريخ الموظف في التقارير.'),
    ('الإجازات والعطل', 'leaves_screen.dart',
     'تسجيل الإجازات، ومنها الإذن الساعي بوقت من/إلى، وأرشيف المنتهية، والعطل الرسمية.',
     ['GET /api/leaves', 'POST /api/leaves', 'DELETE /api/leaves/:id', 'POST /api/leaves/holidays'],
     'leaves, official_holidays',
     'كل تغيير يعيد احتساب الأيام المعتمدة المتأثرة عبر المحرك نفسه.'),
    ('جداول الدوام', 'schedules_screen.dart + widgets/',
     'تعيين جداول أسبوعية أو ثابتة بقالب أو أيام مخصصة، ونسخ الأسبوع السابق، وإدارة القوالب.',
     ['GET /api/schedules/assignments', 'POST /api/schedules/assign', 'POST /api/schedules/copy-previous-week', 'POST /api/schedules/templates'],
     'employee_schedules, schedule_templates',
     'التعيين يحفظ نسخة من الأيام، فتعديل القالب لاحقاً لا يغيّر التاريخ.'),
    ('الإعدادات والصيانة', 'settings_screen.dart + widgets/',
     '7 تبويبات: قواعد الدوام وعتبة البصمة المنفردة، والهوية والشعار، والألوان، واستثناء الأقسام، والمستخدمون وكشف كلمة المرور، والنسخ الاحتياطي، والصيانة والتصفير والسنة النشطة.',
     ['PUT /api/settings', 'POST /api/settings/users', 'POST /api/settings/users/:id/reveal-password', 'POST /api/backup/create', 'POST /api/settings/reset-db'],
     'system_settings, users',
     'كل العمليات الحساسة تتطلب كلمة مرور يتحقق منها الخادم، وتُسجَّل في سجل الحركات.'),
    ('المحادثة', 'chat_screen.dart',
     'محادثات ثنائية ومجموعات، وأحدث 150 رسالة مع تحميل الأقدم، والرقابة للأدمن.',
     ['GET /api/chat/conversations', 'GET /api/chat/messages', 'POST /api/chat/messages', 'POST /api/chat/groups'],
     'chat_channels, chat_members, chat_messages',
     'منع تكرار الرسائل بين الإرسال والاستطلاع الدوري، وإرجاع النص عند فشل الإرسال.'),
    ('الدخول والجلسة', 'login_screen.dart + change_password_screen.dart',
     'الدخول، وضبط عنوان الخادم، وتغيير كلمة المرور المؤقتة الإلزامي قبل أي شاشة أخرى.',
     ['POST /api/auth/login', 'PUT /api/auth/profile', 'GET /api/auth/me'],
     'users',
     'تغيير كلمة المرور يُبطل الجلسات القديمة ويُرجع رمزاً جديداً للجلسة الحالية.'),
    ('عميل الاتصال', 'api_client.dart',
     'كل الطلبات بمهلة، ومعالجة مركزية: 401 خروج، و503 شاشة صيانة، و403 كلمة مؤقتة. ويطلب روابط التنزيل بتذكرة.',
     ['POST /api/downloads/ticket'], '—',
     'نقطة واحدة لمعالجة الأخطاء بدل تكرارها في كل شاشة.'),
]

BACKEND = [
    ('محرك الحضور', 'attendanceEngine.js',
     'يطابق البصمات مع العطل وجداول الدوام والإجازات ويحسب الحالة والدقائق، ويحفظ لقطة القواعد مع كل يوم معتمد.',
     [], 'attendance_records, attendance_days, leaves, official_holidays, employee_schedules',
     'إعادة الاحتساب بنفس قواعد اليوم تحافظ على ثبات التاريخ.'),
    ('قاعدة البيانات', 'database.js',
     'better-sqlite3 بوضع WAL، وجداول النظام، وترحيلات مرقّمة تُطبَّق تلقائياً عند الإقلاع وبعد الاستعادة.',
     [], 'كل الجداول + schema_migrations',
     'ترقية آمنة لأي نسخة قديمة دون فقدان بيانات.'),
    ('وسيط المصادقة', 'authMiddleware.js',
     'يتحقق من الرمز و token_version وحالة الحساب، ويفرض تغيير الكلمة المؤقتة ووضع الصيانة، ويصادق روابط التنزيل بالتذاكر.',
     [], 'users, system_settings',
     'رموز أخطاء موحدة تمكّن الواجهة من التصرف الصحيح.'),
    ('الحماية من التخمين', 'rateLimiter.js',
     'عدّاد لكل عنوان وآخر لكل حساب، ويعتمد CF-Connecting-IP من loopback فقط.',
     [], '—',
     'منع تجاوز الحد بتزوير الترويسات، خصوصاً خلف Cloudflare.'),
    ('النسخ الاحتياطي', 'backupScheduler.js + backupController.js',
     'نسخ يومي تلقائي (آخر 30)، ونسخ يدوي، واستعادة مع فحص الجداول والسلامة وتطبيق الترحيلات.',
     ['GET /api/backup', 'POST /api/backup/create', 'POST /api/backup/restore'], 'كل القاعدة',
     'التصفير يُلغى إذا فشلت نسخة الأمان.'),
    ('التشفير', 'cryptoHelper.js',
     'AES-256-GCM لنسخة كلمة المرور القابلة للكشف، والمفتاح في backend/.keys خارج مجلد البيانات.',
     [], 'users.encrypted_password',
     'النسخ الاحتياطية لا تحتوي المفتاح.'),
]

# ---------------------------------------------------------------------------
# 3. مصفوفة الارتباط: (الإجراء، الشاشة، المسار، المتحكم، الجداول)
# ---------------------------------------------------------------------------
MATRIX = [
    ('معاينة ملف البصمة', 'attendance_screen / upload_dialog', 'POST /api/attendance/preview', 'attendanceController.previewAttendance', 'attendance_previews'),
    ('اعتماد يوم', 'attendance_screen', 'POST /api/attendance/commit', 'attendanceController.commitAttendance', 'attendance_days, attendance_records'),
    ('إعادة احتساب يوم', 'attendance_screen', 'POST /api/attendance/recalculate', 'attendanceEngine.recalculateCommittedDayIfExists', 'attendance_days, attendance_records'),
    ('تصدير الكشف اليومي', 'attendance_screen', 'POST /api/downloads/ticket ← GET /api/reports/export-daily', 'reportController.exportDailyExcel', 'attendance_records'),
    ('تسجيل إجازة', 'leaves_screen', 'POST /api/leaves', 'leaveController.createLeave', 'leaves (+ إعادة احتساب الأيام المعتمدة)'),
    ('تعيين جدول دوام', 'assign_schedule_dialog', 'POST /api/schedules/assign', 'scheduleController.assignSchedule', 'employee_schedules (+ إعادة احتساب)'),
    ('حذف موظف', 'employees_screen', 'DELETE /api/employees/:id', 'employeeController.deleteEmployee', 'employees.deleted_at'),
    ('نقل موظف', 'employees_screen', 'POST /api/employees/:id/transfer', 'employeeService.transferInTx', 'employees, employee_transfers'),
    ('استيراد الموظفين', 'employees_screen', 'POST /api/employees/import-excel', 'employeeService.importEmployees', 'employees, departments, employee_transfers'),
    ('التقرير الشهري', 'reports_screen', 'GET /api/reports/monthly', 'reportController.getMonthlyTimesheet', 'attendance_records'),
    ('تغيير كلمة المرور', 'change_password_screen / profile_dialog', 'PUT /api/auth/profile', 'authController.updateProfile', 'users (token_version)'),
    ('كشف كلمة مرور مستخدم', 'settings_screen', 'POST /api/settings/users/:id/reveal-password', 'settingController.revealPassword', 'users, audit_logs'),
    ('حفظ الإعدادات', 'settings_screen', 'PUT /api/settings', 'settingController.updateSettings', 'system_settings'),
    ('التصفير', 'settings_screen / reset_dialog', 'POST /api/settings/reset-db', 'settingController.resetDatabase', 'كل الجداول (بعد نسخة أمان)'),
    ('إرسال رسالة', 'chat_screen', 'POST /api/chat/messages', 'chatController.sendMessage', 'chat_messages'),
]

# ---------------------------------------------------------------------------
# 4. قاموس المعرفات: (المعرف، المعنى)
# ---------------------------------------------------------------------------
IDENTIFIERS = [
    ('SUPER_ADMIN / DATA_ENTRY', 'الرتبتان الوحيدتان في النظام'),
    ('can_manage_exclusions / can_recommit', 'صلاحيتان اختياريتان لمدخل البيانات: استثناء الأقسام، وإعادة الاعتماد'),
    ('ON_TIME · LATE · VERY_LATE · EARLY_LEAVE', 'حالات الحضور (التأخير البسيط حتى 30 دقيقة)'),
    ('ABSENT · ON_LEAVE · HOLIDAY · OFF_DAY · MISSED_PUNCH', 'غياب، إجازة يوم كامل، عطلة، راحة أسبوعية، بصمة ناقصة'),
    ('زمنية (ساعية)', 'نوع الإذن الساعي، يحتاج start_time و end_time'),
    ('rules_json', 'لقطة قواعد الدوام المحفوظة مع كل يوم معتمد'),
    ('department_snapshot', 'قسم الموظف لحظة الاعتماد، وتعتمد عليه التقارير'),
    ('deleted_at', 'الحذف الناعم للموظفين والمستخدمين'),
    ('token_version', 'يزداد عند تغيير كلمة المرور أو الرتبة أو التعطيل، فيُبطل كل الرموز السابقة'),
    ('must_change_password', 'كلمة مرور مؤقتة يجب تغييرها قبل أي عملية'),
    ('previewId', 'معرّف المعاينة المحفوظة في الخادم (صلاحية 24 ساعة)'),
    ('single_punch_exit_threshold', 'البصمة الوحيدة بعد هذا الوقت تُعامل كخروج (الافتراضي 12:30)'),
    ('bonus_mode = default | custom', 'المكافأة الافتراضية: قبل البداية بساعة وبعد النهاية'),
    ('factory_default / wipe_all', 'وضعا التصفير'),
    ('SESSION_EXPIRED · ACCOUNT_DISABLED · PASSWORD_CHANGE_REQUIRED · MAINTENANCE', 'رموز أخطاء الجلسة التي تتعامل معها الواجهة'),
    ('export-daily · export-monthly · backup', 'أنواع تذاكر التنزيل المؤقتة (60 ثانية)'),
]

# ---------------------------------------------------------------------------
# 5. السكربتات والأوامر: (الأمر أو الملف، الوظيفة)
# ---------------------------------------------------------------------------
SCRIPTS = [
    ('تشغيل النظام.bat', 'يبذر الموظفين إن كانت القاعدة فارغة (ما لم تُصفَّر عمداً)، ثم يشغّل الخادم في نافذة ظاهرة ويفتح المتصفح'),
    ('إيقاف النظام.bat', 'يوقف المشرف في الخلفية أولاً، ثم أي خادم على المنفذ 5000'),
    ('toolkit/install-startup-service.bat', 'تشغيل الخادم تلقائياً مع الويندوز عبر المشرف (مرة واحدة)'),
    ('toolkit/setup-cloudflare-tunnel.ps1', 'إعداد النفق وربط Employee.nociraq.com'),
    ('cd backend && npm test', '37 اختباراً آلياً على قواعد مؤقتة معزولة'),
    ('cd backend && npm run start:supervised', 'تشغيل الخادم عبر المشرف (إعادة تشغيل تلقائية وسجل)'),
    ('cd app && flutter analyze && flutter test', 'تحليل الكود واختبارات الواجهة'),
    ('cd app && flutter build web --release', 'بناء نسخة الويب التي يستضيفها الخادم'),
    ('cd app && flutter build windows --release', 'بناء تطبيق ويندوز'),
    ('python toolkit/generate_file_tree.py', 'إعادة توليد هذه الخريطة بعد أي تغيير في البنية'),
]

# ---------------------------------------------------------------------------
# 6. الجرد: (العنصر، الحالة، ملاحظة) — الحالة: active أو future
# ---------------------------------------------------------------------------
INVENTORY = [
    ('app/lib/**', 'active', 'كل الشاشات تعمل على الويب وتطبيق ويندوز'),
    ('backend/src/**', 'active', 'كل المسارات والمحرك والحماية'),
    ('backend/test/** و app/test/**', 'active', 'تُشغَّل قبل أي بناء أو نشر'),
    ('backend/scripts/run-forever.js', 'active', 'عند التشغيل التلقائي مع الويندوز'),
    ('backend/scripts/test_engine.js', 'active', 'عرض توضيحي فقط، وليس اختباراً'),
    ('app/android/', 'future', 'جاهز للبناء؛ النشر على Google Play يحتاج مفتاح توقيع رسمياً'),
    ('app/ios/ و app/macos/', 'future', 'يُبنى على جهاز ماك'),
    ('app/linux/', 'future', 'غير مستخدم حالياً'),
]


# ---------------------------------------------------------------------------
# توليد Markdown
# ---------------------------------------------------------------------------
def md_tree(node, prefix='', is_last=True, is_root=True):
    name, desc, children = node
    icon = '📁' if children is not None else '📄'
    if is_root:
        lines = [f'{name}    # {desc}']
    else:
        branch = '└── ' if is_last else '├── '
        lines = [f'{prefix}{branch}{icon} {name}    # {desc}']
    if children:
        child_prefix = prefix if is_root else prefix + ('    ' if is_last else '│   ')
        for i, child in enumerate(children):
            lines += md_tree(child, child_prefix, i == len(children) - 1, False)
    return lines


def md_table(headers, rows):
    out = ['| ' + ' | '.join(headers) + ' |', '|' + '---|' * len(headers)]
    out += ['| ' + ' | '.join(str(c).replace('|', '\\|') for c in r) + ' |' for r in rows]
    return '\n'.join(out)


def md_cards(cards):
    out = []
    for title, file, desc, routes, tables, why in cards:
        out.append(f'#### {title} — `{file}`\n{desc}\n')
        if routes:
            out.append('- **المسارات:** ' + '، '.join(f'`{r}`' for r in routes))
        out.append(f'- **الجداول:** {tables}')
        out.append(f'- **لماذا صممت هكذا؟** {why}\n')
    return '\n'.join(out)


def build_md():
    parts = [
        '# 🌳 الموسوعة الهيكلية والمعمارية لنظام حضور وانصراف موظفي المقر',
        '## (File Tree & Code Map — Employee NOCI)',
        '',
        f'* **الإصدار:** {VERSION} · **آخر تحديث:** {UPDATED}',
        '* **ملاحظة:** هذا الملف والنسخة التفاعلية `File_Tree_Employee_NOCI.html` يُولَّدان تلقائياً من `toolkit/generate_file_tree.py`. لا تعدّلهما يدوياً؛ عدّل المولّد ثم شغّله.',
        '* **المرجع التفصيلي:** [المرجع الشامل](../خطط/المرجع_الشامل_والدليل_التشغيلي_المعتمد.md)',
        '',
        '---',
        '',
        '## 1. الشجرة الهيكلية',
        '',
        '```text',
        *md_tree(TREE),
        '```',
        '',
        '## 2. الواجهة الأمامية (Flutter)',
        '',
        md_cards(FRONTEND),
        '## 3. الخادم والمحرك',
        '',
        md_cards(BACKEND),
        '## 4. مصفوفة الارتباط (ما المربوط بماذا)',
        '',
        md_table(['الإجراء', 'الشاشة', 'المسار', 'المنطق', 'الجداول'], MATRIX),
        '',
        '## 5. قاموس المعرفات',
        '',
        md_table(['المعرف', 'المعنى'], IDENTIFIERS),
        '',
        '## 6. السكربتات والأوامر',
        '',
        md_table(['الأمر أو الملف', 'الوظيفة'], [(f'`{a}`', b) for a, b in SCRIPTS]),
        '',
        '## 7. الجرد: المستخدم حالياً مقابل المجهز للمستقبل',
        '',
        md_table(['العنصر', 'الحالة', 'ملاحظة'], [(f'`{a}`', 'مستخدم' if s == 'active' else 'للمستقبل', n) for a, s, n in INVENTORY]),
        '',
        '## 8. بروتوكول التحديث',
        '',
        '1. عند إضافة ملف أو شاشة أو مسار أو جدول: حدّث البيانات في `toolkit/generate_file_tree.py`، ثم شغّله.',
        '2. حدّث [المرجع الشامل](../خطط/المرجع_الشامل_والدليل_التشغيلي_المعتمد.md) و[سجل الإصدارات](../CHANGELOG.md) عند أي تغيير جوهري.',
        '3. شغّل الاختبارات (`npm test` و`flutter test`) قبل رفع أي تعديل إلى `main`.',
        '',
    ]
    return '\n'.join(parts)


# ---------------------------------------------------------------------------
# توليد HTML (بنفس تنسيق الصفحة الحالية)
# ---------------------------------------------------------------------------
E = html.escape


def html_tree(node, depth=0):
    name, desc, children = node
    if children is None:
        return f'<div class="tree-item file"><span>📄 {E(name)}</span><span class="tag-active">{E(desc)}</span></div>'
    inner = ''.join(f'<div class="tree-node">{html_tree(c, depth + 1)}</div>' for c in children)
    collapsed = ' collapsed' if depth >= 2 else ''
    head = f'<div class="tree-item folder" onclick="toggleNode(this)"><span>📁 {E(name)}</span><span class="badge badge-primary">{E(desc)}</span></div>'
    return head + (f'<div class="tree-children{collapsed}">{inner}</div>' if children else '')


def route_badge(r):
    method = r.split(' ')[0].lower()
    cls = {'delete': 'del'}.get(method, method)
    return f'<span class="badge-route {cls}">{E(r)}</span>'


def html_cards(cards):
    out = ['<div class="cards-grid">']
    for title, file, desc, routes, tables, why in cards:
        routes_html = ''.join(route_badge(r) for r in routes)
        out.append(f'''<div class="feature-card">
  <div class="card-top"><div class="card-title"><span>{E(title)}</span></div><span class="code-badge">{E(file)}</span></div>
  <p class="card-desc">{E(desc)}</p>
  <div class="card-links">
    {f'<div class="card-links-row"><span class="card-links-label">المسارات:</span>{routes_html}</div>' if routes else ''}
    <div class="card-links-row"><span class="card-links-label">الجداول:</span><span>{E(tables)}</span></div>
  </div>
  <div class="card-why"><strong>لماذا صممت هكذا؟</strong> {E(why)}</div>
</div>''')
    out.append('</div>')
    return '\n'.join(out)


def html_table(headers, rows, table_id=''):
    head = ''.join(f'<th>{E(h)}</th>' for h in headers)
    body = ''.join('<tr>' + ''.join(f'<td>{E(str(c))}</td>' for c in r) + '</tr>' for r in rows)
    tid = f' id="{table_id}"' if table_id else ''
    return f'<div class="table-responsive"><table{tid}><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def section(tab_id, title, subtitle, content, active=False, toolbar=''):
    return f'''<section id="{tab_id}" class="tab-pane{' active' if active else ''}">
  <div class="section-card">
    <div class="section-header">
      <div><h2 class="section-title">{title}</h2><p class="section-subtitle">{subtitle}</p></div>
      {toolbar}
    </div>
    {content}
  </div>
</section>'''


TABS = [
    ('treeTab', '🌳 الشجرة الهيكلية', 'الملفات'),
    ('frontendTab', '📱 الواجهة الأمامية', 'app/lib'),
    ('backendTab', '⚙️ الخادم والمحرك', 'backend/src'),
    ('matrixTab', '🔗 مصفوفة الارتباط', 'Traceability'),
    ('identifiersTab', '📖 قاموس المعرفات', 'Dictionary'),
    ('scriptsTab', '🚀 السكربتات والأوامر', 'Scripts'),
    ('auditTab', '⚖️ الجرد', 'Inventory'),
]


def build_html(style_block):
    nav = '\n'.join(
        f'<li class="nav-item"><button{" class=\"active\"" if i == 0 else ""} onclick="switchTab(\'{tid}\', this)"><span>{label}</span><span class="nav-count">{count}</span></button></li>'
        for i, (tid, label, count) in enumerate(TABS))
    inventory_rows = ''.join(
        f'<tr><td>{E(a)}</td><td><span class="{"tag-active" if s == "active" else "tag-future"}">{"مستخدم" if s == "active" else "للمستقبل"}</span></td><td>{E(n)}</td></tr>'
        for a, s, n in INVENTORY)
    sections = [
        section('treeTab', '🌳 الشجرة الهيكلية', 'انقر على أي مجلد لفتحه أو طيّه.',
                f'<div class="tree-view" id="interactiveTree"><div class="tree-node">{html_tree(TREE)}</div></div>', active=True,
                toolbar='<div class="tree-toolbar"><button class="btn" onclick="expandAllTree()">توسيع الكل ➕</button><button class="btn" onclick="collapseAllTree()">طي الكل ➖</button></div>'),
        section('frontendTab', '📱 الواجهة الأمامية (Flutter)', 'كل شاشة، بماذا ترتبط، ولماذا صممت هكذا.', html_cards(FRONTEND)),
        section('backendTab', '⚙️ الخادم والمحرك', 'الوحدات الأساسية في backend/src.', html_cards(BACKEND)),
        section('matrixTab', '🔗 مصفوفة الارتباط', 'من الشاشة إلى المسار إلى المنطق إلى الجداول.',
                html_table(['الإجراء', 'الشاشة', 'المسار', 'المنطق', 'الجداول'], MATRIX, 'matrixTable')),
        section('identifiersTab', '📖 قاموس المعرفات', 'المعرفات والقيم الحاكمة في الكود وقاعدة البيانات.',
                html_table(['المعرف', 'المعنى'], IDENTIFIERS)),
        section('scriptsTab', '🚀 السكربتات والأوامر', 'ملفات التشغيل وأوامر الاختبار والبناء.',
                html_table(['الأمر أو الملف', 'الوظيفة'], SCRIPTS)),
        section('auditTab', '⚖️ الجرد', 'المستخدم حالياً مقابل المجهز للمستقبل.',
                f'<div class="table-responsive"><table><thead><tr><th>العنصر</th><th>الحالة</th><th>ملاحظة</th></tr></thead><tbody>{inventory_rows}</tbody></table></div>'),
    ]
    return f'''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>خريطة الملفات | نظام حضور موظفي المقر</title>
  <!-- ملف مولَّد تلقائياً من toolkit/generate_file_tree.py — لا تعدّله يدوياً -->
  <style>{style_block}</style>
</head>
<body>
  <header>
    <div class="header-container">
      <div class="brand-section">
        <div class="brand-logo">🏛️</div>
        <div class="brand-info">
          <h1>خريطة ملفات نظام حضور موظفي المقر <span class="badge badge-success">الإصدار {VERSION}</span></h1>
          <p>اللجنة الأولمبية الوطنية العراقية (NOCI) • آخر تحديث {UPDATED} • مطابقة للكود</p>
        </div>
      </div>
      <div class="header-actions">
        <div class="search-box">
          <input type="text" id="globalSearch" placeholder="ابحث عن ملف، مسار API، جدول، أو معرف...">
          <span class="search-icon">🔍</span>
        </div>
        <a href="http://localhost:5000" target="_blank" class="btn btn-primary"><span>🚀 فتح النظام (5000)</span></a>
      </div>
    </div>
  </header>

  <div class="app-body">
    <aside class="sidebar-nav">
      <div class="nav-title">الأقسام</div>
      <ul class="nav-list">
{nav}
      </ul>
    </aside>
    <main class="content-area">
{chr(10).join(sections)}
    </main>
  </div>

  <script>
    function switchTab(tabId, btn) {{
      document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
      document.querySelectorAll('.nav-item button').forEach(el => el.classList.remove('active'));
      const target = document.getElementById(tabId);
      if (target) {{ target.classList.add('active'); btn.classList.add('active'); }}
    }}
    function toggleNode(element) {{
      const children = element.parentElement.querySelector('.tree-children');
      if (children) children.classList.toggle('collapsed');
    }}
    function expandAllTree() {{ document.querySelectorAll('.tree-children').forEach(el => el.classList.remove('collapsed')); }}
    function collapseAllTree() {{ document.querySelectorAll('.tree-children').forEach(el => el.classList.add('collapsed')); }}
    document.getElementById('globalSearch').addEventListener('input', function (e) {{
      const q = e.target.value.toLowerCase().trim();
      const items = document.querySelectorAll('.feature-card, tbody tr, .tree-item');
      if (q) expandAllTree();
      items.forEach(el => {{ el.style.display = !q || el.innerText.toLowerCase().includes(q) ? '' : 'none'; }});
    }});
  </script>
</body>
</html>
'''


def main():
    current = open(HTML_PATH, encoding='utf8').read()
    m = re.search(r'<style>(.*?)</style>', current, re.S)
    if not m:
        raise SystemExit('تعذر العثور على التنسيق في ملف HTML الحالي')
    open(MD_PATH, 'w', encoding='utf8', newline='\n').write(build_md())
    open(HTML_PATH, 'w', encoding='utf8', newline='\n').write(build_html(m.group(1)))
    print('✔ تم توليد', os.path.relpath(MD_PATH, ROOT), 'و', os.path.relpath(HTML_PATH, ROOT))


if __name__ == '__main__':
    main()
