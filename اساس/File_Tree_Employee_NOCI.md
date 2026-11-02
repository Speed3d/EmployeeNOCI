# 🌳 الموسوعة الهيكلية والمعمارية لنظام حضور وانصراف موظفي المقر
## (File Tree & Code Map — Employee NOCI)

* **الإصدار:** 2.0.0 · **آخر تحديث:** 2026-11-02
* **ملاحظة:** هذا الملف والنسخة التفاعلية `File_Tree_Employee_NOCI.html` يُولَّدان تلقائياً من `toolkit/generate_file_tree.py`. لا تعدّلهما يدوياً؛ عدّل المولّد ثم شغّله.
* **المرجع التفصيلي:** [المرجع الشامل](../خطط/المرجع_الشامل_والدليل_التشغيلي_المعتمد.md)

---

## 1. الشجرة الهيكلية

```text
D:\Employee NOCI    # المجلد الجذري للمشروع
├── 📁 app/    # تطبيق Flutter (ويب، ويندوز، أندرويد، آيفون)
│   ├── 📁 lib/    # الشيفرة المصدرية Dart
│   │   ├── 📄 main.dart    # نقطة البداية: الثيم، والتوجيه بين الدخول وتغيير كلمة المرور والصيانة والتطبيق
│   │   ├── 📁 core/    # النواة المركزية
│   │   │   ├── 📄 api_client.dart    # عميل الاتصال: مهلة الطلبات، ومعالجة 401/503/كلمة مؤقتة، وروابط التنزيل المؤقتة
│   │   │   ├── 📄 auth_provider.dart    # حالة الجلسة والصلاحيات وهوية المؤسسة، وتحديث الصلاحيات كل 5 دقائق
│   │   │   ├── 📄 constants.dart    # رقم الإصدار، وتسميات الحالات وألوانها
│   │   │   └── 📄 theme.dart    # الثيم الموحد وألوان الحالات
│   │   ├── 📁 features/    # الشاشات حسب الميزة
│   │   │   ├── 📁 attendance/    # كشف الحضور
│   │   │   │   ├── 📄 attendance_screen.dart    # الكشف اليومي، والمعاينة متعددة الأيام، والاعتماد، وإعادة الاحتساب، والتصدير
│   │   │   │   └── 📄 upload_dialog.dart    # نافذة رفع ملف البصمة: معاينة فقط أو اعتماد مباشر لكل الأيام
│   │   │   ├── 📁 audit_logs/    # سجل الحركات
│   │   │   │   └── 📄 audit_logs_screen.dart    # استعراض وفلترة الحركات بتوقيت بغداد
│   │   │   ├── 📁 auth/    # المصادقة
│   │   │   │   ├── 📄 login_screen.dart    # الدخول، وتذكر البيانات، وضبط عنوان الخادم
│   │   │   │   ├── 📄 change_password_screen.dart    # تغيير كلمة المرور المؤقتة الإلزامي
│   │   │   │   ├── 📄 maintenance_screen.dart    # شاشة وضع الصيانة لغير الأدمن
│   │   │   │   └── 📄 profile_dialog.dart    # الملف الشخصي: الاسم والصورة وكلمة المرور
│   │   │   ├── 📁 chat/    # المحادثة
│   │   │   │   └── 📄 chat_screen.dart    # المحادثات والمجموعات، وتحميل الرسائل الأقدم، والرقابة للأدمن
│   │   │   ├── 📁 dashboard/    # لوحة المؤشرات
│   │   │   │   └── 📄 dashboard_screen.dart    # 5 بطاقات مؤشرات، وعدد الموظفين المشمولين، وتنبيه اليوم غير المعتمد
│   │   │   ├── 📁 employees/    # الموظفون
│   │   │   │   ├── 📄 employees_screen.dart    # السجل الملوّن، والملف الشخصي، والنقل، والمحذوفين والاستعادة، وملخص الاستيراد
│   │   │   │   └── 📄 employee_dialog.dart    # نافذة إضافة وتعديل موظف
│   │   │   ├── 📁 leaves/    # الإجازات والعطل
│   │   │   │   └── 📄 leaves_screen.dart    # الإجازات (والإذن الساعي بوقت من/إلى)، والأرشيف، والعطل الرسمية
│   │   │   ├── 📁 reports/    # التقارير
│   │   │   │   └── 📄 reports_screen.dart    # التقرير الشهري للأيام المعتمدة وتصديره
│   │   │   ├── 📁 schedules/    # جداول الدوام
│   │   │   │   ├── 📄 schedules_screen.dart    # تعيينات الأسبوع، والتنقل بين الأسابيع، ونسخ الأسبوع السابق
│   │   │   │   └── 📁 widgets/    # نوافذ الشاشة
│   │   │   │       ├── 📄 assign_schedule_dialog.dart    # نافذة تعيين جدول بقالب أو أيام مخصصة
│   │   │   │       └── 📄 template_dialogs.dart    # إنشاء وتعديل وحذف القوالب، وأسماء أيام الأسبوع
│   │   │   └── 📁 settings/    # الإعدادات (7 تبويبات)
│   │   │       ├── 📄 settings_screen.dart    # قواعد الدوام، والهوية، والألوان، والأقسام، والمستخدمون، والنسخ، والصيانة
│   │   │       └── 📁 widgets/    # نوافذ وعناصر الشاشة
│   │   │           ├── 📄 security_dialogs.dart    # نوافذ التأكيد الأمني بكلمة المرور
│   │   │           ├── 📄 reset_dialog.dart    # نافذة تصفير النظام بخياريها
│   │   │           └── 📄 color_setting_item.dart    # منتقي الألوان ومعاينتها، وتحويل الألوان النصية
│   │   ├── 📁 shared/    # عناصر مشتركة
│   │   │   ├── 📄 main_layout.dart    # الإطار العام: القائمة الجانبية، والشريط العلوي، وشريطا التعاميم والصيانة
│   │   │   ├── 📄 kpi_card.dart    # بطاقة المؤشر
│   │   │   ├── 📄 status_badge.dart    # شارة الحالة الملونة
│   │   │   └── 📄 custom_button.dart    # زر موحد التصميم
│   │   └── 📁 tools/    # أدوات
│   │       ├── 📄 date_formatter.dart    # الأشهر العراقية، وتحويل طوابع UTC إلى توقيت بغداد
│   │       └── 📄 responsive.dart    # نقاط التجاوب (هاتف، لوحي، سطح مكتب)
│   ├── 📁 test/    # اختبارات Flutter
│   │   ├── 📄 api_client_test.dart    # معالجة 401/503/كلمة مؤقتة وأخطاء الشبكة وروابط التنزيل
│   │   ├── 📄 date_formatter_test.dart    # الأشهر العراقية وتحويل التوقيت
│   │   └── 📄 widget_test.dart    # اختبار بناء التطبيق
│   ├── 📁 web/    # ملفات الويب (index.html و manifest بالعربية)
│   ├── 📁 android/ windows/ ios/ macos/ linux/    # منصات البناء
│   ├── 📄 analysis_options.yaml    # قواعد flutter_lints كاملة دون إخفاء أي تحذير
│   └── 📄 pubspec.yaml    # المكتبات ورقم الإصدار
├── 📁 backend/    # الخادم (Node.js + Express 5 + SQLite)
│   ├── 📁 src/    # الشيفرة المصدرية
│   │   ├── 📄 app.js    # التجميع: helmet و CORS وتحديد عنوان العميل والمسارات واستضافة الويب ومعالج الأخطاء والنسخ التلقائي
│   │   ├── 📁 core/    # النواة
│   │   │   ├── 📄 config.js    # المنفذ والمضيف والمسارات والمفاتيح (من backend/.keys) ومتغيرات البيئة
│   │   │   ├── 📄 database.js    # الجداول والترحيلات المرقّمة والبذر الافتراضي
│   │   │   ├── 📄 authMiddleware.js    # المصادقة و token_version وتذاكر التنزيل والصلاحيات والصيانة
│   │   │   ├── 📄 rateLimiter.js    # الحماية من التخمين وتحديد العنوان الحقيقي خلف Cloudflare
│   │   │   ├── 📄 backupScheduler.js    # النسخ التلقائي اليومي والدالة المشتركة لإنشاء النسخ
│   │   │   ├── 📄 cryptoHelper.js    # تشفير AES-256-GCM لنسخة كلمة المرور القابلة للكشف
│   │   │   └── 📄 auditLogger.js    # تسجيل الحركات
│   │   ├── 📁 features/    # الوحدات
│   │   │   ├── 📁 attendance/    # الحضور
│   │   │   │   ├── 📄 attendanceEngine.js    # محرك الاحتساب: الأولويات، والإذن الساعي، ولقطة القواعد، وإعادة الاحتساب
│   │   │   │   ├── 📄 attendanceController.js    # المعاينة المحفوظة، والاعتماد بالمعرّف، والكشف اليومي، وإعادة الاحتساب
│   │   │   │   └── 📄 attendanceRoutes.js    # مسارات /api/attendance
│   │   │   ├── 📁 auth/    # المصادقة (authController, authRoutes)
│   │   │   ├── 📁 employees/    # الموظفون (employeeController, employeeRoutes, employeeService للنقل والاستيراد)
│   │   │   ├── 📁 leaves/    # الإجازات والعطل (leaveController, leaveRoutes)
│   │   │   ├── 📁 schedules/    # جداول الدوام (scheduleController, scheduleRoutes)
│   │   │   ├── 📁 reports/    # التقارير والتصدير (reportController, reportRoutes)
│   │   │   ├── 📁 downloads/    # تذاكر التنزيل المؤقتة (downloadRoutes)
│   │   │   ├── 📁 settings/    # الإعدادات والمستخدمون والتصفير (settingController, settingRoutes)
│   │   │   ├── 📁 backup/    # النسخ والاستعادة (backupController, backupRoutes)
│   │   │   ├── 📁 chat/    # المحادثة (chatController, chatRoutes)
│   │   │   └── 📁 audit_logs/    # سجل الحركات (auditController, auditRoutes)
│   │   ├── 📁 shared/    # مشترك
│   │   │   ├── 📄 constants.js    # الأدوار والحالات وأنواع الإجازات والألوان
│   │   │   ├── 📄 responseHelper.js    # قوالب الرد الموحدة و httpError
│   │   │   └── 📄 validators.js    # التحقق من المدخلات وسياسة كلمات المرور
│   │   └── 📁 tools/    # أدوات
│   │       ├── 📄 excelHelper.js    # تحليل ملف الموظفين وملف البصمة (تقسيم حسب اليوم)
│   │       └── 📄 timeUtils.js    # توقيت بغداد وحساب الأيام وحدود اليوم بتوقيت UTC
│   ├── 📁 scripts/    # سكربتات
│   │   ├── 📄 run-forever.js    # مشرف يعيد تشغيل الخادم عند التعطل مع سجل دوّار
│   │   ├── 📄 seed_employees.js    # بذر الموظفين من ملف اساس
│   │   └── 📄 test_engine.js    # عرض توضيحي للمحرك على الملف النموذجي
│   ├── 📁 test/    # الاختبارات الآلية (node:test، 37 اختباراً على قواعد مؤقتة)
│   │   ├── 📄 helpers.js    # تهيئة قاعدة ومفاتيح مؤقتة ودوال مساعدة
│   │   ├── 📄 attendance.test.js    # المحرك والمعاينة والاعتماد والتقارير التاريخية
│   │   ├── 📄 security.test.js    # الجلسات والصلاحيات وكلمات المرور والترويسات والتذاكر
│   │   └── 📄 chat_backup.test.js    # المحادثة والنسخ الاحتياطي والتوقيت
│   ├── 📄 vendor/xlsx-0.20.3.tgz    # مكتبة SheetJS الرسمية المحدّثة
│   ├── 📁 data/    # القاعدة والنسخ والملفات المؤقتة (غير مرفوع إلى git)
│   ├── 📁 .keys/    # مفاتيح الجلسات والتشفير (غير مرفوع، احتفظ بنسخة آمنة)
│   ├── 📁 logs/    # سجل الخادم عند التشغيل عبر المشرف (غير مرفوع)
│   ├── 📁 uploads/    # الصور الشخصية والشعار
│   └── 📄 package.json    # المكتبات والأوامر: start و start:supervised و test و seed
├── 📁 toolkit/    # أدوات التشغيل والنشر
│   ├── 📄 run-local.bat    # تشغيل في نافذة ظاهرة
│   ├── 📄 install-startup-service.bat    # التشغيل التلقائي مع الويندوز عبر المشرف
│   ├── 📄 run-silent.vbs    # تشغيل المشرف في الخلفية دون نافذة
│   ├── 📄 stop-server.bat    # إيقاف المشرف ثم الخادم
│   ├── 📄 setup-cloudflare-tunnel.ps1    # إعداد نفق Cloudflare للدومين
│   └── 📄 generate_file_tree.py    # مولّد هذه الخريطة (Markdown و HTML)
├── 📁 خطط/    # التوثيق: المرجع الشامل، ودليل التثبيت، والتقرير، والخطط، وسجل الإنجاز
├── 📁 اساس/    # ملف الموظفين الأساسي، ونموذج كشف البصمة، وهذه الخريطة
├── 📁 releases/    # الإصدارات المبنية (غير مرفوع إلى git)
├── 📄 تشغيل النظام.bat    # تشغيل الخادم في نافذة ظاهرة وفتح المتصفح
├── 📄 إيقاف النظام.bat    # إيقاف المشرف ثم أي خادم على المنفذ 5000
└── 📄 README.md · CHANGELOG.md · PROJECT_RULES.md    # النبذة، وسجل الإصدارات، وقواعد المشروع
```

