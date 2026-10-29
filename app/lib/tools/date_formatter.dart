import 'package:intl/intl.dart';

/// Hint: أدوات ومساعدات تنسيق الوقت والتاريخ باللغة العربية (بأسماء الأشهر المعتمدة في العراق)
class DateFormatter {
  static final DateFormat _dateOnlyFormat = DateFormat('yyyy-MM-dd');

  static const List<String> iraqiMonths = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];

  static const List<String> weekDays = [
    'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  /// Hint: فرق توقيت بغداد عن UTC (ثابت بلا توقيت صيفي)
  static const Duration baghdadOffset = Duration(hours: 3);

  /// تنسيق كائن DateTime إلى YYYY-MM-DD
  static String toYmd(DateTime dt) => _dateOnlyFormat.format(dt);

  /// اسم الشهر بالتسمية العراقية (1..12)
  static String monthName(int month) => iraqiMonths[(month - 1).clamp(0, 11)];

  /// تحويل تاريخ نصي أو DateTime إلى تاريخ عربي مقروء (مثال: الثلاثاء، 20 تشرين الأول 2026)
  static String toArabicDate(String? ymdString) {
    if (ymdString == null || ymdString.isEmpty) return '-';
    try {
      return formatArabicDate(DateTime.parse(ymdString));
    } catch (_) {
      return ymdString;
    }
  }

  static String formatArabicDate(DateTime dt) {
    return '${weekDays[dt.weekday - 1]}، ${dt.day} ${monthName(dt.month)} ${dt.year}';
  }

  /// Hint: تحويل طابع زمني من قاعدة البيانات (UTC بصيغة YYYY-MM-DD HH:MM:SS) إلى توقيت بغداد
  static DateTime? fromDbUtc(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized.endsWith('Z') ? normalized : '${normalized}Z');
    if (parsed == null) return null;
    return parsed.toUtc().add(baghdadOffset);
  }

  /// Hint: عرض طابع زمني من قاعدة البيانات بتوقيت بغداد (YYYY-MM-DD hh:mm ص/م)
  static String dbTimestampToLocal(String? value) {
    final dt = fromDbUtc(value);
    if (dt == null) return value == null || value.isEmpty ? '-' : value;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${toYmd(dt)} ${formatTime12h('$hh:$mm')}';
  }

  /// استخراج الوقت بتنسيق 12 ساعة مع ص/م
  static String formatTime12h(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '-';
    try {
      final clean = timeStr.contains(' ') ? timeStr.split(' ')[1] : timeStr;
      final parts = clean.split(':');
      int h = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
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
