import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Hint: شاشة التقارير الشهرية والتراكمية وتصدير كشوفات الإكسل
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _selectedYear = 2026;
  int _selectedMonth = 10;
  bool _isLoading = true;
  String? _error;
  List<dynamic> _reportData = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.instance.get('/reports/monthly?year=$_selectedYear&month=$_selectedMonth');
      setState(() {
        _reportData = res['report'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // شريط تحديد الشهر والسنة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: _selectedYear,
                  items: const [
                    DropdownMenuItem(value: 2025, child: Text('سنة 2025')),
                    DropdownMenuItem(value: 2026, child: Text('سنة 2026')),
                    DropdownMenuItem(value: 2027, child: Text('سنة 2027')),
                  ],
                  onChanged: (y) {
                    if (y != null) {
                      setState(() => _selectedYear = y);
                      _loadReport();
                    }
                  },
                ),
                const SizedBox(width: 14),
                DropdownButton<int>(
                  value: _selectedMonth,
                  items: List.generate(12, (i) {
                    final m = i + 1;
                    return DropdownMenuItem(value: m, child: Text('شهر $m'));
                  }),
                  onChanged: (m) {
                    if (m != null) {
                      setState(() => _selectedMonth = m);
                      _loadReport();
                    }
                  },
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('تحديث التقرير'),
                  onPressed: _loadReport,
                ),
              ],
            ),
          ),

          // محتوى التقرير
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reportData.isEmpty
                    ? const Center(child: Text('لا توجد بيانات لهذا الشهر'))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Card(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(AppColors.navy.withOpacity(0.06)),
                              columns: const [
                                DataColumn(label: Text('المعرف', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('اسم الموظف', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('القسم', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('أيام الحضور', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('أيام في الوقت', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('أيام التأخير', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('مجموع دقائق التأخير', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('مجموع الإضافي (د)', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('أيام الغياب', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('أيام الإجازات', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: _reportData.map((r) {
                                final lateMin = r['total_late_minutes'] ?? 0;
                                final absentDays = r['days_absent'] ?? 0;

                                return DataRow(
                                  cells: [
                                    DataCell(Text('${r['emp_code']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(r['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(r['department'] ?? '')),
                                    DataCell(Text('${r['days_present']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.onTime))),
                                    DataCell(Text('${r['days_on_time']}')),
                                    DataCell(Text('${r['days_late']}', style: TextStyle(color: (r['days_late'] ?? 0) > 0 ? AppColors.late : null))),
                                    DataCell(Text('$lateMin دقيقة', style: TextStyle(fontWeight: lateMin > 0 ? FontWeight.bold : FontWeight.normal, color: lateMin > 0 ? AppColors.late : null))),
                                    DataCell(Text('+${r['total_overtime_minutes'] ?? 0} د', style: const TextStyle(color: AppColors.onTime))),
                                    DataCell(Text('$absentDays', style: TextStyle(fontWeight: absentDays > 0 ? FontWeight.bold : FontWeight.normal, color: absentDays > 0 ? AppColors.absent : null))),
                                    DataCell(Text('${r['days_on_leave']}', style: const TextStyle(color: AppColors.onLeave))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
