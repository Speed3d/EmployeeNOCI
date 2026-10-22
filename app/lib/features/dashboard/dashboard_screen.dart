import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../shared/kpi_card.dart';
import '../../tools/date_formatter.dart';

/// Hint: لوحة المؤشرات والإحصائيات الرئيسية المعتمدة (Dashboard)
/// تحتوي حصرياً على 5 كروت مؤشرات رئيسية وتستغني عن جدول العينة لتوفير واجهة سريعة ونقية
class DashboardScreen extends StatefulWidget {
  final Function(int) onNavigate;
  const DashboardScreen({super.key, required this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  String _currentDate = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.instance.get('/attendance/daily');
      setState(() {
        _currentDate = res['date'] ?? '';
        _stats = res['stats'];
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadDashboardData,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final auth = AuthProvider.instance;
    final total = _stats?['total'] ?? 0;
    final present = _stats?['present'] ?? 0;
    final late = (_stats?['late'] ?? 0) + (_stats?['veryLate'] ?? 0);
    final absent = _stats?['absent'] ?? 0;
    final onLeave = _stats?['onLeave'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة الترحيب الملكية
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.navyDark],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أهلاً بك، ${auth.user?['fullName'] ?? 'المشرف'} 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'متابعة الحضور والانصراف لتاريخ: ${DateFormatter.toArabicDate(_currentDate)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldBright,
                      foregroundColor: AppColors.navyDeepDark,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.file_upload_rounded, size: 20),
                    label: const Text('كشف اليوم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () => widget.onNavigate(1), // الانتقال لشاشة كشف الحضور
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // عنوان المؤشرات
            const Text(
              'مؤشرات الحضور والغياب الرئيسية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // شبكة الـ 5 كروت المعتمدة فقط
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 5;
                if (constraints.maxWidth < 650) {
                  crossAxisCount = 2;
                } else if (constraints.maxWidth < 1100) {
                  crossAxisCount = 3;
                }

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.35,
                  children: [
                    KpiCard(
                      title: 'إجمالي الموظفين',
                      value: '$total',
                      icon: Icons.people_alt_rounded,
                      color: AppColors.navy,
                      subtitle: 'الموظفون النشطون والمشمولون',
                      onTap: () => widget.onNavigate(2),
                    ),
                    KpiCard(
                      title: 'الحضور الفعلي',
                      value: '$present',
                      icon: Icons.how_to_reg_rounded,
                      color: AppColors.onTime,
                      subtitle: 'نسبة الالتزام: ${total > 0 ? ((present / total) * 100).toStringAsFixed(1) : 0}%',
                      onTap: () => widget.onNavigate(1),
                    ),
                    KpiCard(
                      title: 'المتأخرون',
                      value: '$late',
                      icon: Icons.watch_later_rounded,
                      color: AppColors.late,
                      subtitle: 'تأخير بعد 10:00 صباحاً',
                      onTap: () => widget.onNavigate(1),
                    ),
                    KpiCard(
                      title: 'الغياب التام',
                      value: '$absent',
                      icon: Icons.cancel_rounded,
                      color: AppColors.absent,
                      subtitle: 'بدون بصمة وبدون إجازة',
                      onTap: () => widget.onNavigate(1),
                    ),
                    KpiCard(
                      title: 'المجازون رسمياً',
                      value: '$onLeave',
                      icon: Icons.beach_access_rounded,
                      color: AppColors.onLeave,
                      subtitle: 'إجازات وأذونات معتمدة',
                      onTap: () => widget.onNavigate(4), // الذهاب لشاشة الإجازات
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 36),

            // بطاقة الإجراءات السريعة
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الوصول السريع',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.table_chart_rounded, size: 18, color: AppColors.navy),
                        label: const Text('كشف الحضور اليومي'),
                        onPressed: () => widget.onNavigate(1),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.badge_rounded, size: 18, color: AppColors.navy),
                        label: const Text('دليل الموظفين'),
                        onPressed: () => widget.onNavigate(2),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.navy),
                        label: const Text('جداول الدوام والشفتات'),
                        onPressed: () => widget.onNavigate(3),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.beach_access_rounded, size: 18, color: AppColors.navy),
                        label: const Text('الإجازات والعطل'),
                        onPressed: () => widget.onNavigate(4),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.bar_chart_rounded, size: 18, color: AppColors.navy),
                        label: const Text('التقارير الشهرية'),
                        onPressed: () => widget.onNavigate(5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