## 2. الواجهة الأمامية (Flutter)

#### كشف الحضور اليومي — `attendance_screen.dart`
الشاشة التشغيلية اليومية: الكشف المعتمد لأي تاريخ، والمعاينة قبل الاعتماد مع اختيار اليوم عند تعدد الأيام في الملف، وإعادة الاحتساب، والتصدير.

- **المسارات:** `POST /api/attendance/preview`، `POST /api/attendance/commit`، `GET /api/attendance/daily`، `POST /api/attendance/recalculate`، `POST /api/downloads/ticket`
- **الجداول:** attendance_previews, attendance_days, attendance_records
- **لماذا صممت هكذا؟** فصل التحليل عن الحفظ، وحفظ المعاينة في الخادم حتى لا يمكن اعتماد بيانات معدّلة من المتصفح.

#### سجل الموظفين — `employees_screen.dart`
السجل الملوّن حسب الحالة، والملف الشخصي (إجازات وتنقلات وحضور)، والنقل بين الأقسام، والاستيراد مع ملخص، وإظهار المحذوفين واستعادتهم.

- **المسارات:** `GET /api/employees`، `POST /api/employees/:id/transfer`، `DELETE /api/employees/:id`، `POST /api/employees/:id/restore`، `POST /api/employees/import-excel`
- **الجداول:** employees, employee_transfers, departments
- **لماذا صممت هكذا؟** الحذف أرشفة حتى يبقى تاريخ الموظف في التقارير.

