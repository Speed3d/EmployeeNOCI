import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Hint: شاشة التقارير الشهرية والتراكمية (النقطة 10)
/// تتطلب الضغط على [بحث وتحليل التقرير] قبل التحميل، وتعتمد حصرياً على الأيام المعتمدة
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String? _selectedDept;
  List<dynamic> _departments = [];

  bool _hasSearched = false;
  bool _isLoading = false;
  String? _error;
  List<dynamic> _reportData = [];
  int _committedDaysCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ApiClient.instance.get('/employees/departments');
      if (res is List) {
        setState(() {
          _departments = res.where((d) => d['is_excluded'] == 0).toList();
        });
      }
    } catch (_) {}
  }

  // النقطة 10: البحث والتحليل يتم حصراً بعد ضغط الزر
  Future<void> _executeSearch() async {
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      String url = '/reports/monthly?year=$_selectedYear&month=$_selectedMonth';
      if (_selectedDept != null && _selectedDept!.isNotEmpty) {
        url += '&department=${Uri.encodeComponent(_selectedDept!)}';
      }

      final res = await ApiClient.instance.get(url);
      setState(() {
        _reportData = res['report'] ?? [];
        _committedDaysCount = res['committedDaysCount'] ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // تصدير التقرير الشهري الحالي كملف إكسل
  Future<void> _exportMonthlyExcel() async {
    if (_reportData.isEmpty) return;

    try {
      final headers = [
        'المعرف',
        'الاسم',
        'القسم',
        'أيام الحضور',
        'أيام الالتزام (في الوقت)',
        'أيام التأخير',
        'أيام الغياب',
        'أيام الإجازة',
        'أيام الراحة',
        'أيام العطل الرسمية',
        'إجمالي دقائق التأخير',
        'إجمالي دقائق الانصراف المبكر',
        'إجمالي مكافأة الحضور المبكر (د)',
        'إجمالي الدوام الإضافي (د)',
      ];

      final rows = _reportData.map((r) => [
        r['emp_code'],
        r['name'],
        r['department'],
        r['days_present'],
        r['days_on_time'],
        r['days_late'],
        r['days_absent'],
        r['days_on_leave'],
        r['days_off'],
        r['days_holiday'],
        r['total_late_minutes'],
        r['total_early_leave_minutes'],
        r['total_early_bonus_minutes'],
        r['total_overtime_minutes'],
      ]).toList();

      final fileName = 'تقرير_شهري_${_selectedYear}_$_selectedMonth';
      final title = 'تقرير شهر $_selectedMonth لسنة $_selectedYear';

      // استدعاء نقطة التصدير العامة
      await ApiClient.instance.post('/reports/export-excel', {
        'title': title,
        'fileName': fileName,
        'headers': headers,
        'rows': rows,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.onTime, content: Text('تم تصدير التقرير بنجاح!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text('فشل التصدير: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // شريط تحديد المعايير وأزرار التحليل
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
              children: [
                // السنة
                SizedBox(
                  width: 130,
                  height: 40,
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 2025, child: Text('سنة 2025')),
                      DropdownMenuItem(value: 2026, child: Text('سنة 2026')),
                      DropdownMenuItem(value: 2027, child: Text('سنة 2027')),
                    ],
                    onChanged: (y) => setState(() => _selectedYear = y ?? _selectedYear),
                  ),
                ),

                // الشهر
                SizedBox(
                  width: 140,
                  height: 40,
                  child: DropdownButtonFormField<int>(
                    value: _selectedMonth,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: List.generate(12, (i) {
                      final m = i + 1;
                      return DropdownMenuItem(value: m, child: Text('شهر $m'));
                    }),
                    onChanged: (m) => setState(() => _selectedMonth = m ?? _selectedMonth),
                  ),
                ),

                // القسم
                SizedBox(
                  width: 200,
                  height: 40,
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
                    onChanged: (val) => setState(() => _selectedDept = val),
                  ),
                ),

                // زر البحث والتحليل الإلزامي
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  icon: const Icon(Icons.analytics_rounded, size: 18),
                  label: const Text('بحث وتحليل التقرير', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _executeSearch,
                ),

                if (_hasSearched && _reportData.isNotEmpty) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.onTime,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('تصدير إكسل'),
                    onPressed: _exportMonthlyExcel,
                  ),
                ],
              ],
            ),
          ),

          // شريط معلومات الأيام المعتمدة
          if (_hasSearched && !_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: AppColors.navy.withOpacity(0.06),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    'التقرير التراكمي لشهر $_selectedMonth لسنة $_selectedYear — تم احتساب ($_committedDaysCount يوماً معتمداً فقط في هذا الشهر)',
                    style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),

          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : !_hasSearched
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_rounded, size: 64, color: AppColors.navy.withOpacity(0.4)),
                                const SizedBox(height: 16),
                                const Text(
                                  'يرجى تحديد السنة والشهر والقسم المطلوب ثم النقر على [بحث وتحليل التقرير]',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : _reportData.isEmpty
                            ? const Center(child: Text('لا توجد بيانات حضور مسجلة وموثقة في هذا الشهر'))
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: MaterialStateProperty.all(AppColors.navy.withOpacity(0.08)),
                                    columns: const [
                                      DataColumn(label: Text('المعرف', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الاسم', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('القسم', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الحضور', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('في الوقت', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('التأخير', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الغياب', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الإجازات', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('أيام الراحة', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('دقائق التأخير', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الانصراف المبكر (د)', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: _reportData.map((r) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text('${r['emp_code']}')),
                                          DataCell(Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                          DataCell(Text(r['department'] ?? '')),
                                          DataCell(Text('${r['days_present']}', style: const TextStyle(color: AppColors.onTime, fontWeight: FontWeight.bold))),
                                          DataCell(Text('${r['days_on_time']}')),
                                          DataCell(Text('${r['days_late']}', style: TextStyle(color: (r['days_late'] ?? 0) > 0 ? AppColors.late : null))),
                                          DataCell(Text('${r['days_absent']}', style: TextStyle(color: (r['days_absent'] ?? 0) > 0 ? AppColors.danger : null, fontWeight: FontWeight.bold))),
                                          DataCell(Text('${r['days_on_leave']}', style: const TextStyle(color: AppColors.info))),
                                          DataCell(Text('${r['days_off']}')),
                                          DataCell(Text('${r['total_late_minutes']} د')),
                                          DataCell(Text('${r['total_early_leave_minutes']} د')),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}
