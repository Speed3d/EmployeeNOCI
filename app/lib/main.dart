import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'core/api_client.dart';
import 'core/auth_provider.dart';
import 'shared/main_layout.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/maintenance_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/employees/employees_screen.dart';
import 'features/schedules/schedules_screen.dart';
import 'features/leaves/leaves_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/audit_logs/audit_logs_screen.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة العميل والمصادقة
  await ApiClient.instance.init();
  await AuthProvider.instance.init();

  runApp(const NociAttendanceApp());
}

/// Hint: جذر التطبيق مع دعم كامل وموثوق للغة العربية والاتجاه من اليمين لليسار (RTL)
class NociAttendanceApp extends StatelessWidget {
  const NociAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthProvider.instance,
      builder: (context, _) {
        final auth = AuthProvider.instance;

        return MaterialApp(
          title: AppConstants.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            );
          },
          home: auth.isLoading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : auth.isLoggedIn
                  ? (auth.isMaintenance && !auth.isSuperAdmin)
                      ? const MaintenanceScreen()
                      : const AppShell()
                  : const LoginScreen(),
        );
      },
    );
  }
}

/// Hint: الصدفة الرئيسية للتبديل بين الشاشات
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final List<String> _titles = [
    'لوحة المؤشرات العامة',
    'كشف الحضور والتشخيص اليومي',
    'سجل ودليل موظفي المقر',
    'جداول الدوام والشفتات وأيام الراحة',
    'الإجازات والأذونات والعطل الرسمية',
    'التقارير التراكمية الشهرية',
    'المحادثة الإدارية المباشرة',
    'سجل الحركات والتدقيق الأمني (Audit Logs)',
    'إعدادات النظام والدوام والمستخدمين',
  ];

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(onNavigate: (index) => setState(() => _selectedIndex = index)),
      const AttendanceScreen(),
      const EmployeesScreen(),
      const SchedulesScreen(),
      const LeavesScreen(),
      const ReportsScreen(),
      const ChatScreen(),
      const AuditLogsScreen(),
      const SettingsScreen(),
    ];

    final safeIndex = _selectedIndex < screens.length ? _selectedIndex : 0;

    return MainLayout(
      selectedIndex: safeIndex,
      title: _titles[safeIndex],
      onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
      body: screens[safeIndex],
    );
  }
}