#### الإجازات والعطل — `leaves_screen.dart`
تسجيل الإجازات، ومنها الإذن الساعي بوقت من/إلى، وأرشيف المنتهية، والعطل الرسمية.

- **المسارات:** `GET /api/leaves`، `POST /api/leaves`، `DELETE /api/leaves/:id`، `POST /api/leaves/holidays`
- **الجداول:** leaves, official_holidays
- **لماذا صممت هكذا؟** كل تغيير يعيد احتساب الأيام المعتمدة المتأثرة عبر المحرك نفسه.

#### جداول الدوام — `schedules_screen.dart + widgets/`
تعيين جداول أسبوعية أو ثابتة بقالب أو أيام مخصصة، ونسخ الأسبوع السابق، وإدارة القوالب.

- **المسارات:** `GET /api/schedules/assignments`، `POST /api/schedules/assign`، `POST /api/schedules/copy-previous-week`، `POST /api/schedules/templates`
- **الجداول:** employee_schedules, schedule_templates
- **لماذا صممت هكذا؟** التعيين يحفظ نسخة من الأيام، فتعديل القالب لاحقاً لا يغيّر التاريخ.

#### الإعدادات والصيانة — `settings_screen.dart + widgets/`
7 تبويبات: قواعد الدوام وعتبة البصمة المنفردة، والهوية والشعار، والألوان، واستثناء الأقسام، والمستخدمون وكشف كلمة المرور، والنسخ الاحتياطي، والصيانة والتصفير والسنة النشطة.

