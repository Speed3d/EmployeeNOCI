import 'package:flutter/material.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/api_client.dart';
import '../../shared/custom_button.dart';

/// Hint: شاشة تسجيل الدخول بتصميم ملكي وعصري يحاكي هوية المؤسسة
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'Admin@123456');
  final _urlController = TextEditingController(text: ApiClient.instance.baseUrl);

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showServerConfig = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال اسم المستخدم وكلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthProvider.instance.login(username, password);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // أيقونة وشعار النظام
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        color: AppColors.goldBright,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // اسم المؤسسة
                    Text(
                      AppConstants.institutionName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // عنوان البرنامج
                    const Text(
                      AppConstants.appTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // رسالة الخطأ إن وجدت
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: AppColors.danger, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // حقل اسم المستخدم
                    TextField(
                      controller: _usernameController,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // حقل كلمة المرور
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 24),

                    // زر تسجيل الدخول
                    CustomButton(
                      label: 'تسجيل الدخول',
                      icon: Icons.login_rounded,
                      width: double.infinity,
                      isLoading: _isLoading,
                      onPressed: _handleLogin,
                    ),
                    const SizedBox(height: 16),

                    // زر إعدادات الخادم للسوبر أدمن أو الشبكة
                    TextButton.icon(
                      icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                      label: Text(
                        _showServerConfig ? 'إخفاء إعدادات الخادم' : 'ضبط عنوان الخادم (API)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => setState(() => _showServerConfig = !_showServerConfig),
                    ),

                    if (_showServerConfig) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _urlController,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'عنوان الخادم (Base URL)',
                          prefixIcon: const Icon(Icons.link_rounded),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check_rounded, color: Colors.green),
                            onPressed: () async {
                              await ApiClient.instance.setBaseUrl(_urlController.text.trim());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تحديث عنوان الخادم')),
                              );
                            },
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
