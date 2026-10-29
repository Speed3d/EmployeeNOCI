import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'widgets/color_setting_item.dart';
import 'widgets/reset_dialog.dart';
import 'widgets/security_dialogs.dart';
import '../../core/auth_provider.dart';
import '../../shared/custom_button.dart';

/// Hint: لوحة التحكم الشاملة الحصرية للسوبر أدمن (الإصدار الثاني المعتمد)
/// تشمل كشف كلمات المرور، استثناءات الأقسام، الشعار، وتصفير النظام
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;

  // الإعدادات العامة
  final _institutionNameController = TextEditingController();
  final _appTitleController = TextEditingController();
  final _workStartTimeController = TextEditingController();
  final _workEndTimeController = TextEditingController();
  final _earlyBonusTimeController = TextEditingController();
  final _overtimeBonusTimeController = TextEditingController();
  final _singlePunchThresholdController = TextEditingController();
  final _bannerTextController = TextEditingController();
  final _activeYearController = TextEditingController();

  bool _bonusEnabled = true;
  String _bonusMode = 'default';
  bool _bannerActive = false;
  bool _maintenanceMode = false;
  String _currentLogoUrl = '';

  // ألوان تمييز حالات الموظفين
  String _colorActiveLeave = '#E8F1FC';
  String _colorSeconded = '#FFF3E0';
  String _colorTerminated = '#FFEBEE';
  String _colorVipExempt = '#ECEFF1';

  // سجل النسخ الاحتياطية
  List<dynamic> _backupsList = [];
  bool _isLoadingBackups = false;

  // قائمة المستخدمين والأقسام
  List<dynamic> _users = [];
  List<dynamic> _departments = [];


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadSettingsAndUsers();
    _loadBackups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _institutionNameController.dispose();
    _appTitleController.dispose();
    _workStartTimeController.dispose();
    _workEndTimeController.dispose();
    _earlyBonusTimeController.dispose();
    _overtimeBonusTimeController.dispose();
    _singlePunchThresholdController.dispose();
    _bannerTextController.dispose();
    _activeYearController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndUsers() async {
    setState(() => _isLoading = true);
    try {
      final settings = await ApiClient.instance.get('/settings');
      final users = await ApiClient.instance.get('/settings/users');
      final depts = await ApiClient.instance.get('/employees/departments');

      if (!mounted) return;
      setState(() {
        _institutionNameController.text = settings['institution_name'] ?? '';
        _appTitleController.text = settings['app_title'] ?? '';
        _workStartTimeController.text = settings['work_start_time'] ?? '10:00';
        _workEndTimeController.text = settings['work_end_time'] ?? '15:00';
        _bonusEnabled = settings['bonus_enabled'] == 'true';
        _bonusMode = settings['bonus_mode'] ?? 'default';
        _earlyBonusTimeController.text = settings['early_bonus_time'] ?? '09:00';
        _overtimeBonusTimeController.text = settings['overtime_bonus_time'] ?? '15:00';
        _singlePunchThresholdController.text = settings['single_punch_exit_threshold'] ?? '12:30';
        _bannerTextController.text = settings['announcement_banner_text'] ?? '';
        _bannerActive = settings['announcement_banner_active'] == 'true';
        _maintenanceMode = settings['maintenance_mode'] == 'true';
        _activeYearController.text = settings['active_year'] ?? '2026';
        _currentLogoUrl = settings['logo_url'] ?? '';

        _colorActiveLeave = settings['color_active_leave'] ?? '#E8F1FC';
        _colorSeconded = settings['color_seconded'] ?? '#FFF3E0';
        _colorTerminated = settings['color_terminated'] ?? '#FFEBEE';
        _colorVipExempt = settings['color_vip_exempt'] ?? '#ECEFF1';

        _users = users is List ? users : [];
        _departments = depts is List ? depts : [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      final body = {
        'institution_name': _institutionNameController.text.trim(),
        'app_title': _appTitleController.text.trim(),
        'work_start_time': _workStartTimeController.text.trim(),
        'work_end_time': _workEndTimeController.text.trim(),
        'bonus_enabled': _bonusEnabled.toString(),
        'bonus_mode': _bonusMode,
        'early_bonus_time': _earlyBonusTimeController.text.trim(),
        'overtime_bonus_time': _overtimeBonusTimeController.text.trim(),
        'single_punch_exit_threshold': _singlePunchThresholdController.text.trim(),
        'announcement_banner_text': _bannerTextController.text.trim(),
        'announcement_banner_active': _bannerActive.toString(),
        'maintenance_mode': _maintenanceMode.toString(),
      };

      await ApiClient.instance.put('/settings', body);
      AuthProvider.instance.updateBanner(_bannerActive ? _bannerTextController.text.trim() : null);
      AuthProvider.instance.setMaintenanceMode(_maintenanceMode);
      AuthProvider.instance.updateBranding(
        logoUrl: _currentLogoUrl,
        institutionName: _institutionNameController.text.trim(),
        appTitle: _appTitleController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حفظ الإعدادات بنجاح!')),
      );
      _loadSettingsAndUsers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  // حفظ وضع الصيانة وشريط التعاميم حصرياً
  Future<void> _saveMaintenanceSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      final body = {
        'maintenance_mode': _maintenanceMode.toString(),
        'announcement_banner_active': _bannerActive.toString(),
        'announcement_banner_text': _bannerTextController.text.trim(),
      };
      await ApiClient.instance.put('/settings', body);
      AuthProvider.instance.setMaintenanceMode(_maintenanceMode);
      AuthProvider.instance.updateBanner(_bannerActive ? _bannerTextController.text.trim() : null);

      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text(_maintenanceMode
              ? 'تم تفعيل وضع الصيانة بنجاح (محصور بالسوبر أدمن فقط)!'
              : 'تم تعطيل وضع الصيانة وحفظ الإعدادات بنجاح!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل حفظ إعدادات الصيانة: $e')));
    }
  }

  // رفع شعار المؤسسة
  Future<void> _uploadLogo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.xFile.readAsBytes();
        if (!mounted) return;
        setState(() => _isLoading = true);
        final res = await ApiClient.instance.uploadFile('/settings/logo', bytes, file.name);

        if (res != null && res['logoUrl'] != null) {
          _currentLogoUrl = res['logoUrl'];
        }

        await AuthProvider.instance.updateBranding(
          logoUrl: _currentLogoUrl,
          institutionName: _institutionNameController.text.trim(),
          appTitle: _appTitleController.text.trim(),
        );

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم رفع وتحديث الشعار المعتمد بنجاح!')),
        );
        _loadSettingsAndUsers();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(content: Text('فشل رفع الشعار: $e')));
    }
  }

  // حفظ ألوان حالات الموظفين
  Future<void> _saveStatusColors() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.put('/settings', {
        'color_active_leave': _colorActiveLeave,
        'color_seconded': _colorSeconded,
        'color_terminated': _colorTerminated,
        'color_vip_exempt': _colorVipExempt,
      });
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم حفظ ألوان حالات الموظفين بنجاح وتطبيقها على السجل!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل حفظ الألوان: $e')));
    }
  }

  // إدارة النسخ الاحتياطي والاستعادة
  Future<void> _loadBackups() async {
    setState(() => _isLoadingBackups = true);
    try {
      final res = await ApiClient.instance.get('/backup');
      if (res is List && mounted) {
        setState(() {
          _backupsList = res;
          _isLoadingBackups = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBackups = false);
    }
  }

  Future<void> _createNewBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await ApiClient.instance.post('/backup/create', {});
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم إنشاء وحفظ نقطة النسخة الاحتياطية بنجاح!'),
        ),
      );
      _loadBackups();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل إنشاء النسخة: $e')));
    }
  }

  // Hint: التنزيل برابط مؤقت (60 ثانية) بدل وضع رمز الجلسة في الرابط
  Future<void> _downloadBackup(String? filename) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ApiClient.instance.downloadUrl('backup', {'filename': filename ?? 'current'});
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر بدء التنزيل: $e')));
    }
  }

  Future<void> _restoreBackupFromFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    final file = files.first;
    if (!file.name.toLowerCase().endsWith('.db')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: AppColors.danger, content: Text('يرجى اختيار ملف قاعدة بيانات SQLite بصيغة .db حصراً')),
        );
      }
      return;
    }

    if (!mounted) return;
    final verified = await showSensitiveActionPrompt(context, 'استعادة قاعدة البيانات من ملف خارجي: (${file.name})');
    if (verified != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final bytes = await file.xFile.readAsBytes();
    setState(() => _isLoading = true);
    try {
      await ApiClient.instance.uploadFile('/backup/restore', bytes, file.name);
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم استعادة قاعدة البيانات بنجاح تام! تم تحديث كافة السجلات.'),
        ),
      );
      _loadBackups();
      _loadSettingsAndUsers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل الاستعادة: $e')));
    }
  }

  Future<void> _restoreNamedBackup(String filename) async {
    final verified = await showSensitiveActionPrompt(context, 'استعادة قاعدة البيانات من النسخة: [$filename]');
    if (verified != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await ApiClient.instance.post('/backup/restore', {'filename': filename});
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم استعادة قاعدة البيانات بنجاح من النسخة [$filename]!'),
        ),
      );
      _loadBackups();
      _loadSettingsAndUsers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل الاستعادة: $e')));
    }
  }

  Future<void> _deleteNamedBackup(String filename) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف النسخة الاحتياطية [$filename] نهائياً من السيرفر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.instance.delete('/backup/$filename');
      _loadBackups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
  }

  // كشف كلمة المرور لمستخدم محدد (النقطة 15)
  // Hint: الخادم هو من يتحقق من كلمة مرور الأدمن قبل الكشف، ويسجل العملية في سجل الحركات
  Future<void> _revealPassword(int userId, String username) async {
    final adminPassword = await askAdminPassword(context, 'كشف كلمة مرور المستخدم [$username]');
    if (adminPassword == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ApiClient.instance.post('/settings/users/$userId/reveal-password', {'adminPassword': adminPassword});
      final pass = res['password'] ?? '';

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.remove_red_eye_rounded, color: AppColors.navy),
              const SizedBox(width: 8),
              Text('كلمة مرور [$username]'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('كلمة المرور الحالية هي:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.navy.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  pass,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '⚠️ تنبيه أمني: تم تسجيل عملية كشف كلمة المرور هذه بالوقت وعنوان الـ IP في سجل التدقيق الأمني.',
                style: TextStyle(fontSize: 11, color: AppColors.late, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل كشف كلمة المرور: $e')),
      );
    }
  }

  /// Hint: تصفير النظام وإعادة الضبط (حصري للسوبر أدمن) مع خيارين:
  /// 1. factory_default: إعادة الضبط لنقطة البداية الأصلية مع إعادة الموظفين للنسخة الأصلية
  /// 2. wipe_all: تصفير شامل بالكامل مع حذف الموظفين والأقسام ليصبح النظام فارغاً تماماً
  Future<void> _resetDatabase() async {
    final choice = await showResetDialog(context);
    if (choice == null || !mounted) return;
    final selectedResetMode = choice.mode;


    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.post('/settings/reset-db', {
        'password': choice.password,
        'resetMode': selectedResetMode,
      });

      // Hint: تحديث حالة الهوية والإعدادات في الذاكرة المحلية فوراً لتعكس وضع المصنع
      AuthProvider.instance.updateBranding(
        logoUrl: '',
        institutionName: 'اللجنة الأولمبية الوطنية العراقية (NOCI)',
        appTitle: 'نظام متابعة حضور وانصراف موظفي المقر',
      );
      AuthProvider.instance.updateBanner(null);
      AuthProvider.instance.setMaintenanceMode(false);
      await AuthProvider.instance.setActiveYear('2026');

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text(
            (res is Map && res['message'] != null)
                ? res['message'].toString()
                : (selectedResetMode == 'wipe_all'
                    ? 'تم التصفير الشامل بالكامل وحذف جميع الموظفين والسجلات والإعدادات بنجاح!'
                    : 'تمت إعادة ضبط النظام لنقطة البداية الأصلية بنجاح!'),
          ),
        ),
      );
      await _loadSettingsAndUsers();
      await _loadBackups();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل التصفير: $e')),
      );
    }
  }

  /// Hint: الترحيل السنوي وتبديل السنة الإدارية/المالية الفعالة في النظام
  Future<void> _switchActiveYear() async {
    final newYear = _activeYearController.text.trim();
    if (newYear.isEmpty || int.tryParse(newYear) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.danger, content: Text('يرجى إدخال سنة صحيحة (مثال: 2026)')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await ApiClient.instance.post('/settings/switch-year', {'year': newYear, 'newYear': newYear});
      await AuthProvider.instance.setActiveYear(newYear);
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text('تم اعتماد السنة المالية/الإدارية النشطة ($newYear) بنجاح!'),
        ),
      );
      _loadSettingsAndUsers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل تبديل السنة: $e')));
    }
  }

  /// Hint: حذف حساب مستخدم من النظام مع التحقق الأمني ومنع حذف الحساب الحالي
  Future<void> _deleteUser(Map<String, dynamic> targetUser) async {
    final currentUserId = AuthProvider.instance.user?['id'];
    if (targetUser['id'] == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.danger, content: Text('لا يمكنك حذف حسابك الشخصي الحالي')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف المستخدم'),
        content: Text('هل أنت متأكد من حذف حساب المستخدم [${targetUser['full_name']} (@${targetUser['username']})] نهائياً؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، حذف الحساب'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiClient.instance.delete('/settings/users/${targetUser['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حذف حساب المستخدم بنجاح')),
      );
      _loadSettingsAndUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل حذف المستخدم: $e')),
      );
    }
  }

  // إضافة أو تعديل مستخدم
  void _showUserDialog([Map<String, dynamic>? user]) {
    final isEdit = user != null;
    final usernameController = TextEditingController(text: user?['username']);
    final fullNameController = TextEditingController(text: user?['full_name']);
    final passwordController = TextEditingController();
    String role = user?['role'] ?? 'DATA_ENTRY';
    bool canManageExclusions = user?['can_manage_exclusions'] == 1;
    bool canRecommit = user?['can_recommit'] == 1;
    bool isActive = user?['is_active'] != 0;
    final isSelf = isEdit && user['id'] == AuthProvider.instance.user?['id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text(isEdit ? 'تعديل بيانات المستخدم' : 'إضافة مستخدم جديد'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      enabled: !isEdit,
                      decoration: const InputDecoration(labelText: 'اسم المستخدم (للدخول) *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'الاسم الكامل *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isEdit ? 'كلمة المرور الجديدة (اتركه فارغاً للإبقاء)' : 'كلمة المرور المؤقتة *',
                        helperText: '8 خانات على الأقل وتحتوي حرفاً ورقماً. سيُطلب من المستخدم تغييرها عند دخوله',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSelf)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('لا يمكنك تغيير رتبتك أو تعطيل حسابك بنفسك.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'الرتبة والدور *', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'SUPER_ADMIN', child: Text('سوبر أدمن (تحكم كامل)')),
                        DropdownMenuItem(value: 'DATA_ENTRY', child: Text('مدخل بيانات')),
                      ],
                      onChanged: isSelf ? null : (val) => setModalState(() => role = val!),
                    ),
                    const SizedBox(height: 12),
                    // تفويض الصلاحيات لمدخل البيانات
                    if (role == 'DATA_ENTRY') ...[
                      SwitchListTile(
                        title: const Text('صلاحية تعديل استثناء الأقسام', style: TextStyle(fontSize: 13)),
                        value: canManageExclusions,
                        onChanged: (val) => setModalState(() => canManageExclusions = val),
                      ),
                      SwitchListTile(
                        title: const Text('صلاحية إعادة اعتماد كشف سبق اعتماده', style: TextStyle(fontSize: 13)),
                        value: canRecommit,
                        onChanged: (val) => setModalState(() => canRecommit = val),
                      ),
                    ],
                    if (isEdit && !isSelf)
                      SwitchListTile(
                        title: const Text('حالة الحساب (نشط ومسموح له بالدخول)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        value: isActive,
                        activeThumbColor: AppColors.onTime,
                        onChanged: (val) => setModalState(() => isActive = val),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () async {
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    if (isEdit) {
                      await ApiClient.instance.put('/settings/users/${user['id']}', {
                        'fullName': fullNameController.text.trim(),
                        if (!isSelf) 'role': role,
                        'newPassword': passwordController.text.isNotEmpty ? passwordController.text : null,
                        'canManageExclusions': canManageExclusions,
                        'canRecommit': canRecommit,
                        if (!isSelf) 'isActive': isActive,
                      });
                    } else {
                      await ApiClient.instance.post('/settings/users', {
                        'username': usernameController.text.trim(),
                        'fullName': fullNameController.text.trim(),
                        'password': passwordController.text,
                        'role': role,
                        'canManageExclusions': canManageExclusions,
                        'canRecommit': canRecommit,
                      });
                    }
                    navigator.pop();
                    _loadSettingsAndUsers();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('خطأ: $e')));
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.instance;

    // حماية لوحة الإعدادات للسوبر أدمن فقط
    if (!auth.isSuperAdmin) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 64, color: AppColors.danger),
            SizedBox(height: 16),
            Text(
              'عذراً، لوحة الإعدادات والصيانة محصورة بالسوبر أدمن فقط',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.navy,
            indicatorColor: AppColors.gold,
            tabs: const [
              Tab(icon: Icon(Icons.access_time_rounded), text: 'قواعد الدوام والمكافأة'),
              Tab(icon: Icon(Icons.branding_watermark_rounded), text: 'الهوية والمؤسسة'),
              Tab(icon: Icon(Icons.palette_rounded), text: 'ألوان حالات الموظفين'),
              Tab(icon: Icon(Icons.filter_alt_off_rounded), text: 'استثناء الأقسام'),
              Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'المستخدمون والصلاحيات'),
              Tab(icon: Icon(Icons.cloud_sync_rounded), text: 'النسخ الاحتياطي والاستعادة'),
              Tab(icon: Icon(Icons.restart_alt_rounded), text: 'تصفير النظام والصيانة'),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // تبويب 1: قواعد الدوام والمكافأة
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('أوقات الدوام الرسمي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _workStartTimeController,
                                          decoration: const InputDecoration(labelText: 'بدء الدوام (10:00)', border: OutlineInputBorder()),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextField(
                                          controller: _workEndTimeController,
                                          decoration: const InputDecoration(labelText: 'نهاية الدوام (15:00)', border: OutlineInputBorder()),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _singlePunchThresholdController,
                                    decoration: const InputDecoration(
                                      labelText: 'عتبة البصمة المنفردة (12:30)',
                                      helperText: 'إذا بصم الموظف مرة واحدة بعد هذا الوقت تُعامل كبصمة خروج فقط (يجب أن تقع بين بداية الدوام ونهايته)',
                                      helperMaxLines: 2,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile(
                                    title: const Text('تفعيل مكافأة الحضور المبكر والإضافي', style: TextStyle(fontWeight: FontWeight.bold)),
                                    value: _bonusEnabled,
                                    onChanged: (val) => setState(() => _bonusEnabled = val),
                                  ),
                                  if (_bonusEnabled) ...[
                                    const SizedBox(height: 12),
                                    const Text('نمط احتساب المكافأة:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    RadioGroup<String>(
                                      groupValue: _bonusMode,
                                      onChanged: (val) => setState(() => _bonusMode = val!),
                                      child: const Wrap(
                                        children: [
                                          SizedBox(
                                            width: 360,
                                            child: RadioListTile<String>(
                                              title: Text('افتراضي (قبل بداية الدوام بساعة، وبعد نهايته)', style: TextStyle(fontSize: 13)),
                                              value: 'default',
                                            ),
                                          ),
                                          SizedBox(
                                            width: 260,
                                            child: RadioListTile<String>(
                                              title: Text('مخصص حسب الرغبة', style: TextStyle(fontSize: 13)),
                                              value: 'custom',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_bonusMode == 'custom') ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _earlyBonusTimeController,
                                              decoration: const InputDecoration(labelText: 'وقت الحضور المبكر', border: OutlineInputBorder()),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: TextField(
                                              controller: _overtimeBonusTimeController,
                                              decoration: const InputDecoration(labelText: 'وقت بدء الإضافي', border: OutlineInputBorder()),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          CustomButton(label: 'حفظ إعدادات الدوام', onPressed: _saveSettings),
                        ],
                      ),
                    ),

                    // تبويب 2: الهوية والمؤسسة
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('هوية وشعار النظام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _institutionNameController,
                                    decoration: const InputDecoration(labelText: 'اسم المؤسسة الرسمي', border: OutlineInputBorder()),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _appTitleController,
                                    decoration: const InputDecoration(labelText: 'عنوان النظام في الترويسة', border: OutlineInputBorder()),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.image_rounded),
                                        label: const Text('رفع وتغيير شعار المؤسسة'),
                                        onPressed: _uploadLogo,
                                      ),
                                      const SizedBox(width: 16),
                                      if (_currentLogoUrl.isNotEmpty) ...[
                                        Container(
                                          width: 50,
                                          height: 50,
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade300),
                                            color: Colors.white,
                                          ),
                                          child: Image.network(
                                            '${ApiClient.instance.serverOrigin}$_currentLogoUrl',
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, size: 24, color: Colors.grey),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('معاينة الشعار المعتمد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          CustomButton(label: 'حفظ بيانات الهوية', onPressed: _saveSettings),
                        ],
                      ),
                    ),

                    // تبويب 3: ألوان حالات الموظفين
                    _buildStatusColorsTab(),

                    // تبويب 4: استثناء الأقسام (النقطة 5 و 7)
                    ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _departments.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final dept = _departments[index];
                        final isExcluded = dept['is_excluded'] == 1;

                        return Card(
                          child: SwitchListTile(
                            title: Text(
                              dept['name'],
                              style: TextStyle(
                                fontWeight: isExcluded ? FontWeight.normal : FontWeight.bold,
                                color: isExcluded ? Colors.grey : AppColors.navy,
                              ),
                            ),
                            subtitle: Text(
                              isExcluded ? 'مستبعد من كشف الحضور والتقارير' : 'مشمول بكافة كشوفات الحضور',
                              style: TextStyle(color: isExcluded ? AppColors.danger : AppColors.onTime, fontSize: 12),
                            ),
                            value: isExcluded,
                            activeThumbColor: AppColors.danger,
                            onChanged: (val) async {
                              try {
                                await ApiClient.instance.put('/employees/departments/${dept['id']}/exclusion', {
                                  'isExcluded': val,
                                });
                                _loadSettingsAndUsers();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                              }
                            },
                          ),
                        );
                      },
                    ),

                    // تبويب 4: المستخدمون والصلاحيات (النقطة 15)
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('قائمة مستخدمي النظام ورتبهم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                                icon: const Icon(Icons.person_add_rounded, size: 18),
                                label: const Text('إضافة مستخدم'),
                                onPressed: () => _showUserDialog(),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _users.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final u = _users[index];
                              final isSuper = u['role'] == 'SUPER_ADMIN';

                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSuper ? AppColors.gold : AppColors.navy,
                                    child: Icon(isSuper ? Icons.shield_rounded : Icons.person_rounded, color: Colors.white, size: 20),
                                  ),
                                  title: Text(
                                    '${u['full_name']} (@${u['username']})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'الدور: ${isSuper ? 'سوبر أدمن' : 'مدخل بيانات'}'
                                    '${u['is_active'] == 0 ? ' • [الحساب معطل]' : ''}'
                                    '${u['must_change_password'] == 1 ? ' • [كلمة مرور مؤقتة]' : ''}'
                                    '${u['can_manage_exclusions'] == 1 ? ' • [صلاحية استثناء]' : ''}'
                                    '${u['can_recommit'] == 1 ? ' • [صلاحية إعادة الاعتماد]' : ''}',
                                    style: TextStyle(fontSize: 12, color: u['is_active'] == 0 ? AppColors.danger : null),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // زر كشف كلمة المرور (👁️)
                                      IconButton(
                                        icon: const Icon(Icons.remove_red_eye_rounded, color: AppColors.navy),
                                        tooltip: 'كشف كلمة المرور',
                                        onPressed: () => _revealPassword(u['id'], u['username']),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded, color: Colors.blueGrey),
                                        tooltip: 'تعديل',
                                        onPressed: () => _showUserDialog(u),
                                      ),
                                      if (u['id'] != auth.user?['id'])
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                          tooltip: 'حذف المستخدم',
                                          onPressed: () => _deleteUser(u),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    // تبويب 6: النسخ الاحتياطي والاستعادة
                    _buildBackupRestoreTab(),

                    // تبويب 7: تصفير النظام والصيانة والترحيل السنوي
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // بطاقة الترحيل السنوي والسنة الفعالة
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.calendar_month_rounded, color: AppColors.navy, size: 22),
                                      SizedBox(width: 8),
                                      Text('السنة الإدارية / المالية النشطة والترحيل السنوي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'تحدد السنة النشطة أرشيف سجلات الحضور والعطل الرسمية الافتراضية المعروضة في النظام:',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 180,
                                        child: TextField(
                                          controller: _activeYearController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'السنة النشطة (مثال: 2026)',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.navy,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        icon: const Icon(Icons.published_with_changes_rounded, size: 18),
                                        label: const Text('تحديث واعتماد السنة', style: TextStyle(fontWeight: FontWeight.bold)),
                                        onPressed: _switchActiveYear,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // بطاقة الصيانة والتعاميم
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('الصيانة وشريط التعاميم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    title: const Text('وضع الصيانة (يمنع مدخلي البيانات من الدخول)'),
                                    value: _maintenanceMode,
                                    onChanged: (val) => setState(() => _maintenanceMode = val),
                                  ),
                                  const Divider(),
                                  SwitchListTile(
                                    title: const Text('تفعيل شريط التنبيهات والتعاميم العلوي'),
                                    value: _bannerActive,
                                    onChanged: (val) => setState(() => _bannerActive = val),
                                  ),
                                  if (_bannerActive) ...[
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _bannerTextController,
                                      decoration: const InputDecoration(labelText: 'نص التعميم العلوي', border: OutlineInputBorder()),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.navy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.save_rounded, size: 18),
                                    label: const Text('حفظ إعدادات وضع الصيانة والتعاميم', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: _saveMaintenanceSettings,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // بطاقة تصفير النظام التحذيرية
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.warning_rounded, color: AppColors.danger, size: 28),
                                    SizedBox(width: 10),
                                    Text(
                                      'منطقة الخطر: تصفير النظام وإعادة الضبط',
                                      style: TextStyle(color: AppColors.danger, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'تستخدم هذه العملية أثناء فترة التطوير والبناء أو عند بدء مرحلة جديدة تماماً، حيث تقوم بمسح كافة سجلات الحضور اليومية والأيام المعتمدة والإجازات وجداول الدوام مع بقاء حسابك وقوالب النظام سليمة. تتطلب العملية إدخال كلمة مرور السوبر أدمن للتأكيد.',
                                  style: TextStyle(fontSize: 13, height: 1.5),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.delete_forever_rounded, size: 20),
                                  label: const Text('تصفير النظام وإعادة الضبط للبداية', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: _resetDatabase,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Hint: تبويب تخصيص ألوان حالات الموظفين في السجل
  Widget _buildStatusColorsTab() {
    final activeLeaveColor = parseHexColor(_colorActiveLeave, const Color(0xFFE8F1FC));
    final secondedColor = parseHexColor(_colorSeconded, const Color(0xFFFFF3E0));
    final terminatedColor = parseHexColor(_colorTerminated, const Color(0xFFFFEBEE));
    final vipExemptColor = parseHexColor(_colorVipExempt, const Color(0xFFECEFF1));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.palette_rounded, color: AppColors.navy, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'ألوان تمييز حالات الموظفين في السجل (خاص بالسوبر أدمن)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'يمكنك هنا تخصيص الألوان التي تُلوّن بها خلايا وبطاقات الموظفين في شاشة سجل ودليل الموظفين وفق حالتهم الوظيفية الحالية:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // 1. إجازة حالياً وسارية
                  buildColorSettingItem(
                    title: '1. لون الموظف المجاز حالياً (إجازة سارية)',
                    subtitle: 'تُطبق على أي موظف لديه إجازة معتمدة تغطي تاريخ اليوم الحالي',
                    currentColorHex: _colorActiveLeave,
                    palette: const ['#E8F1FC', '#E3F2FD', '#E0F7FA', '#E8F8F5', '#F4ECF7'],
                    onColorSelected: (val) => setState(() => _colorActiveLeave = val),
                  ),
                  const Divider(height: 32),

                  // 2. موظف تنسيب
                  buildColorSettingItem(
                    title: '2. لون موظفي التنسيب (تنسيب)',
                    subtitle: 'تُطبق على موظفي قسم أو حالة التنسيب في السجل',
                    currentColorHex: _colorSeconded,
                    palette: const ['#FFE0B2', '#FFCC80', '#FFF3E0', '#FFD180', '#FFE8D6'],
                    onColorSelected: (val) => setState(() => _colorSeconded = val),
                  ),
                  const Divider(height: 32),

                  // 3. منتهي خدماته / استقالة / متوفى
                  buildColorSettingItem(
                    title: '3. لون الموظف المنتهي خدماته (استقالة / إنهاء خدمة / متوفى)',
                    subtitle: 'تُطبق على المستقيلين أو المتوفين لتمييزهم فورياً عن الكادر النشط',
                    currentColorHex: _colorTerminated,
                    palette: const ['#FFEBEE', '#FFCDD2', '#FDEDEC', '#FADBD8', '#F5EEF8'],
                    onColorSelected: (val) => setState(() => _colorTerminated = val),
                  ),
                  const Divider(height: 32),

                  // 4. مستثنى قيادي VIP
                  buildColorSettingItem(
                    title: '4. لون المستثنى القيادي (VIP)',
                    subtitle: 'تُطبق على الأمين العام والمستشارين المستثنين رسمياً من البصمة',
                    currentColorHex: _colorVipExempt,
                    palette: const ['#ECEFF1', '#CFD8DC', '#F2F4F4', '#EAEDED', '#E5E8E8'],
                    onColorSelected: (val) => setState(() => _colorVipExempt = val),
                  ),

                  const SizedBox(height: 28),

                  // معاينة مباشرة
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('معاينة حية لشكل البطاقات في سجل الموظفين بالألوان المحددة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: buildMiniCardPreview('مجاز حالياً', '🏖️ إجازة سارية', activeLeaveColor, const Color(0xFF1976D2))),
                            const SizedBox(width: 8),
                            Expanded(child: buildMiniCardPreview('تنسيب', '📋 تنسيب', secondedColor, const Color(0xFFE65100))),
                            const SizedBox(width: 8),
                            Expanded(child: buildMiniCardPreview('منتهي خدماته', '🛑 استقالة', terminatedColor, const Color(0xFFD32F2F))),
                            const SizedBox(width: 8),
                            Expanded(child: buildMiniCardPreview('مستثنى VIP', '⭐ قيادي VIP', vipExemptColor, const Color(0xFF546E7A))),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('حفظ ألوان حالات الموظفين', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _saveStatusColors,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hint: تبويب النسخ الاحتياطي والاستعادة الفورية لقاعدة البيانات
  Widget _buildBackupRestoreTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. بطاقة إنشاء وتحميل نسخة احتياطية
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.backup_rounded, color: AppColors.navy, size: 24),
                      SizedBox(width: 10),
                      Text('النسخ الاحتياطي لقاعدة البيانات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'يمكنك إنشاء نقطة نسخ احتياطي فورية لكامل قاعدة البيانات (السجلات، الموظفين، الحضور، الإعدادات) وحفظها على السيرفر أو تنزيلها مباشرة إلى جهازك بصيغة .db لاستخدامها وقت الحاجة:',
                    style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                        label: const Text('إنشاء نقطة نسخ احتياطي جديدة على السيرفر', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _createNewBackup,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          side: BorderSide(color: AppColors.navy.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('تنزيل نسخة احتياطية فورية على جهاز الكمبيوتر (.db)', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _downloadBackup('current'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. بطاقة استعادة نسخة احتياطية من جهاز المستخدم
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings_backup_restore_rounded, color: Color(0xFFF57F17), size: 24),
                    SizedBox(width: 10),
                    Text('استعادة قاعدة البيانات من ملف خارجي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'تتيح لك هذه الميزة رفع ملف قاعدة بيانات (.db) سبق حفظه واسترجاع كافة البيانات كما كانت. حفاظاً على الأمان، يقوم النظام تلقائياً بأخذ نسخة أمان استباقية قبل الاستبدال، ويتطلب إدخال كلمة مرور السوبر أدمن للتأكيد.',
                  style: TextStyle(fontSize: 13, color: Colors.brown, height: 1.4),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57F17),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('اختيار ملف قاعدة بيانات (.db) واستعادة البيانات', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _restoreBackupFromFile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. جدول النسخ الاحتياطية المحفوظة محلياً
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.history_rounded, color: AppColors.navy, size: 22),
                          SizedBox(width: 8),
                          Text('النسخ الاحتياطية المحفوظة على السيرفر', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: AppColors.navy),
                        tooltip: 'تحديث القائمة',
                        onPressed: _loadBackups,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingBackups)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else if (_backupsList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('لا توجد نسخ احتياطية محفوظة حتى الآن، اضغط على زر الإنشاء أعلاه لحفظ أول نسخة', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _backupsList.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final b = _backupsList[i];
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F1FC),
                            child: Icon(Icons.storage_rounded, color: AppColors.navy, size: 20),
                          ),
                          title: Text(b['filename'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text('الحجم: ${b['sizeFormatted']} • تاريخ الإنشاء: ${b['createdAt']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                icon: const Icon(Icons.restore_rounded, size: 16, color: AppColors.navy),
                                label: const Text('استعادة', style: TextStyle(fontSize: 11, color: AppColors.navy)),
                                onPressed: () => _restoreNamedBackup(b['filename']),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, size: 18, color: AppColors.navy),
                                tooltip: 'تنزيل على جهازك',
                                onPressed: () => _downloadBackup(b['filename']),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                tooltip: 'حذف النسخة',
                                onPressed: () => _deleteNamedBackup(b['filename']),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
