import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../shared/custom_button.dart';

/// Hint: شاشة تسجيل الدخول بتصميم ملكي وعصري يحاكي هوية المؤسسة
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController(text: ApiClient.instance.baseUrl);

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showServerConfig = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool('remember_me') ?? false;
      if (remember) {
        final savedUser = prefs.getString('saved_username') ?? '';
        final savedPass = prefs.getString('saved_password') ?? '';
        if (mounted) {
          setState(() {
            _rememberMe = true;
            _usernameController.text = savedUser;
            _passwordController.text = savedPass;
          });
        }
      }
    } catch (_) {}
  }

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

      // حفظ أو مسح بيانات الدخول وفق خيار تذكرني
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setBool('remember_me', true);
          await prefs.setString('saved_username', username);
          await prefs.setString('saved_password', password);
        } else {
          await prefs.remove('remember_me');
          await prefs.remove('saved_username');
          await prefs.remove('saved_password');
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    // تنبيه وضع الصيانة إن وجد
                    if (AuthProvider.instance.isMaintenance) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.construction_rounded, color: AppColors.danger, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'النظام في وضع الصيانة حالياً (الدخول متاح للسوبر أدمن فقط)',
                                style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // أيقونة وشعار النظام
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: AuthProvider.instance.fullLogoUrl != null
                          ? ClipOval(
                              child: Image.network(
                                AuthProvider.instance.fullLogoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.fingerprint_rounded,
                                  color: AppColors.goldBright,
                                  size: 42,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.fingerprint_rounded,
                              color: AppColors.goldBright,
                              size: 42,
                            ),
                    ),
                    const SizedBox(height: 18),

                    // اسم المؤسسة
                    Text(
                      AuthProvider.instance.institutionName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // عنوان البرنامج
                    Text(
                      AuthProvider.instance.appTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
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
                    const SizedBox(height: 12),

                    // خيار تذكر بيانات تسجيل الدخول
                    InkWell(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.navy,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) => setState(() => _rememberMe = val ?? false),
                            ),
                            const Text(
                              'تذكر بيانات تسجيل الدخول على هذا الجهاز',
                              style: TextStyle(fontSize: 13, color: AppColors.navyDeep),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

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
                              final messenger = ScaffoldMessenger.of(context);
                              await ApiClient.instance.setBaseUrl(_urlController.text.trim());
                              messenger.showSnackBar(
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
