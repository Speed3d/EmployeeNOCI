import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'constants.dart';

/// Hint: مزود حالة المصادقة وإدارة الجلسات والصلاحيات (Auth Provider)
/// يدعم الرتبتين المعتمدتين: السوبر أدمن ومدخل البيانات مع الصلاحيات الخاصة
class AuthProvider extends ChangeNotifier {
  static final AuthProvider instance = AuthProvider._();
  AuthProvider._();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String? _announcementBanner;
  bool _isMaintenance = false;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get announcementBanner => _announcementBanner;
  bool get isMaintenance => _isMaintenance;

  // الرتب الحصرية
  bool get isSuperAdmin => _user != null && _user!['role'] == 'SUPER_ADMIN';
  bool get isDataEntry => _user != null && _user!['role'] == 'DATA_ENTRY';

  // الصلاحيات الإضافية المفوضة لمدخل البيانات
  bool get canManageExclusions => isSuperAdmin || (_user != null && _user!['canManageExclusions'] == true);
  bool get canRecommit => isSuperAdmin || (_user != null && _user!['canRecommit'] == true);

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(AppConstants.userKey);

    if (userJson != null) {
      try {
        _user = jsonDecode(userJson);
      } catch (_) {
        _user = null;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final res = await ApiClient.instance.post('/auth/login', {
      'username': username,
      'password': password,
    });

    final token = res['token'];
    _user = res['user'];

    final systemStatus = res['systemStatus'];
    if (systemStatus != null) {
      _announcementBanner = systemStatus['announcementBanner'];
      _isMaintenance = systemStatus['isMaintenance'] ?? false;
    }

    await ApiClient.instance.setToken(token);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, jsonEncode(_user));

    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.instance.get('/auth/me');
      if (res['user'] != null) {
        updateUser(Map<String, dynamic>.from(res['user']));
      }
    } catch (_) {}
  }

  Future<void> updateUser(Map<String, dynamic> updated) async {
    _user = {
      ...?_user,
      ...updated,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, jsonEncode(_user));
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null;
    _announcementBanner = null;
    _isMaintenance = false;
    await ApiClient.instance.setToken(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.userKey);

    notifyListeners();
  }

  void updateBanner(String? bannerText) {
    _announcementBanner = bannerText;
    notifyListeners();
  }
}
