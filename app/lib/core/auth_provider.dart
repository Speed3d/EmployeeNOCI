import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'constants.dart';

/// Hint: مزود حالة المصادقة وإدارة الجلسات والصلاحيات وهوية المؤسسة (Auth Provider)
/// يدعم الرتبتين المعتمدتين: السوبر أدمن ومدخل البيانات مع الصلاحيات الخاصة ووضع الصيانة
class AuthProvider extends ChangeNotifier {
  static final AuthProvider instance = AuthProvider._();
  AuthProvider._();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String? _announcementBanner;
  bool _isMaintenance = false;

  String? _logoUrl;
  String _institutionName = AppConstants.institutionName;
  String _appTitle = AppConstants.appTitle;
  String _activeYear = '2026';

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get announcementBanner => _announcementBanner;
  bool get isMaintenance => _isMaintenance;

  String? get logoUrl => _logoUrl;
  String get institutionName => _institutionName;
  String get appTitle => _appTitle;
  String get activeYear => _activeYear;

  String? get fullLogoUrl {
    if (_logoUrl == null || _logoUrl!.isEmpty) return null;
    if (_logoUrl!.startsWith('http://') || _logoUrl!.startsWith('https://')) return _logoUrl;
    final base = ApiClient.instance.baseUrl.replaceAll('/api', '');
    return '$base$_logoUrl';
  }

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

    _logoUrl = prefs.getString('branding_logo_url');
    _institutionName = prefs.getString('branding_institution_name') ?? AppConstants.institutionName;
    _appTitle = prefs.getString('branding_app_title') ?? AppConstants.appTitle;
    _activeYear = prefs.getString('branding_active_year') ?? '2026';

    // Hint: ربط معالج انتهاء الجلسة (401) لتسجيل الخروج تلقائياً
    ApiClient.instance.onUnauthorized = () {
      if (_user != null) {
        logout();
      }
    };

    _isLoading = false;
    notifyListeners();

    // فحص صحة النظام وهوية المؤسسة في الخلفية
    checkSystemStatus();
  }

  Future<void> checkSystemStatus() async {
    try {
      final res = await ApiClient.instance.get('/system/status');
      if (res != null) {
        _isMaintenance = res['isMaintenance'] == true;
        _announcementBanner = res['announcementBanner'];
        if (res['logoUrl'] != null && res['logoUrl'].toString().isNotEmpty) {
          _logoUrl = res['logoUrl'];
        }
        if (res['institutionName'] != null && res['institutionName'].toString().isNotEmpty) {
          _institutionName = res['institutionName'];
        }
        if (res['appTitle'] != null && res['appTitle'].toString().isNotEmpty) {
          _appTitle = res['appTitle'];
        }
        if (res['activeYear'] != null && res['activeYear'].toString().isNotEmpty) {
          _activeYear = res['activeYear'].toString();
        }

        final prefs = await SharedPreferences.getInstance();
        if (_logoUrl != null) await prefs.setString('branding_logo_url', _logoUrl!);
        await prefs.setString('branding_institution_name', _institutionName);
        await prefs.setString('branding_app_title', _appTitle);
        await prefs.setString('branding_active_year', _activeYear);

        notifyListeners();
      }
    } catch (_) {}
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
      if (systemStatus['logoUrl'] != null && systemStatus['logoUrl'].toString().isNotEmpty) {
        _logoUrl = systemStatus['logoUrl'];
      }
      if (systemStatus['institutionName'] != null && systemStatus['institutionName'].toString().isNotEmpty) {
        _institutionName = systemStatus['institutionName'];
      }
      if (systemStatus['appTitle'] != null && systemStatus['appTitle'].toString().isNotEmpty) {
        _appTitle = systemStatus['appTitle'];
      }
      if (systemStatus['activeYear'] != null && systemStatus['activeYear'].toString().isNotEmpty) {
        _activeYear = systemStatus['activeYear'].toString();
      }
    }

    await ApiClient.instance.setToken(token);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, jsonEncode(_user));
    if (_logoUrl != null) await prefs.setString('branding_logo_url', _logoUrl!);
    await prefs.setString('branding_institution_name', _institutionName);
    await prefs.setString('branding_app_title', _appTitle);
    await prefs.setString('branding_active_year', _activeYear);

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

  Future<void> updateBranding({String? logoUrl, String? institutionName, String? appTitle}) async {
    if (logoUrl != null) _logoUrl = logoUrl;
    if (institutionName != null && institutionName.isNotEmpty) _institutionName = institutionName;
    if (appTitle != null && appTitle.isNotEmpty) _appTitle = appTitle;

    final prefs = await SharedPreferences.getInstance();
    if (_logoUrl != null) await prefs.setString('branding_logo_url', _logoUrl!);
    await prefs.setString('branding_institution_name', _institutionName);
    await prefs.setString('branding_app_title', _appTitle);

    notifyListeners();
  }

  void setMaintenanceMode(bool isMaint) {
    _isMaintenance = isMaint;
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

  /// Hint: تحديث السنة المالية/الإدارية النشطة في المزود والتخزين المحلي
  Future<void> setActiveYear(String year) async {
    if (year.trim().isEmpty) return;
    _activeYear = year.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('branding_active_year', _activeYear);
    notifyListeners();
  }
}
