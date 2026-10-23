import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../tools/date_formatter.dart';

/// Hint: شاشة جداول الدوام والشفتات وأيام الراحة الأسبوعية (النقطة 17)
/// تدعم قوالب الدوام، التخصيص اليدوي الحر للأيام، الجداول الأسبوعية والثابتة، ونسخ الأسبوع السابق
class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  DateTime _weekStartDate = _getSunday(DateTime.now());
  bool _isLoading = true;
  String? _error;

  List<dynamic> _assignments = [];
  List<dynamic> _templates = [];
  List<dynamic> _departments = [];

  String? _selectedDept;
  final Set<int> _selectedEmployeeIds = {};

  static const List<String> _dayNames = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  static DateTime _getSunday(DateTime d) {
    return d.subtract(Duration(days: d.weekday % 7));
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadTemplates(),
        _loadDepartments(),
      ]);
      await _loadAssignments();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTemplates() async {
    final res = await ApiClient.instance.get('/schedules/templates');
    if (res is List) {
      setState(() {
        _templates = res;
      });
    }
  }

  Future<void> _loadDepartments() async {
    final res = await ApiClient.instance.get('/employees/departments');
    if (res is List) {
      setState(() {
        _departments = res.where((d) => d['is_excluded'] == 0).toList();
      });
    }
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final weekStr = DateFormatter.toYmd(_weekStartDate);
      String url = '/schedules/assignments?weekStartDate=$weekStr';
      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        url += '&department=${Uri.encodeComponent(_selectedDept!)}';
      }

      final res = await ApiClient.instance.get(url);
      if (!mounted) return;
      setState(() {
        _assignments = res['assignments'] ?? [];
        _selectedEmployeeIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _changeWeek(int deltaWeeks) {
    setState(() {
      _weekStartDate = _weekStartDate.add(Duration(days: deltaWeeks * 7));
    });
    _loadAssignments();
  }

  // نسخ جدول الأسبوع السابق
  Future<void> _copyPreviousWeek() async {
    final messenger = ScaffoldMessenger.of(context);
    final targetWeekStr = DateFormatter.toYmd(_weekStartDate);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.copy_all_rounded, color: AppColors.navy),
            SizedBox(width: 8),
            Text('نسخ جدول الأسبوع السابق'),
          ],
        ),
        content: Text('هل تود نسخ كافة تعيينات جداول الدوام من الأسبوع السابق إلى أسبوع [$targetWeekStr]؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('تأكيد النسخ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.post('/schedules/copy-previous-week', {
        'targetWeekStartDate': targetWeekStr,
      });

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text(res['message'] ?? 'تم نسخ جدول الأسبوع السابق بنجاح!'),
        ),
      );
      _loadAssignments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل النسخ: $e')),
      );
    }
  }

  // تعيين وتخصيص جدول الدوام (لموظف واحد أو مجموعة موظفين، مع دعم القوالب والتخصيص اليدوي الحر)
  void _showAssignDialog({
    int? singleEmployeeId,
    String? singleEmployeeName,
    List<dynamic>? initialWorkDays,
    String? initialType,
    int? initialTemplateId,
  }) {
    final List<int> targetIds = singleEmployeeId != null ? [singleEmployeeId] : _selectedEmployeeIds.toList();

    if (targetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد موظف واحد على الأقل أولاً')),
      );
      return;
    }

    int? selectedTemplateId = initialTemplateId ?? (_templates.isNotEmpty ? _templates.first['id'] : null);
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
                                color: scheduleType == 'WEEKLY' ? AppColors.navy.withOpacity(0.08) : Colors.transparent,
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
                                      Text('أسبوع: ${DateFormatter.toYmd(_weekStartDate)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                                color: scheduleType == 'FIXED' ? AppColors.navy.withOpacity(0.08) : Colors.transparent,
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
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))]
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
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))]
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
                        value: selectedTemplateId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: _templates.map((t) {
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
                                  color: AppColors.onTime.withOpacity(0.12),
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
                                          _dayNames[i],
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
                        setState(() => _isLoading = true);
                        try {
                          final Map<String, dynamic> body = {
                            'employeeIds': targetIds,
                            'scheduleType': scheduleType,
                            'weekStartDate': DateFormatter.toYmd(_weekStartDate),
                          };

                          if (isCustom) {
                            body['workDays'] = customWorkDays.toList()..sort();
                            body['templateId'] = null;
                          } else {
                            body['templateId'] = selectedTemplateId;
                            body['workDays'] = null;
                          }

                          await ApiClient.instance.post('/schedules/assign', body);

                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حفظ وتعيين جدول الدوام بنجاح!')),
                          );
                          _loadAssignments();
                        } catch (e) {
                          if (!mounted) return;
                          setState(() => _isLoading = false);
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

  // نافذة إدارة قوالب الدوام (عرض، إضافة جديدة، تعديل، حذف)
  void _showTemplatesManagerDialog() {
    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.dashboard_customize_rounded, color: AppColors.navy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('إدارة قوالب الدوام والشفتات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.onTime, foregroundColor: Colors.white),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة قالب جديد'),
                  onPressed: () => _showTemplateEditorDialog(
                    onSaved: () async {
                      await _loadTemplates();
                      setDialogState(() {});
                    },
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 440,
              child: _templates.isEmpty
                  ? const Center(child: Text('لا توجد قوالب مسجلة حالياً'))
                  : ListView.separated(
                      itemCount: _templates.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final t = _templates[index];
                        final List<dynamic> workDays = t['workDays'] ?? [];

                        return ListTile(
                          title: Row(
                            children: [
                              Text(t['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.navy.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${workDays.length} أيام دوام', style: const TextStyle(fontSize: 10, color: AppColors.navy)),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 4,
                              children: [
                                for (int i = 0; i < 7; i++)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      _dayNames[i],
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: workDays.contains(i) ? Colors.white : Colors.grey.shade600,
                                      ),
                                    ),
                                    backgroundColor: workDays.contains(i) ? AppColors.onTime : Colors.grey.shade200,
                                  ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.navy),
                                tooltip: 'تعديل القالب',
                                onPressed: () => _showTemplateEditorDialog(
                                  template: t,
                                  onSaved: () async {
                                    await _loadTemplates();
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                tooltip: 'حذف القالب',
                                onPressed: () => _deleteTemplate(
                                  t['id'],
                                  t['name'],
                                  onDeleted: () async {
                                    await _loadTemplates();
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
  }

  // نافذة إنشاء أو تعديل قالب دوام
  void _showTemplateEditorDialog({Map<String, dynamic>? template, required VoidCallback onSaved}) {
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
                              label: Text(_dayNames[i]),
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

                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.onTime,
                        content: Text(isEdit ? 'تم تعديل القالب بنجاح!' : 'تم إنشاء قالب الدوام بنجاح!'),
                      ),
                    );
                    onSaved();
                  } catch (e) {
                    if (!mounted) return;
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
  Future<void> _deleteTemplate(int id, String name, {required VoidCallback onDeleted}) async {
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
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم حذف القالب بنجاح')));
      onDeleted();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text('فشل الحذف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // الشريط العلوي للأدوات والأسابيع
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ?? Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15))),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // محدد الأسبوع
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'الأسبوع السابق',
                      onPressed: () => _changeWeek(-1),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.navy.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.date_range_rounded, size: 16, color: AppColors.navy),
                          const SizedBox(width: 8),
                          Text(
                            'أسبوع: ${DateFormatter.toYmd(_weekStartDate)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'الأسبوع التالي',
                      onPressed: () => _changeWeek(1),
                    ),
                  ],
                ),

                // أزرار العمليات
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (AuthProvider.instance.isSuperAdmin) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: BorderSide(color: AppColors.navy.withOpacity(0.4)),
                        ),
                        icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
                        label: const Text('إدارة قوالب الدوام'),
                        onPressed: _showTemplatesManagerDialog,
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: BorderSide(color: AppColors.navy.withOpacity(0.4)),
                      ),
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: const Text('نسخ الأسبوع السابق'),
                      onPressed: _copyPreviousWeek,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.onTime,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
                      label: Text('تعيين جدول (${_selectedEmployeeIds.length})'),
                      onPressed: () => _showAssignDialog(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // شريط الفلترة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).cardTheme.color?.withOpacity(0.5) ?? Colors.grey.shade50,
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    value: _selectedDept,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    hint: const Text('كافة الأقسام', style: TextStyle(fontSize: 12)),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كافة الأقسام', style: TextStyle(fontSize: 12))),
                      ..._departments.map((d) => DropdownMenuItem(
                            value: d['name'].toString(),
                            child: Text(d['name'].toString(), style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedDept = val);
                      _loadAssignments();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  icon: Icon(
                    _selectedEmployeeIds.length == _assignments.length ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    size: 18,
                  ),
                  label: const Text('تحديد الكل'),
                  onPressed: () {
                    setState(() {
                      if (_selectedEmployeeIds.length == _assignments.length) {
                        _selectedEmployeeIds.clear();
                      } else {
                        _selectedEmployeeIds.addAll(_assignments.map<int>((a) => a['employeeId'] as int));
                      }
                    });
                  },
                ),
                const Spacer(),
                Text(
                  'إجمالي الموظفين: ${_assignments.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navy),
                ),
              ],
            ),
          ),

          // جدول شبكة الدوام الأسبوعية
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : _assignments.isEmpty
                        ? const Center(child: Text('لا توجد بيانات دوام مسجلة'))
                        : ListView.separated(
                            itemCount: _assignments.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final a = _assignments[index];
                              final empId = a['employeeId'] as int;
                              final isSelected = _selectedEmployeeIds.contains(empId);
                              final List<dynamic> workDays = a['workDays'] ?? [];
                              final List<dynamic> offDays = a['offDays'] ?? [];

                              return Container(
                                color: isSelected ? AppColors.navy.withOpacity(0.04) : Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedEmployeeIds.add(empId);
                                        } else {
                                          _selectedEmployeeIds.remove(empId);
                                        }
                                      });
                                    },
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        '[${a['empCode']}] ${a['name']}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('(${a['department']})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: a['activeType'] == 'WEEKLY' ? AppColors.goldBright.withOpacity(0.2) : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          a['templateName'] ?? 'افتراضي',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: a['activeType'] == 'WEEKLY' ? AppColors.navyDeep : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // زر تخصيص سريع ومباشر لهذا الموظف
                                      IconButton(
                                        icon: const Icon(Icons.edit_calendar_rounded, size: 18, color: AppColors.navy),
                                        tooltip: 'تخصيص جدول هذا الموظف مباشرة',
                                        onPressed: () => _showAssignDialog(
                                          singleEmployeeId: empId,
                                          singleEmployeeName: a['name'],
                                          initialWorkDays: workDays,
                                          initialType: a['activeType'],
                                          initialTemplateId: a['templateId'],
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        // أيام الأسبوع السبعة
                                        for (int i = 0; i < 7; i++) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            margin: const EdgeInsets.only(left: 4),
                                            decoration: BoxDecoration(
                                              color: workDays.contains(i)
                                                  ? AppColors.onTime.withOpacity(0.12)
                                                  : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: workDays.contains(i) ? AppColors.onTime : Colors.grey.shade400,
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              _dayNames[i],
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: workDays.contains(i) ? AppColors.onTime : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        Text(
                                          'أيام الراحة: ${offDays.length}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: offDays.isEmpty ? AppColors.late : AppColors.navy,
                                          ),
                                        ),
                                      ],
                                    ),
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
