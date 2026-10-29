import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';

/// Hint: نوافذ التأكيد الأمني المستخدمة في شاشة الإعدادات

// نافذة تأكيد الهوية بكلمة مرور السوبر أدمن قبل العمليات الحساسة
Future<bool?> showSensitiveActionPrompt(BuildContext context, String actionTitle) async {
  final passCtrl = TextEditingController();
  bool obscure = true;
  bool isVerifying = false;
  String? err;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDlgState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.security_rounded, color: AppColors.danger),
              SizedBox(width: 8),
              Text('تأكيد أمني مطلوب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'يتطلب تنفيذ ($actionTitle) إدخال كلمة مرور حساب السوبر أدمن لتأكيد العملية وحماية البيانات:',
                  style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'كلمة مرور السوبر أدمن',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setDlgState(() => obscure = !obscure),
                    ),
                    errorText: err,
                  ),
                  onSubmitted: (_) async {
                    final pwd = passCtrl.text;
                    if (pwd.isEmpty) {
                      setDlgState(() => err = 'يرجى إدخال كلمة المرور');
                      return;
                    }
                    setDlgState(() {
                      isVerifying = true;
                      err = null;
                    });
                    try {
                      await ApiClient.instance.post('/auth/verify-password', {'password': pwd});
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (!context.mounted) return;
                      setDlgState(() {
                        isVerifying = false;
                        err = 'كلمة المرور غير صحيحة، يرجى التأكد والمحاولة';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: isVerifying ? null : () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              icon: isVerifying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('تأكيد ومتابعة'),
              onPressed: isVerifying
                  ? null
                  : () async {
                      final pwd = passCtrl.text;
                      if (pwd.isEmpty) {
                        setDlgState(() => err = 'يرجى إدخال كلمة المرور');
                        return;
                      }
                      setDlgState(() {
                        isVerifying = true;
                        err = null;
                      });
                      try {
                        await ApiClient.instance.post('/auth/verify-password', {'password': pwd});
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (!context.mounted) return;
                        setDlgState(() {
                          isVerifying = false;
                          err = 'كلمة المرور غير صحيحة، يرجى التأكد والمحاولة';
                        });
                      }
                    },
            ),
          ],
        );
      },
    ),
  );
}

/// Hint: نافذة إدخال كلمة مرور الأدمن وإرجاعها كما هي (يتحقق منها الخادم ضمن نفس الطلب)
Future<String?> askAdminPassword(BuildContext context, String actionTitle) {
  final ctrl = TextEditingController();
  bool obscure = true;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDlgState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Expanded(
              child: Text('تأكيد أمني مطلوب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لتنفيذ ($actionTitle) أدخل كلمة مرور حسابك:', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'كلمة مرورك',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setDlgState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(context, v.isEmpty ? null : v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.isEmpty ? null : ctrl.text), child: const Text('تأكيد')),
        ],
      ),
    ),
  );
}
