import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../tools/responsive.dart';
import '../features/auth/profile_dialog.dart';

/// Hint: الإطار الهيكلي العام للشاشات (Main Layout)
/// يدعم التجاوب الذكي مع الهواتف الذكية (Overlay Drawer) وشريط التنبيهات العلوي
class MainLayout extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final Widget body;
  final String title;
  final List<Widget>? actions;

  const MainLayout({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.title,
    this.actions,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _unreadChatCount = 0;
  Timer? _unreadTimer;

  @override
  void initState() {
    super.initState();
    _fetchUnreadChat();
    _unreadTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchUnreadChat());
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchUnreadChat() async {
    try {
      final res = await ApiClient.instance.get('/chat/unread-count');
      if (mounted && res != null && res['unreadCount'] != null) {
        final count = (res['unreadCount'] as num).toInt();
        if (count != _unreadChatCount) {
          setState(() => _unreadChatCount = count);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.instance;
    final isDesktop = Responsive.isDesktop(context);
    final theme = Theme.of(context);

    // قائمة التبويبات المتاحة حسب الصلاحية
    final navItems = [
      _NavItem(Icons.dashboard_rounded, 'لوحة المؤشرات', 0),
      _NavItem(Icons.fingerprint_rounded, 'كشف الحضور اليومي', 1),
      _NavItem(Icons.people_alt_rounded, 'سجل الموظفين', 2),
      _NavItem(Icons.calendar_month_rounded, 'جداول الدوام والراحة', 3),
      _NavItem(Icons.event_note_rounded, 'الإجازات والعطلات', 4),
      _NavItem(Icons.assessment_rounded, 'التقارير الشهرية', 5),
      _NavItem(Icons.chat_bubble_outline_rounded, 'المحادثة الفورية', 6, badgeCount: _unreadChatCount),
      if (auth.isSuperAdmin) ...[
        _NavItem(Icons.history_rounded, 'سجل الحركات (Logs)', 7),
        _NavItem(Icons.settings_rounded, 'الإعدادات والصيانة', 8),
      ],
    ];

    final sidebarContent = _buildSidebar(navItems, theme);

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : Drawer(child: sidebarContent),
      body: Column(
        children: [
          // 1. شريط الإعلانات والتعاميم العلوي (Announcement Banner)
          if (auth.announcementBanner != null && auth.announcementBanner!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.goldDark,
              child: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      auth.announcementBanner!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 2. شريط التنبيه في حال كان النظام في وضع الصيانة
          if (auth.isMaintenance)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.danger,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.construction_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'تنبيه: النظام في وضع الصيانة حالياً (محصور بالسوبر أدمن فقط)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // 3. الشريط العلوي (Topbar)
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                if (!isDesktop) ...[
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 8),
                ],

                // العنوان (يُختصر على الشاشات الضيقة بدل أن يخرج عن الشاشة)
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Responsive.isMobile(context) ? 15 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Hint: شارة السنة النشطة المرتبطة ديناميكياً بإعدادات النظام
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.navy),
                      const SizedBox(width: 4),
                      Text(
                        auth.activeYear,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // أزرار العمليات الإضافية من الشاشة
                if (widget.actions != null) ...widget.actions!,

                const SizedBox(width: 4),

                // اسم وصورة المستخدم (قابل للنقر لفتح الملف الشخصي - النقطة 14)
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const ProfileDialog(),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: AppColors.navy.withValues(alpha: 0.12),
                          backgroundImage: auth.user?['avatarUrl'] != null && auth.user!['avatarUrl'].toString().isNotEmpty
                              ? NetworkImage('${ApiClient.instance.serverOrigin}${auth.user!['avatarUrl']}')
                              : null,
                          child: (auth.user?['avatarUrl'] == null || auth.user!['avatarUrl'].toString().isEmpty)
                              ? Text(
                                  (auth.user?['fullName'] ?? 'U').substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navy),
                                )
                              : null,
                        ),
                        if (!Responsive.isMobile(context)) ...[
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.user?['fullName'] ?? 'المستخدم',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                auth.isSuperAdmin ? 'سوبر أدمن' : 'مدخل بيانات',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // زر تسجيل الخروج
                IconButton(
                  tooltip: 'تسجيل الخروج',
                  icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('تسجيل الخروج'),
                        content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                            onPressed: () {
                              Navigator.pop(ctx);
                              auth.logout();
                            },
                            child: const Text('تأكيد الخروج', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // 4. المحتوى الداخلي مع القائمة الجانبية للشاشات الكبيرة
          Expanded(
            child: Row(
              children: [
                if (isDesktop)
                  SizedBox(
                    width: 250,
                    child: sidebarContent,
                  ),
                Expanded(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: widget.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(List<_NavItem> navItems, ThemeData theme) {
    return Material(
      color: theme.cardTheme.color,
      child: Column(
        children: [
          // ترويسة القائمة مع الشعار
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            alignment: Alignment.centerRight,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AuthProvider.instance.fullLogoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            AuthProvider.instance.fullLogoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.security_rounded, color: AppColors.goldBright, size: 22),
                          ),
                        )
                      : const Icon(Icons.security_rounded, color: AppColors.goldBright, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuthProvider.instance.institutionName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AuthProvider.instance.appTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // عناصر القائمة
          Expanded(
            child: ListView.builder(
              itemCount: navItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, index) {
                final item = navItems[index];
                final isSelected = widget.selectedIndex == item.index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.navy.withValues(alpha: 0.08),
                      leading: Icon(
                        item.icon,
                        size: 20,
                        color: isSelected ? AppColors.navy : Colors.grey,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.navy : theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                          if (item.badgeCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${item.badgeCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        if (!Responsive.isDesktop(context)) {
                          Navigator.pop(context); // إغلاق الـ Drawer
                        }
                        widget.onDestinationSelected(item.index);
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // تذييل القائمة
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'الإصدار ${AppConstants.appVersion}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  final int badgeCount;
  _NavItem(this.icon, this.label, this.index, {this.badgeCount = 0});
}
