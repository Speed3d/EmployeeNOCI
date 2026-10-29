import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

/// Hint: عميل الاتصال الموحد بالخادم (API Client)
/// يكتشف بيئة التشغيل تلقائياً، ويطبق مهلة على كل طلب، ويعالج انتهاء الجلسة ووضع الصيانة مركزياً
class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  /// Hint: عميل HTTP قابل للاستبدال في الاختبارات
  http.Client httpClient = http.Client();

  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);

  String _baseUrl = AppConstants.defaultBaseUrl;
  String? _token;

  /// Hint: يُستدعى عند انتهاء الجلسة أو تعطيل الحساب (401) لتسجيل الخروج الفوري
  VoidCallback? onUnauthorized;

  /// Hint: يُستدعى عند رد الخادم بوضع الصيانة (503) لعرض شاشة الصيانة فوراً
  VoidCallback? onMaintenance;

  /// Hint: يُستدعى عندما يطلب الخادم تغيير كلمة المرور المؤقتة
  VoidCallback? onPasswordChangeRequired;

  String get baseUrl => _baseUrl;
  String? get token => _token;

  /// Hint: أصل الخادم بدون اللاحقة /api (لروابط الصور والمرفقات)
  String get serverOrigin => _baseUrl.endsWith('/api') ? _baseUrl.substring(0, _baseUrl.length - 4) : _baseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(AppConstants.tokenKey);
    final savedBase = prefs.getString(AppConstants.baseUrlKey);

    if (savedBase != null && savedBase.isNotEmpty) {
      _baseUrl = savedBase;
    } else if (kIsWeb) {
      // في متصفح الويب: إذا كان التطبيق مفتوحاً على نفس منفذ السيرفر (5000) أو على الدومين الخارجي
      final origin = Uri.base.origin;
      if (Uri.base.port == 5000 || Uri.base.host.toLowerCase().contains('nociraq')) {
        _baseUrl = '$origin/api';
      } else {
        // في وضع التطوير (Flutter Run على منفذ عشوائي)
        _baseUrl = 'http://localhost:5000/api';
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // في محاكي الأندرويد: localhost للحاسوب المضيف يُعبر عنه بـ 10.0.2.2
      _baseUrl = 'http://10.0.2.2:5000/api';
    } else {
      _baseUrl = AppConstants.defaultBaseUrl;
    }
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.baseUrlKey, _baseUrl);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString(AppConstants.tokenKey, token);
    } else {
      await prefs.remove(AppConstants.tokenKey);
    }
  }

  Map<String, String> _headers() {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  Future<dynamic> get(String endpoint) {
    return _send(endpoint, () => httpClient.get(Uri.parse('$_baseUrl$endpoint'), headers: _headers()));
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) {
    return _send(endpoint, () => httpClient.post(Uri.parse('$_baseUrl$endpoint'), headers: _headers(), body: jsonEncode(body)));
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) {
    return _send(endpoint, () => httpClient.put(Uri.parse('$_baseUrl$endpoint'), headers: _headers(), body: jsonEncode(body)));
  }

  Future<dynamic> delete(String endpoint) {
    return _send(endpoint, () => httpClient.delete(Uri.parse('$_baseUrl$endpoint'), headers: _headers()));
  }

  /// Hint: رفع ملف عبر MultipartRequest بمهلة أطول
  Future<dynamic> uploadFile(String endpoint, List<int> bytes, String filename) {
    return _send(endpoint, () async {
      final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl$endpoint'));
      if (_token != null) {
        req.headers['Authorization'] = 'Bearer $_token';
      }
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamedRes = await httpClient.send(req);
      return http.Response.fromStream(streamedRes);
    }, timeout: uploadTimeout);
  }

  /// Hint: طلب رابط تنزيل مؤقت (صالح 60 ثانية) بدل وضع رمز الجلسة في الرابط
  /// kind: export-daily | export-monthly | backup
  Future<String> downloadUrl(String kind, Map<String, dynamic> params) async {
    final res = await post('/downloads/ticket', {'kind': kind, 'params': params});
    return '$_baseUrl${res['url']}';
  }

  Future<dynamic> _send(String endpoint, Future<http.Response> Function() request, {Duration timeout = requestTimeout}) async {
    http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('انتهت مهلة الاتصال بالخادم، يرجى التحقق من الشبكة والمحاولة مجدداً', statusCode: 408);
    } on http.ClientException {
      throw ApiException('تعذر الاتصال بالخادم، يرجى التحقق من تشغيله ومن عنوانه', statusCode: 0);
    }
    return _handleResponse(res, endpoint: endpoint);
  }

  /// Hint: معالجة الاستجابات الموحدة مع التوجيه التلقائي عند انتهاء الجلسة أو الصيانة
  dynamic _handleResponse(http.Response res, {String endpoint = ''}) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = {'message': res.body};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    }

    final code = decoded is Map ? decoded['code']?.toString() : null;
    final isAuthEndpoint = endpoint.startsWith('/auth/login');

    if (res.statusCode == 401 && !isAuthEndpoint) {
      onUnauthorized?.call();
    } else if (res.statusCode == 503 && code == 'MAINTENANCE') {
      onMaintenance?.call();
    } else if (res.statusCode == 403 && code == 'PASSWORD_CHANGE_REQUIRED') {
      onPasswordChangeRequired?.call();
    }

    final msg = decoded is Map && decoded['message'] != null
        ? decoded['message'].toString()
        : 'خطأ في الاتصال (${res.statusCode})';
    throw ApiException(msg, statusCode: res.statusCode, code: code);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  ApiException(this.message, {this.statusCode = 400, this.code});

  @override
  String toString() => message;
}