- **المسارات:** `PUT /api/settings`، `POST /api/settings/users`، `POST /api/settings/users/:id/reveal-password`، `POST /api/backup/create`، `POST /api/settings/reset-db`
- **الجداول:** system_settings, users
- **لماذا صممت هكذا؟** كل العمليات الحساسة تتطلب كلمة مرور يتحقق منها الخادم، وتُسجَّل في سجل الحركات.

#### المحادثة — `chat_screen.dart`
محادثات ثنائية ومجموعات، وأحدث 150 رسالة مع تحميل الأقدم، والرقابة للأدمن.

- **المسارات:** `GET /api/chat/conversations`، `GET /api/chat/messages`، `POST /api/chat/messages`، `POST /api/chat/groups`
- **الجداول:** chat_channels, chat_members, chat_messages
- **لماذا صممت هكذا؟** منع تكرار الرسائل بين الإرسال والاستطلاع الدوري، وإرجاع النص عند فشل الإرسال.

#### الدخول والجلسة — `login_screen.dart + change_password_screen.dart`
الدخول، وضبط عنوان الخادم، وتغيير كلمة المرور المؤقتة الإلزامي قبل أي شاشة أخرى.

- **المسارات:** `POST /api/auth/login`، `PUT /api/auth/profile`، `GET /api/auth/me`
- **الجداول:** users
- **لماذا صممت هكذا؟** تغيير كلمة المرور يُبطل الجلسات القديمة ويُرجع رمزاً جديداً للجلسة الحالية.

