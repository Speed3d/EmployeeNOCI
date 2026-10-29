import 'package:flutter_test/flutter_test.dart';
import 'package:noci_attendance/tools/date_formatter.dart';

void main() {
  group('DateFormatter', () {
    test('uses Iraqi month names', () {
      expect(DateFormatter.toArabicDate('2026-10-20'), 'الثلاثاء، 20 تشرين الأول 2026');
      expect(DateFormatter.monthName(1), 'كانون الثاني');
      expect(DateFormatter.monthName(12), 'كانون الأول');
    });

    test('converts database UTC timestamps to Baghdad time', () {
      final dt = DateFormatter.fromDbUtc('2026-10-28 21:38:06');
      expect(dt, isNotNull);
      expect(DateFormatter.toYmd(dt!), '2026-10-29');
      expect(dt.hour, 0);
      expect(dt.minute, 38);
      expect(DateFormatter.dbTimestampToLocal('2026-10-28 21:38:06'), '2026-10-29 12:38 ص');
    });

    test('handles empty and invalid values safely', () {
      expect(DateFormatter.fromDbUtc(null), isNull);
      expect(DateFormatter.dbTimestampToLocal(''), '-');
      expect(DateFormatter.toArabicDate('not-a-date'), 'not-a-date');
    });

    test('formats 12-hour times and minutes', () {
      expect(DateFormatter.formatTime12h('2026-10-20 13:05:00'), '1:05 م');
      expect(DateFormatter.formatTime12h('09:43'), '9:43 ص');
      expect(DateFormatter.formatMinutes(75), '1 س و 15 د');
      expect(DateFormatter.formatMinutes(0), '0 د');
    });
  });
}
