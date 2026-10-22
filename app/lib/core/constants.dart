import 'package:flutter/material.dart';
import 'theme.dart';

/// Hint: ملف الثوابت وعناوين الـ API وقيم النصوص العربية
class AppConstants {
  static const String appTitle = 'نظام متابعة حضور وانصراف الموظفين';
  static const String institutionName = 'اللجنة الأولمبية الوطنية العراقية (NOCI)';
  static const String appVersion = '1.0.0';

  /// Hint: عنوان الـ API الأساسي (يمكن تغييره عند الربط بالنفق أو بالدومين)
  /// على الويب يستخدم نفس الدومين تلقائياً إذا كان المسار نسبياً، أو localhost في التطوير
  static String defaultBaseUrl = 'http://localhost:5000/api';
  static String productionBaseUrl = 'https://Employee.nociraq.com/api';

  // مفاتيح التخزين المحلي (SharedPreferences)
  static const String tokenKey = 'noci_auth_token';
  static const String userKey = 'noci_user_data';
  static const String baseUrlKey = 'noci_api_base_url';

  /// ترجمة الحالات إلى اللغة العربية
  static String getStatusLabel(String status) {
    switch (status) {
      case 'ON_TIME':
        return 'حضور نظامي';
      case 'LATE':
        return 'تأخير بسيط';
      case 'VERY_LATE':
        return 'تأخير كبير';
      case 'EARLY_LEAVE':
        return 'انصراف مبكر';
      case 'MISSED_PUNCH':
        return 'بصمة ناقصة';
      case 'ABSENT':
        return 'غائب';
      case 'ON_LEAVE':
        return 'مجاز';
      case 'VIP_EXEMPT':
        return 'مستثنى VIP';
      case 'DEPT_EXCLUDED':
        return 'قسم مستبعد';
      case 'HOLIDAY':
        return 'عطلة رسمية';
      case 'OFF_DAY':
        return 'يوم راحة';
      default:
        return status;
    }
  }

  /// الحصول على لون الحالة
  static Color getStatusColor(String status) {
    switch (status) {
      case 'ON_TIME':
        return AppColors.onTime;
      case 'LATE':
        return AppColors.late;
      case 'VERY_LATE':
        return AppColors.veryLate;
      case 'EARLY_LEAVE':
        return AppColors.earlyLeave;
      case 'MISSED_PUNCH':
        return AppColors.missedPunch;
      case 'ABSENT':
        return AppColors.absent;
      case 'ON_LEAVE':
        return AppColors.onLeave;
      case 'VIP_EXEMPT':
        return AppColors.vipExempt;
      case 'DEPT_EXCLUDED':
        return Colors.grey;
      case 'HOLIDAY':
        return AppColors.holiday;
      case 'OFF_DAY':
        return AppColors.offDay;
      default:
        return Colors.blueGrey;
    }
  }
}
