import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';

/// Hint: شاشة إلزامية لتغيير كلمة المرور المؤقتة عند أول دخول أو بعد إعادة تعيينها من الأدمن
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSaving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateNew(String? v) {
    final value = v ?? '';
    if (value.length < 8) return 'يجب ألا تقل كلمة المرور عن 8 خانات';
    if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(value) || !RegExp(r'[0-9٠-٩]').hasMatch(value)) {
      return 'يجب أن تحتوي على حرف ورقم على الأقل';
    }
    if (value != value.trim()) return 'لا يُسمح بمسافات في البداية أو النهاية';
    if (value == _oldController.text) return 'يجب أن تختلف عن كلمة المرور الحالية';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.put('/auth/profile', {
        'oldPassword': _oldController.text,
        'newPassword': _newController.text,
      });
      await AuthProvider.instance.applyProfileUpdate(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSaving = false;
      });
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: IconButton(
        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthProvider.instance.user;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 48, color: AppColors.navy),
                      const SizedBox(height: 12),
                      const Text(
                        'تغيير كلمة المرور المؤقتة',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'مرحباً ${user?['fullName'] ?? ''}، كلمة المرور الحالية مؤقتة. يرجى اختيار كلمة مرور جديدة خاصة بك للمتابعة.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _oldController,
                        obscureText: _obscure,
                        decoration: _decoration('كلمة المرور الحالية (المؤقتة)', Icons.key_rounded),
                        validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newController,
                        obscureText: _obscure,
                        decoration: _decoration('كلمة المرور الجديدة', Icons.lock_rounded),
                        validator: _validateNew,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscure,
                        decoration: _decoration('تأكيد كلمة المرور الجديدة', Icons.lock_outline_rounded),
                        validator: (v) => v != _newController.text ? 'كلمتا المرور غير متطابقتين' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '8 خانات على الأقل، وتحتوي حرفاً ورقماً.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _submit,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_rounded),
                        label: const Text('حفظ ومتابعة'),
                      ),
                      TextButton(
                        onPressed: _isSaving ? null : () => AuthProvider.instance.logout(),
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
