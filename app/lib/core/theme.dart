import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hint: الألوان الأساسية والهوية البصرية المعتمدة (مستوحاة ومطابقة لنظام DMS الملكي)
class AppColors {
  // ألوان الكحلي (الأساس والاستقرار)
  static const Color navy = Color(0xFF15315C);
  static const Color navyDeep = Color(0xFF0C1B33);
  static const Color navyDark = Color(0xFF16294A);
  static const Color navyDeepDark = Color(0xFF0A1428);

  // ألوان الذهبي (الفعل والتمييز والتفاعل)
  static const Color gold = Color(0xFFBE9A47);
  static const Color goldBright = Color(0xFFD6B158);
  static const Color goldDark = Color(0xFFD9B458);
  static const Color goldBrightDark = Color(0xFFEDCC73);

  // حالات البصمة والحضور (Status Colors)
  static const Color onTime = Color(0xFF178A5B);       // أخضر - حضور في الوقت
  static const Color late = Color(0xFFBE7A12);         // أصفر/كهرماني - تأخير بسيط
  static const Color veryLate = Color(0xFFE07A10);     // برتقالي - تأخير كبير
  static const Color earlyLeave = Color(0xFFD97706);   // كهرماني برتقالي - انصراف مبكر
  static const Color absent = Color(0xFFC13B33);       // أحمر - غياب تام
  static const Color onLeave = Color(0xFF1E6BB8);      // أزرق - إجازة رسمية
  static const Color vipExempt = Color(0xFF5A6E85);    // رمادي - مستثنى قيادي
  static const Color missedPunch = Color(0xFF8E44AD);  // بنفسجي - بصمة واحدة فقط
  static const Color holiday = Color(0xFF7E57C2);      // أرجواني هادئ للعطلات الرسمية
  static const Color offDay = Color(0xFF78909C);       // رمادي مزرق لأيام الراحة الأسبوعية

  // الحالات العامة
  static const Color success = Color(0xFF178A5B);
  static const Color danger = Color(0xFFC13B33);
  static const Color info = Color(0xFF1E6BB8);

  /// Hint: لون الفعل المتكيف مع الوضعين الفاتح والداكن (كحلي نهاراً وذهبي ليلاً)
  static Color action(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? goldBrightDark : navyDeep;

  static Color onAction(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? navyDeepDark : Colors.white;
}

/// Hint: الثيم العام للتطبيق (فاتح وداكن) مع خط Cairo العربي المتناسق
class AppTheme {
  // النمط الفاتح (Light Theme)
  static ThemeData get light {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFE9EDF4),
      primaryColor: AppColors.navy,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.navy,
        secondary: AppColors.gold,
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFF4F6FA),
        surfaceContainer: const Color(0xFFECEFF5),
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFF0F1D38),
        displayColor: const Color(0xFF0F1D38),
      ),
      dividerColor: const Color(0xFFE2E7EF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF0F1D38),
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E7EF)),
        ),
      ),
    );
  }

  // النمط الداكن (Dark Theme)
  static ThemeData get dark {
    final base = ThemeData.dark();
    const gold = AppColors.goldBrightDark;
    const onGold = AppColors.navyDeepDark;
    const ink = Color(0xFFE8EEF9);
    const surface = Color(0xFF0F1B30);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF070E1C),
      primaryColor: AppColors.navyDark,
      colorScheme: base.colorScheme.copyWith(
        primary: gold,
        onPrimary: onGold,
        primaryContainer: const Color(0xFF17294A),
        onPrimaryContainer: gold,
        secondary: AppColors.goldDark,
        onSecondary: onGold,
        surface: surface,
        surfaceContainerHighest: const Color(0xFF13223C),
        surfaceContainer: const Color(0xFF17294A),
        onSurface: ink,
        error: const Color(0xFFE2655C),
      ),
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      dividerColor: const Color(0xFF22334F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1B30),
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF22334F)),
        ),
      ),
    );
  }
}
