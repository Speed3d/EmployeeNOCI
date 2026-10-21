import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/custom_button.dart';
import '../../tools/date_formatter.dart';

/// Hint: شاشة إدارة الإجازات والعطلات والمناسبات الرسمية
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _leaves = [];
  List<dynamic> _holidays = [];
  List<dynamic> _employees = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final leavesRes = await ApiClient.instance.get('/leaves');
      final holidaysRes = await ApiClient.instance.get('/leaves/holidays');
      final empsRes = await ApiClient.instance.get('/employees');

      setState(() {
        _leaves = leavesRes is List ? leavesRes : [];
        _holidays = holidaysRes is List ? holidaysRes : [];
        _employees = empsRes is List ? empsRes : [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddLeaveDialog() {
    int? selectedEmpId = _employees.isNotEmpty ? _employees.first['id'] : null;
    String leaveType = 'اعتيادية';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('تسجيل إجازة لموظف'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedEmpId,
                      decoration: const InputDecoration(labelText: 'اختر الموظف *'),
                      items: _employees.map<DropdownMenuItem<int>>((e) {
                        return DropdownMenuItem<int>(
                          value: e['id'],
                          child: Text('[${e['emp_code']}] ${e['name']} (${e['department']})', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) => setModalState(() => selectedEmpId = val),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: leaveType,
                      decoration: const InputDecoration(labelText: 'نوع الإجازة *'),
                      items: const [
                        DropdownMenuItem(value: 'اعتيادية', child: Text('إجازة اعتيادية')),
                        DropdownMenuItem(value: 'مرضية', child: Text('إجازة مرضية')),
                        DropdownMenuItem(value: 'زمنية (ساعية)', child: Text('زمنية / إذن ساعي')),
                        DropdownMenuItem(value: 'إيفاد رسمي', child: Text('إيفاد رسمي / مهمة خارجية')),
                        DropdownMenuItem(value: 'طارئة', child: Text('إجازة طارئة')),
                      ],
                      onChanged: (val) => setModalState(() => leaveType = val ?? 'اعتيادية'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range_rounded, size: 16),
                            label: Text('من: ${DateFormatter.toYmd(startDate)}'),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) setModalState(() => startDate = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.date_range_rounded, size: 16),
                            label: Text('إلى: ${DateFormatter.toYmd(endDate)}'),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) setModalState(() => endDate = d);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(labelText: 'السبب / الملاحظات'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  if (selectedEmpId == null) return;
                  await ApiClient.instance.post('/leaves', {
                    'employeeId': selectedEmpId,
                    'leaveType': leaveType,
                    'startDate': DateFormatter.toYmd(startDate),
                    'endDate': DateFormatter.toYmd(endDate),
                    'reason': reasonController.text.trim(),
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadData();
                  }
                },
                child: const Text('تسجيل الإجازة'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddHolidayDialog() {
    DateTime holidayDate = DateTime.now();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('إضافة عطلة رسمية أو مناسبة'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text('تاريخ العطلة: ${DateFormatter.toYmd(holidayDate)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: holidayDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setModalState(() => holidayDate = d);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'اسم المناسبة أو العطلة * (مثال: عيد الأضحى)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  await ApiClient.instance.post('/leaves/holidays', {
                    'date': DateFormatter.toYmd(holidayDate),
                    'title': title,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadData();
                  }
                },
                child: const Text('إضافة العطلة'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.navy,
            indicatorColor: AppColors.goldBright,
            tabs: const [
              Tab(icon: Icon(Icons.beach_access_rounded), text: 'سجل إجازات الموظفين'),
              Tab(icon: Icon(Icons.celebration_rounded), text: 'العطل والمناسبات الرسمية'),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // تبويب الإجازات
                Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _showAddLeaveDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('تسجيل إجازة'),
                  ),
                  body: _leaves.isEmpty
                      ? const Center(child: Text('لا توجد إجازات مسجلة حالياً'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _leaves.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final l = _leaves[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.onLeave,
                                  child: Icon(Icons.beach_access_rounded, color: Colors.white, size: 20),
                                ),
                                title: Text(
                                  '[${l['emp_code']}] ${l['employee_name']} (${l['department']})',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'إجازة ${l['leave_type']} • من ${l['start_date']} إلى ${l['end_date']}${l['reason'] != null && l['reason'].toString().isNotEmpty ? ' • ${l['reason']}' : ''}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                  onPressed: () async {
                                    await ApiClient.instance.delete('/leaves/${l['id']}');
                                    _loadData();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // تبويب العطلات الرسمية
                Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: _showAddHolidayDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة عطلة رسمية'),
                  ),
                  body: _holidays.isEmpty
                      ? const Center(child: Text('لا توجد عطل رسمية مسجلة'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _holidays.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final h = _holidays[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.goldBright,
                                  child: Icon(Icons.celebration_rounded, color: AppColors.navyDeepDark, size: 20),
                                ),
                                title: Text(
                                  h['title'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'تاريخ العطلة: ${DateFormatter.toArabicDate(h['date'])} (${h['date']})',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                  onPressed: () async {
                                    await ApiClient.instance.delete('/leaves/holidays/${h['id']}');
                                    _loadData();
                                  },
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
