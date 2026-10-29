import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

/// Hint: نافذة الملف الشخصي للمستخدم الحالي (النقطة 14)
/// تتيح تعديل الاسم، رفع صورة شخصية من الحاسوب، وتغيير كلمة المرور
class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _fullNameController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isChangingPassword = false;
  bool _isLoading = false;
  String? _error;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    final user = AuthProvider.instance.user;
    _fullNameController.text = user?['fullName'] ?? '';
    _avatarUrl = user?['avatarUrl'];
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // رفع صورة شخصية من الحاسوب
  Future<void> _pickAndUploadAvatar() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.xFile.readAsBytes();

        if (!mounted) return;
        setState(() => _isLoading = true);
        final messenger = ScaffoldMessenger.of(context);
        final res = await ApiClient.instance.uploadFile('/auth/avatar', bytes, file.name);
        if (!mounted) return;

        setState(() {
          _avatarUrl = res['avatarUrl'];
          _isLoading = false;
        });

        AuthProvider.instance.updateUser({'avatarUrl': _avatarUrl});
        messenger.showSnackBar(
          const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم تحديث الصورة الشخصية بنجاح!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'تعذر رفع الصورة: $e';
      });
    }
  }

  Future<void> _saveProfile() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;
    final oldPass = _oldPasswordController.text;

    if (_isChangingPassword) {
      if (oldPass.isEmpty) {
        setState(() => _error = 'يرجى إدخال كلمة المرور الحالية لتأكيد التغيير');
        return;
      }
      if (newPass.length < 8 ||
          !RegExp(r'[A-Za-z؀-ۿ]').hasMatch(newPass) ||
          !RegExp(r'[0-9٠-٩]').hasMatch(newPass)) {
        setState(() => _error = 'كلمة المرور الجديدة يجب ألا تقل عن 8 خانات وأن تحتوي حرفاً ورقماً');
        return;
      }
      if (newPass != confirmPass) {
        setState(() => _error = 'كلمتا المرور غير متطابقتين');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final body = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
        'avatarUrl': _avatarUrl,
      };

      if (_isChangingPassword && newPass.isNotEmpty) {
        body['oldPassword'] = oldPass;
        body['newPassword'] = newPass;
      }

      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final res = await ApiClient.instance.put('/auth/profile', body);
      // Hint: عند تغيير كلمة المرور يُرجع الخادم رمز جلسة جديداً ويُبطل القديم
      await AuthProvider.instance.applyProfileUpdate(res);

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حفظ بيانات الملف الشخصي بنجاح!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthProvider.instance.user;
    final isSuper = AuthProvider.instance.isSuperAdmin;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person_rounded, color: AppColors.navy),
          SizedBox(width: 8),
          Text('الملف الشخصي'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الصورة الشخصية مع زر التغيير
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.12),
                      backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? NetworkImage('${ApiClient.instance.serverOrigin}$_avatarUrl')
                          : null,
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? Text(
                              (user?['fullName'] ?? 'U').substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.navy),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _isLoading ? null : _pickAndUploadAvatar,
                        child: const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.gold,
                          child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // اسم المستخدم (للقراءة فقط)
              TextField(
                controller: TextEditingController(text: user?['username']),
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم (للدخول)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),

              // الرتبة (للقراءة فقط)
              TextField(
                controller: TextEditingController(text: isSuper ? 'سوبر أدمن (تحكم كامل)' : 'مدخل بيانات'),
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'الرتبة والصلاحية',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shield_rounded),
                ),
              ),
              const SizedBox(height: 12),

              // الاسم الكامل (قابل للتعديل)
              TextField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // تغيير كلمة المرور
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('أرغب في تغيير كلمة المرور', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                value: _isChangingPassword,
                onChanged: (val) => setState(() => _isChangingPassword = val ?? false),
              ),

              if (_isChangingPassword) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الحالية *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة * (6 خانات على الأقل)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.check_rounded),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
          onPressed: _isLoading ? null : _saveProfile,
          child: const Text('حفظ التعديلات'),
        ),
      ],
    );
  }
}
