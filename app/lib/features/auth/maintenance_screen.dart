import 'package:flutter/material.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';

/// Hint: شاشة وضع الصيانة الحصرية (تظهر لمدخلي البيانات والمستخدمين العاديين عند تفعيل وضع الصيانة)
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _isChecking = false;

  Future<void> _checkStatus() async {
    setState(() => _isChecking = true);
    await AuthProvider.instance.checkSystemStatus();
    if (mounted) {
      setState(() => _isChecking = false);
      if (!AuthProvider.instance.isMaintenance) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.onTime,
            content: Text('انتهت أعمال الصيانة! يمكنك استخدام النظام الآن.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.late,
            content: Text('لا يزال النظام في وضع الصيانة والتحديث حالياً.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الشعار أو أيقونة الصيانة
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: auth.fullLogoUrl != null
                          ? ClipOval(
                              child: Image.network(
                                auth.fullLogoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.construction_rounded,
                                  color: AppColors.goldBright,
                                  size: 48,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.construction_rounded,
                              color: AppColors.goldBright,
                              size: 48,
                            ),
                    ),
                    const SizedBox(height: 20),

                    // اسم المؤسسة
                    Text(
                      auth.institutionName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // عنوان الصيانة
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'النظام قيد الصيانة والتحديث',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // النص التوضيحي
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                      ),
                      child: const Text(
                        'عذراً، يجري العمل حالياً على صيانة وتحديث قواعد البيانات والنظام من قبل الإدارة العامة (السوبر أدمن).\n\nتم إيقاف دخول واستخدام مدخلي البيانات مؤقتاً لضمان سلامة البيانات، يرجى المحاولة لاحقاً بعد انتهاء الصيانة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // أزرار العمليات
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _isChecking
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('إعادة التحقق من الحالة'),
                            onPressed: _isChecking ? null : _checkStatus,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('تسجيل الخروج'),
                          onPressed: () => AuthProvider.instance.logout(),
                        ),
                      ],
                    ),
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
