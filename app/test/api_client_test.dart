import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noci_attendance/core/api_client.dart';

http.Response jsonResponse(int status, Map<String, dynamic> body) {
  return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
}

void main() {
  final api = ApiClient.instance;

  setUp(() {
    api.onUnauthorized = null;
    api.onMaintenance = null;
    api.onPasswordChangeRequired = null;
  });

  test('returns the data field of successful responses', () async {
    api.httpClient = MockClient((_) async => jsonResponse(200, {'success': true, 'data': {'value': 42}}));
    final res = await api.get('/anything');
    expect(res['value'], 42);
  });

  test('401 triggers logout callback and throws ApiException', () async {
    var loggedOut = false;
    api.onUnauthorized = () => loggedOut = true;
    api.httpClient = MockClient((_) async => jsonResponse(401, {'success': false, 'code': 'SESSION_EXPIRED', 'message': 'انتهت'}));
    await expectLater(api.get('/employees'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(loggedOut, isTrue);
  });

  test('401 on the login endpoint does not trigger logout', () async {
    var loggedOut = false;
    api.onUnauthorized = () => loggedOut = true;
    api.httpClient = MockClient((_) async => jsonResponse(401, {'success': false, 'message': 'بيانات الدخول غير صحيحة'}));
    await expectLater(api.post('/auth/login', {}), throwsA(isA<ApiException>()));
    expect(loggedOut, isFalse);
  });

  test('503 MAINTENANCE triggers maintenance callback', () async {
    var maintenance = false;
    api.onMaintenance = () => maintenance = true;
    api.httpClient = MockClient((_) async => jsonResponse(503, {'success': false, 'code': 'MAINTENANCE', 'message': 'صيانة'}));
    await expectLater(api.get('/employees'), throwsA(isA<ApiException>()));
    expect(maintenance, isTrue);
  });

  test('403 PASSWORD_CHANGE_REQUIRED triggers its callback', () async {
    var required = false;
    api.onPasswordChangeRequired = () => required = true;
    api.httpClient = MockClient((_) async => jsonResponse(403, {'success': false, 'code': 'PASSWORD_CHANGE_REQUIRED', 'message': 'غيّر كلمة المرور'}));
    await expectLater(api.get('/employees'), throwsA(isA<ApiException>()));
    expect(required, isTrue);
  });

  test('network failures become a readable ApiException', () async {
    api.httpClient = MockClient((_) async => throw http.ClientException('connection refused'));
    await expectLater(api.get('/employees'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)));
  });

  test('download URLs come from a short-lived ticket, never the session token', () async {
    api.httpClient = MockClient((req) async {
      expect(req.url.path, endsWith('/downloads/ticket'));
      return jsonResponse(200, {'success': true, 'data': {'url': '/reports/export-daily?date=2026-10-20&ticket=abc'}});
    });
    final url = await api.downloadUrl('export-daily', {'date': '2026-10-20'});
    expect(url, endsWith('/reports/export-daily?date=2026-10-20&ticket=abc'));
    expect(url.contains('token='), isFalse);
  });
}
