import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

/// Hint: عميل الاتصال الموحد بالخادم (API Client)
/// يكتشف بيئة التشغيل تلقائياً (متصفح الويب، محاكي الأندرويد، أو الدومين السحابي)
class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  String _baseUrl = AppConstants.defaultBaseUrl;
  String? _token;

  String get baseUrl => _baseUrl;
  String? get token => _token;

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
        // في وضع التطوير (Flutter Run على منفذ عشوائي مثل 54431)
        _baseUrl = 'http://localhost:5000/api';
      }
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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

  Map<String, String> _headers([Map<String, String>? extra]) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    if (extra != null) h.addAll(extra);
    return h;
  }

  Future<dynamic> get(String endpoint) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final res = await http.get(uri, headers: _headers());
    return _handleResponse(res);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final res = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final res = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final res = await http.delete(uri, headers: _headers());
    return _handleResponse(res);
  }

  /// Hint: رفع ملف كشف البصمة اليومي عبر MultipartRequest
  Future<dynamic> uploadFile(String endpoint, List<int> bytes, String filename) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final req = http.MultipartRequest('POST', uri);

    if (_token != null) {
      req.headers['Authorization'] = 'Bearer $_token';
    }

    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));

    final streamedRes = await req.send();
    final res = await http.Response.fromStream(streamedRes);
    return _handleResponse(res);
  }

  dynamic _handleResponse(http.Response res) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = {'message': res.body};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded['data'] ?? decoded;
    } else {
      final msg = decoded is Map && decoded['message'] != null
          ? decoded['message']
          : 'خطأ في الاتصال (${res.statusCode})';
      throw ApiException(msg, statusCode: res.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, {this.statusCode = 400});

  @override
  String toString() => message;
}
