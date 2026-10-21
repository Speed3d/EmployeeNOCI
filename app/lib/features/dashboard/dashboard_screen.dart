import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../shared/kpi_card.dart';
import '../../shared/status_badge.dart';
import '../../tools/responsive.dart';
import '../../tools/date_formatter.dart';

/// Hint: لوحة المؤشرات والإحصائيات الرئيسية (Dashboard)
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
  List<dynamic> _recentRecords = [];

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
        _recentRecords = (res['records'] as List<dynamic>?)?.take(8).toList() ?? [];
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
    final onTime = _stats?['onTime'] ?? 0;
    final late = (_stats?['late'] ?? 0) + (_stats?['veryLate'] ?? 0);
    final absent = _stats?['absent'] ?? 0;
    final onLeave = _stats?['onLeave'] ?? 0;
    final vipExempt = _stats?['vipExempt'] ?? 0;
    final deptExcluded = _stats?['deptExcluded'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة الترحيب والتاريخ
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.navyDark],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.2),
                    blurRadius: 10,
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
                          'أهلاً بك، ${auth.user?['fullName'] ?? 'زميلنا'} 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'متابعة الحضور والانصراف لتاريخ: ${DateFormatter.toArabicDate(_currentDate)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldBright,
                      foregroundColor: AppColors.navyDeepDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.file_upload_rounded, size: 18),
                    label: const Text('كشف اليوم', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => widget.onNavigate(1), // الذهاب لشاشة الحضور
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // عنوان المؤشرات
            const Text(
              'مؤشرات الحضور اليومية العامة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),

            // شبكة بطاقات الـ KPIs التفاعلية
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 4;
                if (constraints.maxWidth < 600) {
                  crossAxisCount = 2;
                } else if (constraints.maxWidth < 950) {
                  crossAxisCount = 3;
                }

                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    KpiCard(
                      title: 'إجمالي الموظفين',
                      value: '$total',
                      icon: Icons.people_alt_rounded,
                      color: AppColors.navy,
                      subtitle: 'القوة الإجمالية للمقر',
                      onTap: () => widget.onNavigate(2),
                    ),
                    KpiCard(
                      title: 'إجمالي الحضور',
                      value: '$present',
                      icon: Icons.how_to_reg_rounded,
                      color: AppColors.onTime,
                      subtitle: 'نسبة الالتزام: ${total > 0 ? ((present / total) * 100).toStringAsFixed(1) : 0}%',
                      onTap: () => widget.onNavigate(1),
                    ),
                    KpiCard(
                      title: 'في الوقت المحدد',
                      value: '$onTime',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.onTime,
                      subtitle: 'حضور قبل 10:00 صباحاً',
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
                      subtitle: 'إجازات وأذونات مسجلة',
                      onTap: () => widget.onNavigate(3),
                    ),
                    KpiCard(
                      title: 'مستثنون قياديون (VIP)',
                      value: '$vipExempt',
                      icon: Icons.star_rounded,
                      color: AppColors.vipExempt,
                      subtitle: 'الأمين العام والمستشارين',
                      onTap: () => widget.onNavigate(2),
                    ),
                    KpiCard(
                      title: 'أقسام مستبعدة',
                      value: '$deptExcluded',
                      icon: Icons.filter_alt_off_rounded,
                      color: Colors.grey,
                      subtitle: 'استقالة، تنسيب، متوفين',
                      onTap: () => widget.onNavigate(2),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),

            // قائمة أحدث حركات البصمة المسجلة اليوم
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'عينة من سجلات الحضور المسجلة اليوم',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => widget.onNavigate(1),
                  child: const Text('عرض الكشف الكامل ←'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentRecords.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final r = _recentRecords[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.navy.withOpacity(0.1),
                      child: Text(
                        '${r['emp_code']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                    ),
                    title: Text(
                      r['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${r['department']} • الدخول: ${DateFormatter.formatTime12h(r['first_punch'])} • الخروج: ${DateFormatter.formatTime12h(r['last_punch'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: StatusBadge(status: r['status'] ?? 'ABSENT'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
