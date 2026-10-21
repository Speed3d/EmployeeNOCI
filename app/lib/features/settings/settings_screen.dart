import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../shared/custom_button.dart';

/// Hint: لوحة التحكم الشاملة الحصرية للسوبر أدمن (Settings & System Control)
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

  // قائمة المستخدمين
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

        _users = users is List ? users : [];
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
        'active_year': _activeYearController.text.trim(),
      };

      await ApiClient.instance.put('/settings', body);

      // تحديث البانر في واجهة المستخدم فوراً
      AuthProvider.instance.updateBanner(_bannerActive ? _bannerTextController.text.trim() : null);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.onTime,
            content: Text('تم حفظ وتطبيق الإعدادات بنجاح!'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showAddUserDialog([Map<String, dynamic>? user]) {
    final isEditing = user != null;
    final usernameController = TextEditingController(text: user?['username'] ?? '');
    final nameController = TextEditingController(text: user?['full_name'] ?? '');
    final passwordController = TextEditingController();
    String role = user?['role'] ?? 'DATA_ENTRY';
    bool isActive = user?['is_active'] == 1 || user?['is_active'] == true || user == null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text(isEditing ? 'تعديل المستخدم' : 'إضافة مستخدم جديد'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'الاسم الكامل *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    enabled: !isEditing,
                    decoration: const InputDecoration(labelText: 'اسم المستخدم (Login Username) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isEditing ? 'كلمة المرور الجديدة (اتركه فارغاً للإبقاء)' : 'كلمة المرور *',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'الصلاحية / الدور *'),
                    items: const [
                      DropdownMenuItem(value: 'SUPER_ADMIN', child: Text('سوبر أدمن (تحكم كامل)')),
                      DropdownMenuItem(value: 'HR_MANAGER', child: Text('مدير موارد بشرية')),
                      DropdownMenuItem(value: 'DATA_ENTRY', child: Text('مدخل بيانات')),
                      DropdownMenuItem(value: 'AUDITOR', child: Text('مراجع / مشاهد فقط')),
                    ],
                    onChanged: (val) => setModalState(() => role = val ?? 'DATA_ENTRY'),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('الحساب نشط ومفعل'),
                      value: isActive,
                      onChanged: (val) => setModalState(() => isActive = val),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  if (!isEditing && (usernameController.text.trim().isEmpty || passwordController.text.isEmpty)) return;

                  if (!isEditing) {
                    await ApiClient.instance.post('/settings/users', {
                      'fullName': nameController.text.trim(),
                      'username': usernameController.text.trim(),
                      'password': passwordController.text.trim(),
                      'role': role,
                    });
                  } else {
                    final body = {
                      'fullName': nameController.text.trim(),
                      'role': role,
                      'isActive': isActive,
                    };
                    if (passwordController.text.isNotEmpty) {
                      body['newPassword'] = passwordController.text.trim();
                    }
                    await ApiClient.instance.put('/settings/users/${user['id']}', body);
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadSettingsAndUsers();
                  }
                },
                child: Text(isEditing ? 'تحديث' : 'إنشاء الحساب'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.navy,
            indicatorColor: AppColors.goldBright,
            tabs: const [
              Tab(icon: Icon(Icons.timer_rounded), text: 'أوقات الدوام والمكافآت'),
              Tab(icon: Icon(Icons.tune_rounded), text: 'الهوية والشريط والصيانة'),
              Tab(icon: Icon(Icons.admin_panel_settings_rounded), text: 'المستخدمين والصلاحيات'),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. أوقات الدوام والمكافآت
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'أوقات الدوام الرسمي المعتمد',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'يتم حساب التأخير والانصراف المبكر تلقائياً بناءً على هذه الأوقات:',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _workStartTimeController,
                                        decoration: const InputDecoration(
                                          labelText: 'وقت بدء الحضور الصباحي (HH:MM)',
                                          hintText: '10:00',
                                          prefixIcon: Icon(Icons.login_rounded),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: _workEndTimeController,
                                        decoration: const InputDecoration(
                                          labelText: 'وقت نهاية الدوام والانصراف (HH:MM)',
                                          hintText: '15:00',
                                          prefixIcon: Icon(Icons.logout_rounded),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // محرك احتساب المكافآت والإضافي
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('تفعيل احتساب مكافأة الحضور المبكر والدوام الإضافي', style: TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: const Text('حساب دقائق المكافأة لمن يحضر قبل الوقت أو يغادر بعد نهاية الدوام'),
                                  value: _bonusEnabled,
                                  onChanged: (val) => setState(() => _bonusEnabled = val),
                                ),
                                if (_bonusEnabled) ...[
                                  const Divider(height: 24),
                                  DropdownButtonFormField<String>(
                                    value: _bonusMode,
                                    decoration: const InputDecoration(labelText: 'نمط تحديد أوقات المكافأة'),
                                    items: const [
                                      DropdownMenuItem(value: 'default', child: Text('الوضع الافتراضي (حضور قبل 09:00 / انصراف بعد 15:00)')),
                                      DropdownMenuItem(value: 'custom', child: Text('وضع يدوي مخصص (تحديد الأوقات يدوياً)')),
                                    ],
                                    onChanged: (val) => setState(() => _bonusMode = val ?? 'default'),
                                  ),
                                  if (_bonusMode == 'custom') ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _earlyBonusTimeController,
                                            decoration: const InputDecoration(labelText: 'وقت احتساب الحضور المبكر (مثال 09:15)'),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: TextField(
                                            controller: _overtimeBonusTimeController,
                                            decoration: const InputDecoration(labelText: 'وقت احتساب الإضافي بعد الدوام (مثال 15:30)'),
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
                        const SizedBox(height: 24),

                        CustomButton(
                          label: 'حفظ إعدادات الدوام والمكافآت',
                          icon: Icons.save_rounded,
                          onPressed: _saveSettings,
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. الهوية والشريط ووضع الصيانة
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // هوية المؤسسة
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('بيانات وهوية المؤسسة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _institutionNameController,
                                  decoration: const InputDecoration(labelText: 'اسم المؤسسة الرسمي'),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _appTitleController,
                                  decoration: const InputDecoration(labelText: 'عنوان النظام في الترويسة والتقارير'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // شريط التنبيهات العلوي
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('تفعيل شريط التنبيهات والإعلانات العلوي', style: TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: const Text('إظهار شريط بلون مميز في أعلى الشاشة يراه جميع المستخدمين'),
                                  value: _bannerActive,
                                  onChanged: (val) => setState(() => _bannerActive = val),
                                ),
                                if (_bannerActive) ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _bannerTextController,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      labelText: 'نص التنبيه أو التعميم الإداري',
                                      hintText: 'مثال: يرجى من جميع الموظفين مراجعة قسم الإدارة بخصوص...',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // وضع الصيانة والترحيل السنوي
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('وضع الصيانة (Maintenance Mode)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger)),
                                  subtitle: const Text('إيقاف وصول كافة المستخدمين العاديين وإبقائه حصراً للسوبر أدمن أثناء التحديثات'),
                                  value: _maintenanceMode,
                                  onChanged: (val) => setState(() => _maintenanceMode = val),
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _activeYearController,
                                        decoration: const InputDecoration(labelText: 'السنة النشطة حالياً (مثال: 2026 أو 2027)'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.arrow_forward_rounded),
                                      label: const Text('ترحيل وفتح سنة جديدة'),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('تأكيد الترحيل السنوي'),
                                            content: Text('هل أنت متأكد من اعتماد السنة [${_activeYearController.text}] كسنة نشطة؟ (ستبقى كافة بيانات السنوات السابقة محفوظة بالكامل).'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  Navigator.pop(ctx);
                                                  await ApiClient.instance.post('/settings/switch-year', {
                                                    'year': _activeYearController.text.trim(),
                                                  });
                                                  _saveSettings();
                                                },
                                                child: const Text('تأكيد الترحيل'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        CustomButton(
                          label: 'حفظ وتطبيق كافة الإعدادات',
                          icon: Icons.save_rounded,
                          onPressed: _saveSettings,
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. إدارة المستخدمين والصلاحيات
                Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: () => _showAddUserDialog(),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('إضافة مستخدم'),
                  ),
                  body: ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _users.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final u = _users[index];
                      final isSuper = u['role'] == 'SUPER_ADMIN';

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSuper ? AppColors.goldBright.withOpacity(0.2) : AppColors.navy.withOpacity(0.1),
                            child: Icon(
                              isSuper ? Icons.security_rounded : Icons.person_rounded,
                              color: isSuper ? AppColors.goldDark : AppColors.navy,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(u['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSuper ? AppColors.goldDark.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  u['role'] ?? '',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isSuper ? AppColors.goldDark : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text('اسم الدخول: ${u['username']} • الحالة: ${u['is_active'] == 1 ? 'نشط' : 'معطل'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'تعديل الصلاحيات أو كلمة المرور',
                                onPressed: () => _showAddUserDialog(u),
                              ),
                              if (!isSuper)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                  tooltip: 'حذف الحساب',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('حذف المستخدم'),
                                        content: Text('هل أنت متأكد من حذف الحساب [${u['username']}]؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await ApiClient.instance.delete('/settings/users/${u['id']}');
                                      _loadSettingsAndUsers();
                                    }
                                  },
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
    );
  }
}
