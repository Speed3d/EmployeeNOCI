import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';

/// Hint: أسماء أيام الأسبوع بترتيب الخادم (0 = الأحد ... 6 = السبت)
const List<String> scheduleDayNames = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/// Hint: نوافذ إنشاء وتعديل وحذف قوالب الدوام

// نافذة إنشاء أو تعديل قالب دوام
void showTemplateEditorDialog(BuildContext context, {Map<String, dynamic>? template, required VoidCallback onSaved}) {
  final bool isEdit = template != null;
  final nameController = TextEditingController(text: isEdit ? template['name'] : '');
  final Set<int> workDays = isEdit && template['workDays'] != null
      ? (template['workDays'] as List<dynamic>).map<int>((e) => (e as num).toInt()).toSet()
      : {0, 1, 2, 3, 4}; // افتراضي 5 أيام

  final messenger = ScaffoldMessenger.of(context);

  showDialog(
    context: context,
    builder: (dlgCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) {
        return AlertDialog(
          title: Text(isEdit ? 'تعديل قالب الدوام' : 'إضافة قالب دوام جديد'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم القالب *',
                    hintText: 'مثال: شفت حراسة ليلي 4 أيام...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('أيام الدوام في هذا القالب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (int i = 0; i < 7; i++) ...[
                      Builder(
                        builder: (context) {
                          final isSelected = workDays.contains(i);
                          return FilterChip(
                            label: Text(scheduleDayNames[i]),
                            selected: isSelected,
                            selectedColor: AppColors.onTime,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                            onSelected: (val) {
                              setDialogState(() {
                                if (val) {
                                  workDays.add(i);
                                } else {
                                  workDays.remove(i);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'أيام الدوام المحددة: ${workDays.length} | أيام الراحة: ${7 - workDays.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('يرجى إدخال اسم القالب')));
                  return;
                }

                Navigator.pop(dlgCtx);
                try {
                  if (isEdit) {
                    await ApiClient.instance.put('/schedules/templates/${template['id']}', {
                      'name': name,
                      'workDays': workDays.toList()..sort(),
                    });
                  } else {
                    await ApiClient.instance.post('/schedules/templates', {
                      'name': name,
                      'workDays': workDays.toList()..sort(),
                    });
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.onTime,
                      content: Text(isEdit ? 'تم تعديل القالب بنجاح!' : 'تم إنشاء قالب الدوام بنجاح!'),
                    ),
                  );
                  onSaved();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(backgroundColor: AppColors.danger, content: Text('خطأ: $e')),
                  );
                }
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة القالب'),
            ),
          ],
        );
      },
    ),
  );
}

// حذف قالب
Future<void> deleteTemplateWithConfirm(BuildContext context, int id, String name, {required VoidCallback onDeleted}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('هل أنت متأكد من حذف قالب الدوام [$name]؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(dlgCtx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  try {
    await ApiClient.instance.delete('/schedules/templates/$id');
    messenger.showSnackBar(const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حذف القالب بنجاح')));
    onDeleted();
  } catch (e) {
    messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل الحذف: $e')));
  }
}
