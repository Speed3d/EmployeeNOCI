import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'constants.dart';

/// Hint: مزود حالة المصادقة وإدارة الجلسات والصلاحيات (Auth Provider)
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

  bool get isSuperAdmin => _user != null && _user!['role'] == 'SUPER_ADMIN';
  bool get isHrManager => _user != null && (_user!['role'] == 'SUPER_ADMIN' || _user!['role'] == 'HR_MANAGER');

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
