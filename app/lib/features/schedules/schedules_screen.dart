import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../tools/date_formatter.dart';

/// Hint: شاشة جداول الدوام والشفتات وأيام الراحة الأسبوعية (النقطة 17)
/// تدعم قوالب الدوام، الجداول الأسبوعية والثابتة، ونسخ جدول الأسبوع السابق
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
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTemplates() async {
    final res = await ApiClient.instance.get('/schedules/templates');
    if (res is List) {
      _templates = res;
    }
  }

  Future<void> _loadDepartments() async {
    final res = await ApiClient.instance.get('/employees/departments');
    if (res is List) {
      _departments = res.where((d) => d['is_excluded'] == 0).toList();
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
      setState(() {
        _assignments = res['assignments'] ?? [];
        _selectedEmployeeIds.clear();
        _isLoading = false;
      });
    } catch (e) {
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
    final targetWeekStr = DateFormatter.toYmd(_weekStartDate);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.copy_all_rounded, color: AppColors.navy),
            SizedBox(width: 8),
            Text('نسخ جدول الأسبوع السابق'),
          ],
        ),
        content: Text('هل تود نسخ كافة تعيينات جداول الدوام من الأسبوع السابق إلى أسبوع [$targetWeekStr]؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.onTime,
          content: Text(res['message'] ?? 'تم نسخ جدول الأسبوع السابق بنجاح!'),
        ),
      );
      _loadAssignments();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل النسخ: $e')),
      );
    }
  }

  // تعيين جدول دوام للموظفين المحددين
  void _showAssignDialog() {
    if (_selectedEmployeeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد موظف واحد على الأقل أولاً')),
      );
      return;
    }

    int? selectedTemplateId = _templates.isNotEmpty ? _templates.first['id'] : null;
    String scheduleType = 'WEEKLY'; // أو FIXED

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('تعيين جدول دوام (${_selectedEmployeeIds.length} موظف)'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('نوع التطبيق:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('أسبوعي', style: TextStyle(fontSize: 13)),
                          subtitle: Text(DateFormatter.toYmd(_weekStartDate), style: const TextStyle(fontSize: 11)),
                          value: 'WEEKLY',
                          groupValue: scheduleType,
                          onChanged: (val) => setDialogState(() => scheduleType = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ثابت دائم', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('يطبق كل أسبوع', style: TextStyle(fontSize: 11)),
                          value: 'FIXED',
                          groupValue: scheduleType,
                          onChanged: (val) => setDialogState(() => scheduleType = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: selectedTemplateId == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);
                        try {
                          await ApiClient.instance.post('/schedules/assign', {
                            'employeeIds': _selectedEmployeeIds.toList(),
                            'scheduleType': scheduleType,
                            'templateId': selectedTemplateId,
                            'weekStartDate': DateFormatter.toYmd(_weekStartDate),
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم تعيين جدول الدوام بنجاح!')),
                          );
                          _loadAssignments();
                        } catch (e) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
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

  // نافذة إدارة قوالب الدوام (إضافة / تعديل)
  void _showTemplatesManagerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.dashboard_customize_rounded, color: AppColors.navy),
                SizedBox(width: 8),
                Text('إدارة قوالب الدوام والشفتات'),
              ],
            ),
            content: SizedBox(
              width: 550,
              height: 400,
              child: ListView.separated(
                itemCount: _templates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final t = _templates[index];
                  final List<dynamic> workDays = t['workDays'] ?? [];
                  const daysNames = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

                  return ListTile(
                    title: Text(t['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Wrap(
                      spacing: 4,
                      children: [
                        for (int i = 0; i < 7; i++)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(daysNames[i], style: TextStyle(fontSize: 10, color: workDays.contains(i) ? Colors.white : Colors.grey)),
                            backgroundColor: workDays.contains(i) ? AppColors.onTime : Colors.grey.shade200,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dayLabels = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

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
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: BorderSide(color: AppColors.navy.withOpacity(0.4)),
                      ),
                      icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
                      label: const Text('قوالب الدوام'),
                      onPressed: _showTemplatesManagerDialog,
                    ),
                    const SizedBox(width: 8),
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
                      onPressed: _showAssignDialog,
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
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
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
                                              dayLabels[i],
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