#### عميل الاتصال — `api_client.dart`
كل الطلبات بمهلة، ومعالجة مركزية: 401 خروج، و503 شاشة صيانة، و403 كلمة مؤقتة. ويطلب روابط التنزيل بتذكرة.

- **المسارات:** `POST /api/downloads/ticket`
- **الجداول:** —
- **لماذا صممت هكذا؟** نقطة واحدة لمعالجة الأخطاء بدل تكرارها في كل شاشة.

## 3. الخادم والمحرك

#### محرك الحضور — `attendanceEngine.js`
يطابق البصمات مع العطل وجداول الدوام والإجازات ويحسب الحالة والدقائق، ويحفظ لقطة القواعد مع كل يوم معتمد.

- **الجداول:** attendance_records, attendance_days, leaves, official_holidays, employee_schedules
- **لماذا صممت هكذا؟** إعادة الاحتساب بنفس قواعد اليوم تحافظ على ثبات التاريخ.

#### قاعدة البيانات — `database.js`
better-sqlite3 بوضع WAL، وجداول النظام، وترحيلات مرقّمة تُطبَّق تلقائياً عند الإقلاع وبعد الاستعادة.

- **الجداول:** كل الجداول + schema_migrations
- **لماذا صممت هكذا؟** ترقية آمنة لأي نسخة قديمة دون فقدان بيانات.

#### وسيط المصادقة — `authMiddleware.js`
يتحقق من الرمز و token_version وحالة الحساب، ويفرض تغيير الكلمة المؤقتة ووضع الصيانة، ويصادق روابط التنزيل بالتذاكر.

- **الجداول:** users, system_settings
- **لماذا صممت هكذا؟** رموز أخطاء موحدة تمكّن الواجهة من التصرف الصحيح.

#### الحماية من التخمين — `rateLimiter.js`
عدّاد لكل عنوان وآخر لكل حساب، ويعتمد CF-Connecting-IP من loopback فقط.

