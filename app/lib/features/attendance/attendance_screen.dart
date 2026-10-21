import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/status_badge.dart';
import '../../tools/responsive.dart';
import '../../tools/date_formatter.dart';
import 'upload_dialog.dart';

/// Hint: شاشة كشف البصمة اليومي والتحليل والتشخيص اللوني الذكي
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime(2026, 10, 20); // تاريخ العينة الافتراضي
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic>? _stats;
  List<dynamic> _records = [];
  List<String> _departments = [];

  String _searchQuery = '';
  String? _selectedDept;
  String? _selectedStatus;
  final Set<String> _excludedDepts = {};

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadDailyAttendance();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get('/employees/departments');
      if (res is List) {
        setState(() {
          _departments = res.map((d) => d['name'].toString()).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDailyAttendance() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateStr = DateFormatter.toYmd(_selectedDate);
      String url = '/attendance/daily?date=$dateStr';

      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        url += '&department=${Uri.encodeComponent(_selectedDept!)}';
      }
      if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
        url += '&status=$_selectedStatus';
      }
      if (_searchQuery.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(_searchQuery)}';
      }
      if (_excludedDepts.isNotEmpty) {
        url += '&excludeDepts=${_excludedDepts.map((d) => Uri.encodeComponent(d)).join(',')}';
      }

      final res = await ApiClient.instance.get(url);
      setState(() {
        _stats = res['stats'];
        _records = res['records'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadDailyAttendance();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadDailyAttendance();
    }
  }

  Future<void> _exportExcel() async {
    final dateStr = DateFormatter.toYmd(_selectedDate);
    final url = '${ApiClient.instance.baseUrl}/reports/export-daily-excel?date=$dateStr';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط التصدير')),
      );
    }
  }

  void _showExcludeDeptsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('استثناء أقسام معينة من الكشف والغياب'),
              content: SizedBox(
                width: 400,
                height: 350,
                child: ListView.builder(
                  itemCount: _departments.length,
                  itemBuilder: (context, index) {
                    final dept = _departments[index];
                    final isExcluded = _excludedDepts.contains(dept);

                    return CheckboxListTile(
                      title: Text(dept, style: const TextStyle(fontSize: 13)),
                      value: isExcluded,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            _excludedDepts.add(dept);
                          } else {
                            _excludedDepts.remove(dept);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _excludedDepts.clear();
                    Navigator.pop(ctx);
                    _loadDailyAttendance();
                  },
                  child: const Text('إلغاء الاستثناءات'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _loadDailyAttendance();
                  },
                  child: const Text('تطبيق الفلتر'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      body: Column(
        children: [
          // 1. شريط التاريخ والعمليات الأساسية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // أدوات اختيار التاريخ
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'اليوم السابق',
                      onPressed: () => _changeDate(-1),
                    ),
                    InkWell(
                      onTap: _selectDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded, size: 20, color: AppColors.navy),
                            const SizedBox(width: 8),
                            Text(
                              DateFormatter.toArabicDate(DateFormatter.toYmd(_selectedDate)),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'اليوم التالي',
                      onPressed: () => _changeDate(1),
                    ),
                  ],
                ),

                // أزرار العمليات (رفع كشف، استثناء أقسام، تصدير)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.filter_list_off_rounded, size: 16),
                      label: Text(
                        _excludedDepts.isEmpty ? 'استثناء أقسام' : 'استثناء (${_excludedDepts.length})',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _showExcludeDeptsDialog,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.table_view_rounded, size: 16, color: Colors.green),
                      label: const Text('تصدير إكسل', style: TextStyle(fontSize: 12)),
                      onPressed: _exportExcel,
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.action(context),
                        foregroundColor: AppColors.onAction(context),
                      ),
                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                      label: const Text('رفع كشف البصمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => UploadAttendanceDialog(
                            onUploaded: _loadDailyAttendance,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. شريط ملخص الإحصائيات السريعة لليوم
          if (_stats != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: AppColors.navy.withOpacity(0.04),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatPill('إجمالي:', '${_stats!['total']}', Colors.black87),
                    const SizedBox(width: 12),
                    _buildStatPill('حضور:', '${_stats!['present']}', AppColors.onTime),
                    const SizedBox(width: 12),
                    _buildStatPill('في الوقت:', '${_stats!['onTime']}', AppColors.onTime),
                    const SizedBox(width: 12),
                    _buildStatPill('متأخرون:', '${_stats!['late'] + _stats!['veryLate']}', AppColors.late),
                    const SizedBox(width: 12),
                    _buildStatPill('غياب تام:', '${_stats!['absent']}', AppColors.absent),
                    const SizedBox(width: 12),
                    _buildStatPill('إجازات:', '${_stats!['onLeave']}', AppColors.onLeave),
                    const SizedBox(width: 12),
                    _buildStatPill('VIP:', '${_stats!['vipExempt']}', AppColors.vipExempt),
                  ],
                ),
              ),
            ),

          // 3. شريط الفلاتر والبحث
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث باسم الموظف أو المعرف...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      _searchQuery = val.trim();
                      _loadDailyAttendance();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (isDesktop) ...[
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDept,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: 'القسم',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كافة الأقسام')),
                        ..._departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedDept = val);
                        _loadDailyAttendance();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: 'الحالة',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('كافة الحالات')),
                        DropdownMenuItem(value: 'ON_TIME', child: Text('في الوقت')),
                        DropdownMenuItem(value: 'LATE', child: Text('تأخير بسيط')),
                        DropdownMenuItem(value: 'VERY_LATE', child: Text('تأخير كبير')),
                        DropdownMenuItem(value: 'ABSENT', child: Text('غائب')),
                        DropdownMenuItem(value: 'ON_LEAVE', child: Text('مجاز')),
                        DropdownMenuItem(value: 'VIP_EXEMPT', child: Text('مستثنى VIP')),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedStatus = val);
                        _loadDailyAttendance();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 4. جدول السجلات (Desktop) أو كروت تفاعلية (Mobile)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(child: Text('لا توجد سجلات تطابق البحث في هذا اليوم'))
                    : isDesktop
                        ? _buildDesktopTable()
                        : _buildMobileCardsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDesktopTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(AppColors.navy.withOpacity(0.06)),
            columns: const [
              DataColumn(label: Text('المعرف', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الاسم', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('القسم', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('وقت الحضور (الدخول)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('وقت الانصراف (الخروج)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('التأخير / الإضافي', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('الملاحظات والتشخيص', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _records.map((r) {
              final status = r['status'] ?? 'ABSENT';
              final firstPunch = r['first_punch'];
              final lastPunch = r['last_punch'];
              final lateMin = r['late_minutes'] ?? 0;
              final overtimeMin = r['overtime_minutes'] ?? 0;
              final bonusEarlyMin = r['early_bonus_minutes'] ?? 0;

              // تلوين خلية الدخول بدقة
              Color entryBg = Colors.transparent;
              if (status == 'LATE') {
                entryBg = AppColors.late.withOpacity(0.15); // أصفر
              } else if (status == 'VERY_LATE') {
                entryBg = AppColors.veryLate.withOpacity(0.18); // برتقالي
              } else if (status == 'ON_TIME') {
                entryBg = AppColors.onTime.withOpacity(0.1); // أخضر
              } else if (status == 'ABSENT') {
                entryBg = AppColors.absent.withOpacity(0.1); // أحمر
              }

              return DataRow(
                cells: [
                  DataCell(Text('${r['emp_code']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(r['department'] ?? '')),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: entryBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        DateFormatter.formatTime12h(firstPunch),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status == 'ABSENT' ? AppColors.absent : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(DateFormatter.formatTime12h(lastPunch))),
                  DataCell(StatusBadge(status: status)),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lateMin > 0)
                          Text('تأخير: $lateMin د', style: const TextStyle(color: AppColors.late, fontSize: 11, fontWeight: FontWeight.bold)),
                        if (overtimeMin > 0)
                          Text('إضافي: +$overtimeMin د', style: const TextStyle(color: AppColors.onTime, fontSize: 11, fontWeight: FontWeight.bold)),
                        if (bonusEarlyMin > 0)
                          Text('مبكر: +$bonusEarlyMin د ⭐', style: const TextStyle(color: AppColors.goldDark, fontSize: 11, fontWeight: FontWeight.bold)),
                        if (lateMin == 0 && overtimeMin == 0 && bonusEarlyMin == 0)
                          const Text('-', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: Text(
                        r['notes'] ?? '',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCardsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final r = _records[index];
        final status = r['status'] ?? 'ABSENT';
        final lateMin = r['late_minutes'] ?? 0;
        final overtimeMin = r['overtime_minutes'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.navy.withOpacity(0.1),
                      child: Text(
                        '${r['emp_code']}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(r['department'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    StatusBadge(status: status),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الدخول: ${DateFormatter.formatTime12h(r['first_punch'])}', style: const TextStyle(fontSize: 12)),
                    Text('الخروج: ${DateFormatter.formatTime12h(r['last_punch'])}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                if (lateMin > 0 || overtimeMin > 0 || (r['notes'] != null && r['notes'].toString().isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Text(
                    r['notes'] ?? '',
                    style: TextStyle(fontSize: 11, color: lateMin > 0 ? AppColors.late : Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
