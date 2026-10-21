import 'package:intl/intl.dart';

/// Hint: أدوات ومساعدات تنسيق الوقت والتاريخ باللغة العربية
class DateFormatter {
  static final DateFormat _dateOnlyFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _arabicDateFormat = DateFormat('EEEE، d MMMM yyyy', 'ar');

  /// تنسيق كائن DateTime إلى YYYY-MM-DD
  static String toYmd(DateTime dt) => _dateOnlyFormat.format(dt);

  /// تحويل تاريخ نصي إلى تاريخ عربي مقروء (مثال: الثلاثاء، 20 تشرين الأول 2026)
  static String toArabicDate(String? ymdString) {
    if (ymdString == null || ymdString.isEmpty) return '-';
    try {
      final dt = DateTime.parse(ymdString);
      return _arabicDateFormat.format(dt);
    } catch (_) {
      return ymdString;
    }
  }

  /// استخراج الوقت بتنسيق 12 ساعة مع ص/م
  static String formatTime12h(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '-';
    try {
      final clean = timeStr.contains(' ') ? timeStr.split(' ')[1] : timeStr;
      final parts = clean.split(':');
      int h = int.parse(parts[0]);
      int m = int.parse(parts[1]);
      final period = h >= 12 ? 'م' : 'ص';
      if (h > 12) h -= 12;
      if (h == 0) h = 12;
      final mm = m.toString().padLeft(2, '0');
      return '$h:$mm $period';
    } catch (_) {
      return timeStr;
    }
  }

  /// تحويل عدد الدقائق إلى نص عربي
  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0 د';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m دقيقة';
    if (m == 0) return '$h ساعة';
    return '$h س و $m د';
  }
}