- **الجداول:** —
- **لماذا صممت هكذا؟** منع تجاوز الحد بتزوير الترويسات، خصوصاً خلف Cloudflare.

#### النسخ الاحتياطي — `backupScheduler.js + backupController.js`
نسخ يومي تلقائي (آخر 30)، ونسخ يدوي، واستعادة مع فحص الجداول والسلامة وتطبيق الترحيلات.

- **المسارات:** `GET /api/backup`، `POST /api/backup/create`، `POST /api/backup/restore`
- **الجداول:** كل القاعدة
- **لماذا صممت هكذا؟** التصفير يُلغى إذا فشلت نسخة الأمان.

#### التشفير — `cryptoHelper.js`
AES-256-GCM لنسخة كلمة المرور القابلة للكشف، والمفتاح في backend/.keys خارج مجلد البيانات.

- **الجداول:** users.encrypted_password
- **لماذا صممت هكذا؟** النسخ الاحتياطية لا تحتوي المفتاح.

## 4. مصفوفة الارتباط (ما المربوط بماذا)

| الإجراء | الشاشة | المسار | المنطق | الجداول |
|---|---|---|---|---|
| معاينة ملف البصمة | attendance_screen / upload_dialog | POST /api/attendance/preview | attendanceController.previewAttendance | attendance_previews |
| اعتماد يوم | attendance_screen | POST /api/attendance/commit | attendanceController.commitAttendance | attendance_days, attendance_records |
| إعادة احتساب يوم | attendance_screen | POST /api/attendance/recalculate | attendanceEngine.recalculateCommittedDayIfExists | attendance_days, attendance_records |
| تصدير الكشف اليومي | attendance_screen | POST /api/downloads/ticket ← GET /api/reports/export-daily | reportController.exportDailyExcel | attendance_records |
| تسجيل إجازة | leaves_screen | POST /api/leaves | leaveController.createLeave | leaves (+ إعادة احتساب الأيام المعتمدة) |
| تعيين جدول دوام | assign_schedule_dialog | POST /api/schedules/assign | scheduleController.assignSchedule | employee_schedules (+ إعادة احتساب) |
| حذف موظف | employees_screen | DELETE /api/employees/:id | employeeController.deleteEmployee | employees.deleted_at |
| نقل موظف | employees_screen | POST /api/employees/:id/transfer | employeeService.transferInTx | employees, employee_transfers |
| استيراد الموظفين | employees_screen | POST /api/employees/import-excel | employeeService.importEmployees | employees, departments, employee_transfers |
| التقرير الشهري | reports_screen | GET /api/reports/monthly | reportController.getMonthlyTimesheet | attendance_records |
| تغيير كلمة المرور | change_password_screen / profile_dialog | PUT /api/auth/profile | authController.updateProfile | users (token_version) |
| كشف كلمة مرور مستخدم | settings_screen | POST /api/settings/users/:id/reveal-password | settingController.revealPassword | users, audit_logs |
| حفظ الإعدادات | settings_screen | PUT /api/settings | settingController.updateSettings | system_settings |
| التصفير | settings_screen / reset_dialog | POST /api/settings/reset-db | settingController.resetDatabase | كل الجداول (بعد نسخة أمان) |
| إرسال رسالة | chat_screen | POST /api/chat/messages | chatController.sendMessage | chat_messages |

## 5. قاموس المعرفات

