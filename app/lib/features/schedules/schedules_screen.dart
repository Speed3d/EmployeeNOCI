import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../tools/date_formatter.dart';
import 'widgets/template_dialogs.dart';
import 'widgets/assign_schedule_dialog.dart';

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

  static const List<String> _dayNames = scheduleDayNames;

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
      if (!mounted) return;
      setState(() {
        _templates = res;
      });
    }
  }

  Future<void> _loadDepartments() async {
    final res = await ApiClient.instance.get('/employees/departments');
    if (res is List) {
      if (!mounted) return;
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
    if (!mounted) return;
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

    if (!mounted) return;
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

    showAssignScheduleDialog(
      context,
      targetIds: targetIds,
      singleEmployeeName: singleEmployeeName,
      initialWorkDays: initialWorkDays,
      initialType: initialType,
      initialTemplateId: initialTemplateId,
      templates: _templates,
      weekStartDate: _weekStartDate,
      onSubmitting: () => setState(() => _isLoading = true),
      onSaved: _loadAssignments,
      onFailed: () {
        if (mounted) setState(() => _isLoading = false);
      },
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
                  onPressed: () => showTemplateEditorDialog(context, 
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
                                  color: AppColors.navy.withValues(alpha: 0.08),
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
                                onPressed: () => showTemplateEditorDialog(context, 
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
                                onPressed: () => deleteTemplateWithConfirm(context, 
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
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
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
                        border: Border.all(color: AppColors.navy.withValues(alpha: 0.3)),
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
                          side: BorderSide(color: AppColors.navy.withValues(alpha: 0.4)),
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
                        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.4)),
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
            color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.5) ?? Colors.grey.shade50,
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  height: 38,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDept,
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
                      if (!mounted) return;
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
                    if (!mounted) return;
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
                                color: isSelected ? AppColors.navy.withValues(alpha: 0.04) : Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      if (!mounted) return;
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
                                          color: a['activeType'] == 'WEEKLY' ? AppColors.goldBright.withValues(alpha: 0.2) : Colors.grey.shade200,
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
                                                  ? AppColors.onTime.withValues(alpha: 0.12)
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
