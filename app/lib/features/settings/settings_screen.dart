import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
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
  final _bannerTextController = TextEditingController();
  final _activeYearController = TextEditingController();

  bool _bonusEnabled = true;
  String _bonusMode = 'default';
  bool _bannerActive = false;
  bool _maintenanceMode = false;
  String _currentLogoUrl = '';

  // قائمة المستخدمين والأقسام
  List<dynamic> _users = [];
  List<dynamic> _departments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadSettingsAndUsers();
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

      setState(() {
        _institutionNameController.text = settings['institution_name'] ?? '';
        _appTitleController.text = settings['app_title'] ?? '';
        _workStartTimeController.text = settings['work_start_time'] ?? '10:00';
        _workEndTimeController.text = settings['work_end_time'] ?? '15:00';
        _bonusEnabled = settings['bonus_enabled'] == 'true';
        _bonusMode = settings['bonus_mode'] ?? 'default';
        _earlyBonusTimeController.text = settings['early_bonus_time'] ?? '09:00';
        _overtimeBonusTimeController.text = settings['overtime_bonus_time'] ?? '15:00';
        _bannerTextController.text = settings['announcement_banner_text'] ?? '';
        _bannerActive = settings['announcement_banner_active'] == 'true';
        _maintenanceMode = settings['maintenance_mode'] == 'true';
        _activeYearController.text = settings['active_year'] ?? '2026';
        _currentLogoUrl = settings['logo_url'] ?? '';

        _users = users is List ? users : [];
        _departments = depts is List ? depts : [];
        _isLoading = false;
      });
    } catch (e) {
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

  // كشف كلمة المرور لمستخدم محدد (النقطة 15)
  Future<void> _revealPassword(int userId, String username) async {
    try {
      final res = await ApiClient.instance.get('/settings/users/$userId/reveal-password');
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
                  border: Border.all(color: AppColors.navy.withOpacity(0.3)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل كشف كلمة المرور: $e')),
      );
    }
  }

  // تصفير النظام وإعادة الضبط (حصري للسوبر أدمن)
  Future<void> _resetDatabase() async {
    final passwordController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
            SizedBox(width: 8),
            Text('تصفير النظام وإعادة الضبط'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تحذير صارم: هذه العملية ستقوم بحذف كافة سجلات الحضور والانصراف، الأيام المعتمدة، الإجازات، وجداول الدوام وإعادة النظام لنقطة البداية.',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('للتأكيد، يرجى إدخال كلمة مرور السوبر أدمن:'),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد التصفير النهائي'),
          ),
        ],
      ),
    );

    if (confirm != true || passwordController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.post('/settings/reset-db', {
        'password': passwordController.text.trim(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text(res['message'] ?? 'تم تصفير النظام وإعادة الضبط بنجاح!'),
        ),
      );
      _loadSettingsAndUsers();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل التصفير: $e')),
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
                        labelText: isEdit ? 'كلمة المرور الجديدة (اتركه فارغاً للإبقاء)' : 'كلمة المرور *',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(labelText: 'الرتبة والدور *', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'SUPER_ADMIN', child: Text('سوبر أدمن (تحكم كامل)')),
                        DropdownMenuItem(value: 'DATA_ENTRY', child: Text('مدخل بيانات')),
                      ],
                      onChanged: (val) => setModalState(() => role = val!),
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () async {
                  try {
                    if (isEdit) {
                      await ApiClient.instance.put('/settings/users/${user['id']}', {
                        'fullName': fullNameController.text.trim(),
                        'role': role,
                        'newPassword': passwordController.text.trim().isNotEmpty ? passwordController.text.trim() : null,
                        'canManageExclusions': canManageExclusions,
                        'canRecommit': canRecommit,
                      });
                    } else {
                      await ApiClient.instance.post('/settings/users', {
                        'username': usernameController.text.trim(),
                        'fullName': fullNameController.text.trim(),
                        'password': passwordController.text.trim(),
                        'role': role,
                        'canManageExclusions': canManageExclusions,
                        'canRecommit': canRecommit,
                      });
                    }
                    Navigator.pop(ctx);
                    _loadSettingsAndUsers();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
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
              Tab(icon: Icon(Icons.filter_alt_off_rounded), text: 'استثناء الأقسام'),
              Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'المستخدمون والصلاحيات'),
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: RadioListTile<String>(
                                            title: const Text('افتراضي (09:00 و 15:00)', style: TextStyle(fontSize: 13)),
                                            value: 'default',
                                            groupValue: _bonusMode,
                                            onChanged: (val) => setState(() => _bonusMode = val!),
                                          ),
                                        ),
                                        Expanded(
                                          child: RadioListTile<String>(
                                            title: const Text('مخصص حسب الرغبة', style: TextStyle(fontSize: 13)),
                                            value: 'custom',
                                            groupValue: _bonusMode,
                                            onChanged: (val) => setState(() => _bonusMode = val!),
                                          ),
                                        ),
                                      ],
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
                                            '${ApiClient.instance.baseUrl.replaceAll('/api', '')}$_currentLogoUrl',
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 24, color: Colors.grey),
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

                    // تبويب 3: استثناء الأقسام (النقطة 5 و 7)
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
                            activeColor: AppColors.danger,
                            onChanged: (val) async {
                              try {
                                await ApiClient.instance.put('/employees/departments/${dept['id']}/exclusion', {
                                  'isExcluded': val,
                                });
                                _loadSettingsAndUsers();
                              } catch (e) {
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
                                    'الدور: ${isSuper ? 'سوبر أدمن' : 'مدخل بيانات'}' +
                                        (u['can_manage_exclusions'] == 1 ? ' • [صلاحية استثناء]' : '') +
                                        (u['can_recommit'] == 1 ? ' • [صلاحية إعادة الاعتماد]' : ''),
                                    style: const TextStyle(fontSize: 12),
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
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    // تبويب 5: تصفير النظام والصيانة
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                              color: AppColors.danger.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
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
}
