import 'package:flutter/material.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../tools/date_formatter.dart';
import 'template_dialogs.dart';

/// Hint: نافذة تعيين وتخصيص جدول الدوام (لموظف واحد أو مجموعة موظفين، بقالب أو بأيام مخصصة)
/// الشاشة تمرر البيانات اللازمة وتستقبل النتيجة عبر الاستدعاءات onSubmitting / onSaved / onFailed
void showAssignScheduleDialog(
  BuildContext context, {
  required List<int> targetIds,
  String? singleEmployeeName,
  List<dynamic>? initialWorkDays,
  String? initialType,
  int? initialTemplateId,
  required List<dynamic> templates,
  required DateTime weekStartDate,
  required VoidCallback onSubmitting,
  required VoidCallback onSaved,
  required VoidCallback onFailed,
}) {
  int? selectedTemplateId = initialTemplateId ?? (templates.isNotEmpty ? templates.first['id'] : null);
  String scheduleType = initialType ?? 'WEEKLY'; // WEEKLY أو FIXED
  bool isCustom = initialTemplateId == null && initialWorkDays != null;
  final Set<int> customWorkDays = initialWorkDays != null
      ? initialWorkDays.map<int>((e) => (e as num).toInt()).toSet()
      : {0, 1, 2, 3, 4}; // افتراضي الأحد إلى الخميس

  final messenger = ScaffoldMessenger.of(context);

  showDialog(
    context: context,
    builder: (dlgCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) {
        final int workCount = isCustom ? customWorkDays.length : 0;
        final int offCount = 7 - workCount;

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: AppColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  singleEmployeeName != null
                      ? 'تخصيص جدول دوام: $singleEmployeeName'
                      : 'تعيين جدول دوام (${targetIds.length} موظف)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // نطاق التطبيق (أسبوعي أم ثابت دائم)
                  const Text('نطاق التطبيق والصلاحية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setDialogState(() => scheduleType = 'WEEKLY'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheduleType == 'WEEKLY' ? AppColors.navy.withValues(alpha: 0.08) : Colors.transparent,
                              border: Border.all(
                                color: scheduleType == 'WEEKLY' ? AppColors.navy : Colors.grey.shade300,
                                width: scheduleType == 'WEEKLY' ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  scheduleType == 'WEEKLY' ? Icons.radio_button_checked : Icons.radio_button_off,
                                  size: 18,
                                  color: scheduleType == 'WEEKLY' ? AppColors.navy : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('أسبوعي محدد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('أسبوع: ${DateFormatter.toYmd(weekStartDate)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setDialogState(() => scheduleType = 'FIXED'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheduleType == 'FIXED' ? AppColors.navy.withValues(alpha: 0.08) : Colors.transparent,
                              border: Border.all(
                                color: scheduleType == 'FIXED' ? AppColors.navy : Colors.grey.shade300,
                                width: scheduleType == 'FIXED' ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  scheduleType == 'FIXED' ? Icons.radio_button_checked : Icons.radio_button_off,
                                  size: 18,
                                  color: scheduleType == 'FIXED' ? AppColors.navy : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ثابت دائم', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('يطبق على كل الأسابيع', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // التبديل بين القالب الجاهز والتخصيص اليدوي الحر
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => setDialogState(() => isCustom = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !isCustom ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: !isCustom
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '📋 اختيار قالب جاهز',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: !isCustom ? FontWeight.bold : FontWeight.normal,
                                  color: !isCustom ? AppColors.navy : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => setDialogState(() => isCustom = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isCustom ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: isCustom
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '✏️ تخصيص يدوي حر للأيام',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                                  color: isCustom ? AppColors.navy : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!isCustom) ...[
                    // اختيار قالب جاهز
                    const Text('اختر قالب الدوام المطلوب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: selectedTemplateId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: templates.map((t) {
                        final workDays = (t['workDays'] as List<dynamic>?)?.length ?? 0;
                        return DropdownMenuItem<int>(
                          value: t['id'] as int,
                          child: Text('${t['name']} ($workDays أيام دوام)'),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedTemplateId = val),
                    ),
                  ] else ...[
                    // تخصيص يدوي حر للأيام
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('حدد أيام الدوام والراحة يدوياً:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.onTime.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('دوام: $workCount', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.onTime)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('راحة (أوف): $offCount', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'اضغط على أي يوم لتبديله بين (يوم دوام 🟢) أو (يوم راحة أوف ⚪):',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),

                    // أزرار الأيام السبعة التفاعلية
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int i = 0; i < 7; i++) ...[
                          Builder(
                            builder: (context) {
                              final isWork = customWorkDays.contains(i);
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setDialogState(() {
                                    if (isWork) {
                                      customWorkDays.remove(i);
                                    } else {
                                      customWorkDays.add(i);
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isWork ? AppColors.onTime : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isWork ? AppColors.onTime : Colors.grey.shade400,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isWork ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                        size: 14,
                                        color: isWork ? Colors.white : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        scheduleDayNames[i],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isWork ? Colors.white : Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isWork ? '(دوام)' : '(أوف)',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: isWork ? Colors.white70 : Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
              onPressed: (!isCustom && selectedTemplateId == null)
                  ? null
                  : () async {
                      Navigator.pop(dlgCtx);
                      onSubmitting();
                      try {
                        final Map<String, dynamic> body = {
                          'employeeIds': targetIds,
                          'scheduleType': scheduleType,
                          'weekStartDate': DateFormatter.toYmd(weekStartDate),
                        };

                        if (isCustom) {
                          body['workDays'] = customWorkDays.toList()..sort();
                          body['templateId'] = null;
                        } else {
                          body['templateId'] = selectedTemplateId;
                          body['workDays'] = null;
                        }

                        await ApiClient.instance.post('/schedules/assign', body);

                        messenger.showSnackBar(
                          const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حفظ وتعيين جدول الدوام بنجاح!')),
                        );
                        onSaved();
                      } catch (e) {
                        onFailed();
                        messenger.showSnackBar(
                          SnackBar(backgroundColor: AppColors.danger, content: Text('فشل التعيين: $e')),
                        );
                      }
                    },
              child: const Text('حفظ التعيين'),
            ),
          ],
        );
      },
    ),
  );
}
