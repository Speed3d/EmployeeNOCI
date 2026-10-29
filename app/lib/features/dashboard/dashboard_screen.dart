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
  int _eligibleEmployees = 0;
  bool _isCommitted = false;

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
      if (!mounted) return;
      setState(() {
        _currentDate = res['date'] ?? '';
        _stats = res['stats'];
        _eligibleEmployees = res['eligibleEmployees'] ?? 0;
        _isCommitted = res['isCommitted'] == true;
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
    // Hint: إجمالي الموظفين = المشمولون بالكشوفات حالياً، ونسبة الالتزام تُحسب من سجلات اليوم المعتمد
    final total = _eligibleEmployees;
    final dayTotal = _stats?['total'] ?? 0;
    final present = _stats?['present'] ?? 0;
    final late = _stats?['late'] ?? 0;
    final absent = _stats?['absent'] ?? 0;
    final onLeave = _stats?['onLeave'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 12 : 24),
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
                    color: AppColors.navy.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.waving_hand_rounded, color: AppColors.goldBright, size: 22),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'أهلاً بك، ${auth.user?['fullName'] ?? 'المشرف'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'متابعة الحضور والانصراف لتاريخ: ${DateFormatter.toArabicDate(_currentDate)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
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

            if (!_isCommitted)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'لم يُعتمد كشف اليوم بعد، لذلك مؤشرات الحضور والغياب صفرية حتى يُرفع ويُعتمد كشف البصمة.',
                        style: TextStyle(fontSize: 13, color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),

            // شبكة الـ 5 كروت المعتمدة فقط
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 5;
                if (constraints.maxWidth < 650) {
                  crossAxisCount = 2;
                } else if (constraints.maxWidth < 1100) {
                  crossAxisCount = 3;
                }

                return GridView(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 132,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
                      subtitle: 'نسبة الالتزام: ${dayTotal > 0 ? ((present / dayTotal) * 100).toStringAsFixed(1) : 0}%',
                      onTap: () => widget.onNavigate(1),
                    ),
                    KpiCard(
                      title: 'المتأخرون',
                      value: '$late',
                      icon: Icons.watch_later_rounded,
                      color: AppColors.late,
                      subtitle: 'تأخير عن بداية الدوام',
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
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
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
