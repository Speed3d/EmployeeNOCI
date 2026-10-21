import 'package:flutter_test/flutter_test.dart';
import 'package:noci_attendance/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NociAttendanceApp());
    expect(find.byType(NociAttendanceApp), findsOneWidget);
  });
}
