import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Hint: نتيجة نافذة التصفير: وضع التصفير المختار وكلمة مرور التأكيد
typedef ResetChoice = ({String mode, String password});

/// Hint: نافذة تصفير النظام وإعادة الضبط بخياريها (factory_default و wipe_all)
Future<ResetChoice?> showResetDialog(BuildContext context) async {
  final passwordController = TextEditingController();
  String selectedResetMode = 'factory_default';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
            SizedBox(width: 8),
            Text('تصفير النظام وإعادة الضبط للبداية'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'تحذير صارم: سيتم أخذ نسخة احتياطية تلقائية للأمان قبل تنفيذ التصفير. يرجى تحديد نوع التصفير المطلوب بدقة:',
                    style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 14),
                // الخيار الأول: إعادة الضبط لنقطة البداية الأصلية
                InkWell(
                  onTap: () => setDialogState(() => selectedResetMode = 'factory_default'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedResetMode == 'factory_default' ? AppColors.navy.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedResetMode == 'factory_default' ? AppColors.navy : Colors.grey.shade300,
                        width: selectedResetMode == 'factory_default' ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selectedResetMode == 'factory_default' ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selectedResetMode == 'factory_default' ? AppColors.navy : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1. إعادة الضبط لنقطة البداية الأصلية (مع إعادة الموظفين للنسخة الأصلية)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'مسح كافة البصمات، الإجازات، العطل، الجداول، القوالب المضافة، التنقلات، المحادثات، المستخدمين الإضافيين، وسجل الحركات، مع إعادة إعدادات النظام وقائمة الموظفين والأقسام لنسخة الإكسل الأصلية.',
                                style: TextStyle(fontSize: 12, color: AppColors.vipExempt),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // الخيار الثاني: تصفير شامل بالكامل مع حذف الموظفين
                InkWell(
                  onTap: () => setDialogState(() => selectedResetMode = 'wipe_all'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedResetMode == 'wipe_all' ? AppColors.danger.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedResetMode == 'wipe_all' ? AppColors.danger : Colors.grey.shade300,
                        width: selectedResetMode == 'wipe_all' ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selectedResetMode == 'wipe_all' ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selectedResetMode == 'wipe_all' ? AppColors.danger : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '2. تصفير شامل بالكامل (مع حذف جميع الموظفين والأقسام)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.danger),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'حذف كل شيء في النظام بما في ذلك جميع أسماء الموظفين والأقسام والمستخدمين الإضافيين والقوالب والإعدادات والسجلات ليصبح النظام فارغاً تماماً (0 موظف).',
                                style: TextStyle(fontSize: 12, color: AppColors.vipExempt),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('للتأكيد، يرجى إدخال كلمة مرور السوبر أدمن:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_rounded)),
                ),
              ],
            ),
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
    ),
  );

  if (confirm != true || passwordController.text.isEmpty) return null;
  return (mode: selectedResetMode, password: passwordController.text);
}
