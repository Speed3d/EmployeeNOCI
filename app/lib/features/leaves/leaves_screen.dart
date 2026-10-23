import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../tools/date_formatter.dart';

/// Hint: شاشة إدارة الإجازات والعطلات والمناسبات الرسمية (النقطة 9)
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
  List<dynamic> _departments = [];

  String? _selectedDept;
  String _leaveFilterMode = 'ACTIVE'; // ACTIVE (سارية وقادمة), EXPIRED (منتهية), ALL (الكل)

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
      String leavesUrl = '/leaves?';
      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        leavesUrl += 'department=${Uri.encodeComponent(_selectedDept!)}&';
      }

      final leavesRes = await ApiClient.instance.get(leavesUrl);
      final holidaysRes = await ApiClient.instance.get('/leaves/holidays');
      final empsRes = await ApiClient.instance.get('/employees?status=نشط&isExempt=0');
      final deptsRes = await ApiClient.instance.get('/employees/departments');

      setState(() {
        _leaves = leavesRes is List ? leavesRes : [];
        _holidays = holidaysRes is List ? holidaysRes : [];
        _employees = empsRes is List ? empsRes : [];
        _departments = deptsRes is List ? deptsRes.where((d) => d['is_excluded'] == 0).toList() : [];
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

    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
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
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('من: ${DateFormatter.toYmd(startDate)}', style: const TextStyle(fontSize: 12)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setModalState(() {
                                  startDate = d;
                                  if (endDate.isBefore(startDate)) endDate = startDate;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('إلى: ${DateFormatter.toYmd(endDate)}', style: const TextStyle(fontSize: 12)),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
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
                      decoration: const InputDecoration(
                        labelText: 'السبب / الملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: selectedEmpId == null
                    ? null
                    : () async {
                        try {
                          await ApiClient.instance.post('/leaves', {
                            'employeeId': selectedEmpId,
                            'leaveType': leaveType,
                            'startDate': DateFormatter.toYmd(startDate),
                            'endDate': DateFormatter.toYmd(endDate),
                            'reason': reasonController.text.trim(),
                          });
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          messenger.showSnackBar(const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم تسجيل الإجازة بنجاح')));
                          _loadData();
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(e.toString())));
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

    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            title: const Text('إضافة عطلة أو مناسبة رسمية'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المناسبة / العطلة الرسمية *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
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
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) return;
                  try {
                    await ApiClient.instance.post('/leaves/holidays', {
                      'date': DateFormatter.toYmd(holidayDate),
                      'title': titleController.text.trim(),
                    });
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم إضافة العطلة الرسمية بنجاح')));
                    _loadData();
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(e.toString())));
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
    final auth = AuthProvider.instance;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.navy,
            indicatorColor: AppColors.gold,
            tabs: const [
              Tab(icon: Icon(Icons.beach_access_rounded), text: 'الإجازات والأذونات'),
              Tab(icon: Icon(Icons.celebration_rounded), text: 'العطل والمناسبات الرسمية'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // شريط فلترة القسم للإجازات
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
                      _loadData();
                    },
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('تسجيل إجازة'),
                  onPressed: _showAddLeaveDialog,
                ),
                if (auth.isSuperAdmin) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('إضافة عطلة رسمية'),
                    onPressed: _showAddHolidayDialog,
                  ),
                ],
              ],
            ),
          ),

          // محتوى التبويبات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // تبويب 1: الإجازات
                      Builder(
                        builder: (context) {
                          final todayStr = DateFormatter.toYmd(DateTime.now());
                          final activeLeaves = _leaves.where((l) => (l['end_date'] ?? '').toString().compareTo(todayStr) >= 0).toList();
                          final expiredLeaves = _leaves.where((l) => (l['end_date'] ?? '').toString().compareTo(todayStr) < 0).toList();

                          final displayedLeaves = _leaveFilterMode == 'ACTIVE'
                              ? activeLeaves
                              : (_leaveFilterMode == 'EXPIRED' ? expiredLeaves : _leaves);

                          return Column(
                            children: [
                              // شريط فلترة الإجازات السارية مقابل المنتهية
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                color: Theme.of(context).cardTheme.color ?? Colors.white,
                                child: Row(
                                  children: [
                                    ChoiceChip(
                                      label: Text('الإجازات السارية (${activeLeaves.length})'),
                                      selected: _leaveFilterMode == 'ACTIVE',
                                      selectedColor: AppColors.onTime.withOpacity(0.15),
                                      labelStyle: TextStyle(
                                        color: _leaveFilterMode == 'ACTIVE' ? AppColors.onTime : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      onSelected: (_) => setState(() => _leaveFilterMode = 'ACTIVE'),
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: Text('أرشيف الإجازات المنتهية (${expiredLeaves.length})'),
                                      selected: _leaveFilterMode == 'EXPIRED',
                                      selectedColor: Colors.grey.shade300,
                                      labelStyle: TextStyle(
                                        color: _leaveFilterMode == 'EXPIRED' ? AppColors.navy : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      onSelected: (_) => setState(() => _leaveFilterMode = 'EXPIRED'),
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: Text('الكل (${_leaves.length})'),
                                      selected: _leaveFilterMode == 'ALL',
                                      labelStyle: const TextStyle(fontSize: 12),
                                      onSelected: (_) => setState(() => _leaveFilterMode = 'ALL'),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),

                              // قائمة الإجازات المعروضة
                              Expanded(
                                child: displayedLeaves.isEmpty
                                    ? Center(
                                        child: Text(
                                          _leaveFilterMode == 'ACTIVE'
                                              ? 'لا توجد إجازات سارية حالياً'
                                              : (_leaveFilterMode == 'EXPIRED' ? 'لا توجد إجازات منتهية في الأرشيف' : 'لا توجد إجازات مسجلة'),
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: displayedLeaves.length,
                                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                                        itemBuilder: (context, index) {
                                          final l = displayedLeaves[index];
                                          final isExpired = (l['end_date'] ?? '').toString().compareTo(todayStr) < 0;

                                          return Card(
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor: isExpired ? Colors.grey.shade300 : AppColors.info,
                                                child: Icon(
                                                  Icons.beach_access_rounded,
                                                  color: isExpired ? Colors.grey.shade700 : Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              title: Row(
                                                children: [
                                                  Text(
                                                    '[${l['emp_code']}] ${l['employee_name'] ?? ''}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isExpired ? Colors.grey.shade200 : AppColors.onTime.withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      isExpired ? 'منتهية' : 'سارية',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: isExpired ? Colors.grey.shade600 : AppColors.onTime,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Text(
                                                'نوع الإجازة: ${l['leave_type']} • من ${l['start_date']} إلى ${l['end_date']}' +
                                                    (l['reason'] != null && l['reason'].toString().isNotEmpty ? ' (${l['reason']})' : ''),
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                                tooltip: 'حذف الإجازة',
                                                onPressed: () async {
                                                  try {
                                                    await ApiClient.instance.delete('/leaves/${l['id']}');
                                                    _loadData();
                                                  } catch (e) {
                                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                                                  }
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          );
                        },
                      ),

                      // تبويب 2: العطلات الرسمية
                      _holidays.isEmpty
                          ? const Center(child: Text('لا توجد عطلات رسمية مسجلة'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _holidays.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final h = _holidays[index];
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.holiday,
                                      child: Icon(Icons.celebration_rounded, color: Colors.white, size: 20),
                                    ),
                                    title: Text(h['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text('تاريخ العطلة: ${h['date']}', style: const TextStyle(fontSize: 12)),
                                    trailing: auth.isSuperAdmin
                                        ? IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                            onPressed: () async {
                                              try {
                                                await ApiClient.instance.delete('/leaves/holidays/${h['id']}');
                                                _loadData();
                                              } catch (e) {
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                                              }
                                            },
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