| المعرف | المعنى |
|---|---|
| SUPER_ADMIN / DATA_ENTRY | الرتبتان الوحيدتان في النظام |
| can_manage_exclusions / can_recommit | صلاحيتان اختياريتان لمدخل البيانات: استثناء الأقسام، وإعادة الاعتماد |
| ON_TIME · LATE · VERY_LATE · EARLY_LEAVE | حالات الحضور (التأخير البسيط حتى 30 دقيقة) |
| ABSENT · ON_LEAVE · HOLIDAY · OFF_DAY · MISSED_PUNCH | غياب، إجازة يوم كامل، عطلة، راحة أسبوعية، بصمة ناقصة |
| زمنية (ساعية) | نوع الإذن الساعي، يحتاج start_time و end_time |
| rules_json | لقطة قواعد الدوام المحفوظة مع كل يوم معتمد |
| department_snapshot | قسم الموظف لحظة الاعتماد، وتعتمد عليه التقارير |
| deleted_at | الحذف الناعم للموظفين والمستخدمين |
| token_version | يزداد عند تغيير كلمة المرور أو الرتبة أو التعطيل، فيُبطل كل الرموز السابقة |
| must_change_password | كلمة مرور مؤقتة يجب تغييرها قبل أي عملية |
| previewId | معرّف المعاينة المحفوظة في الخادم (صلاحية 24 ساعة) |
| single_punch_exit_threshold | البصمة الوحيدة بعد هذا الوقت تُعامل كخروج (الافتراضي 12:30) |
| bonus_mode = default \| custom | المكافأة الافتراضية: قبل البداية بساعة وبعد النهاية |
| factory_default / wipe_all | وضعا التصفير |
| SESSION_EXPIRED · ACCOUNT_DISABLED · PASSWORD_CHANGE_REQUIRED · MAINTENANCE | رموز أخطاء الجلسة التي تتعامل معها الواجهة |
| export-daily · export-monthly · backup | أنواع تذاكر التنزيل المؤقتة (60 ثانية) |

## 6. السكربتات والأوامر

| الأمر أو الملف | الوظيفة |
|---|---|
| `تشغيل النظام.bat` | يبذر الموظفين إن كانت القاعدة فارغة (ما لم تُصفَّر عمداً)، ثم يشغّل الخادم في نافذة ظاهرة ويفتح المتصفح |
| `إيقاف النظام.bat` | يوقف المشرف في الخلفية أولاً، ثم أي خادم على المنفذ 5000 |
| `toolkit/install-startup-service.bat` | تشغيل الخادم تلقائياً مع الويندوز عبر المشرف (مرة واحدة) |
| `toolkit/setup-cloudflare-tunnel.ps1` | إعداد النفق وربط Employee.nociraq.com |
| `cd backend && npm test` | 37 اختباراً آلياً على قواعد مؤقتة معزولة |
| `cd backend && npm run start:supervised` | تشغيل الخادم عبر المشرف (إعادة تشغيل تلقائية وسجل) |
| `cd app && flutter analyze && flutter test` | تحليل الكود واختبارات الواجهة |
| `cd app && flutter build web --release` | بناء نسخة الويب التي يستضيفها الخادم |
| `cd app && flutter build windows --release` | بناء تطبيق ويندوز |
| `python toolkit/generate_file_tree.py` | إعادة توليد هذه الخريطة بعد أي تغيير في البنية |

## 7. الجرد: المستخدم حالياً مقابل المجهز للمستقبل

| العنصر | الحالة | ملاحظة |
|---|---|---|
| `app/lib/**` | مستخدم | كل الشاشات تعمل على الويب وتطبيق ويندوز |
| `backend/src/**` | مستخدم | كل المسارات والمحرك والحماية |
| `backend/test/** و app/test/**` | مستخدم | تُشغَّل قبل أي بناء أو نشر |
| `backend/scripts/run-forever.js` | مستخدم | عند التشغيل التلقائي مع الويندوز |
| `backend/scripts/test_engine.js` | مستخدم | عرض توضيحي فقط، وليس اختباراً |
| `app/android/` | للمستقبل | جاهز للبناء؛ النشر على Google Play يحتاج مفتاح توقيع رسمياً |
| `app/ios/ و app/macos/` | للمستقبل | يُبنى على جهاز ماك |
| `app/linux/` | للمستقبل | غير مستخدم حالياً |

## 8. بروتوكول التحديث

1. عند إضافة ملف أو شاشة أو مسار أو جدول: حدّث البيانات في `toolkit/generate_file_tree.py`، ثم شغّله.
2. حدّث [المرجع الشامل](../خطط/المرجع_الشامل_والدليل_التشغيلي_المعتمد.md) و[سجل الإصدارات](../CHANGELOG.md) عند أي تغيير جوهري.
3. شغّل الاختبارات (`npm test` و`flutter test`) قبل رفع أي تعديل إلى `main`.
