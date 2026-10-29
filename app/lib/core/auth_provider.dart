import 'dart:async';
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

  static const Duration _profileRefreshInterval = Duration(minutes: 5);

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String? _announcementBanner;
  bool _isMaintenance = false;
  Timer? _refreshTimer;

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
    return '${ApiClient.instance.serverOrigin}$_logoUrl';
  }

  // الرتب الحصرية
  bool get isSuperAdmin => _user != null && _user!['role'] == 'SUPER_ADMIN';
  bool get isDataEntry => _user != null && _user!['role'] == 'DATA_ENTRY';

  // الصلاحيات الإضافية المفوضة لمدخل البيانات
  bool get canManageExclusions => isSuperAdmin || (_user != null && _user!['canManageExclusions'] == true);
  bool get canRecommit => isSuperAdmin || (_user != null && _user!['canRecommit'] == true);

  /// Hint: كلمة المرور الحالية مؤقتة ويجب تغييرها قبل استخدام النظام
  bool get mustChangePassword => _user != null && _user!['mustChangePassword'] == true;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(AppConstants.userKey);

    if (userJson != null && ApiClient.instance.token != null) {
      try {
        _user = Map<String, dynamic>.from(jsonDecode(userJson));
      } catch (_) {
        _user = null;
      }
    }

    _logoUrl = prefs.getString('branding_logo_url');
    _institutionName = prefs.getString('branding_institution_name') ?? AppConstants.institutionName;
    _appTitle = prefs.getString('branding_app_title') ?? AppConstants.appTitle;
    _activeYear = prefs.getString('branding_active_year') ?? '2026';

    // Hint: ربط معالجات انتهاء الجلسة والصيانة وإلزام تغيير كلمة المرور القادمة من الخادم
    ApiClient.instance.onUnauthorized = () {
      if (_user != null) logout();
    };
    ApiClient.instance.onMaintenance = () {
      if (!_isMaintenance) setMaintenanceMode(true);
    };
    ApiClient.instance.onPasswordChangeRequired = () {
      if (_user != null && !mustChangePassword) {
        updateUser({'mustChangePassword': true});
      }
    };

    _isLoading = false;
    notifyListeners();

    // فحص صحة النظام وهوية المؤسسة وتحديث صلاحيات المستخدم في الخلفية
    checkSystemStatus();
    if (_user != null) {
      refreshProfile();
      _startProfileRefresh();
    }
  }

  void _startProfileRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_profileRefreshInterval, (_) {
      refreshProfile();
      checkSystemStatus();
    });
  }

  Future<void> checkSystemStatus() async {
    try {
      final res = await ApiClient.instance.get('/system/status');
      if (res != null) {
        _isMaintenance = res['isMaintenance'] == true;
        _announcementBanner = res['announcementBanner'];
        _applyBranding(res);
        await _saveBranding();
        notifyListeners();
      }
    } catch (_) {}
  }

  void _applyBranding(Map<dynamic, dynamic> source) {
    String? nonEmpty(dynamic v) => v != null && v.toString().isNotEmpty ? v.toString() : null;
    _logoUrl = nonEmpty(source['logoUrl']) ?? _logoUrl;
    _institutionName = nonEmpty(source['institutionName']) ?? _institutionName;
    _appTitle = nonEmpty(source['appTitle']) ?? _appTitle;
    _activeYear = nonEmpty(source['activeYear']) ?? _activeYear;
  }

  Future<void> _saveBranding() async {
    final prefs = await SharedPreferences.getInstance();
    if (_logoUrl != null) await prefs.setString('branding_logo_url', _logoUrl!);
    await prefs.setString('branding_institution_name', _institutionName);
    await prefs.setString('branding_app_title', _appTitle);
    await prefs.setString('branding_active_year', _activeYear);
  }

  Future<void> login(String username, String password) async {
    final res = await ApiClient.instance.post('/auth/login', {
      'username': username,
      'password': password,
    });

    _user = Map<String, dynamic>.from(res['user']);

    final systemStatus = res['systemStatus'];
    if (systemStatus != null) {
      _announcementBanner = systemStatus['announcementBanner'];
      _isMaintenance = systemStatus['isMaintenance'] ?? false;
      _applyBranding(systemStatus);
    }

    await ApiClient.instance.setToken(res['token']);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, jsonEncode(_user));
    await _saveBranding();

    _startProfileRefresh();
    notifyListeners();
  }

  /// Hint: تحديث بيانات المستخدم وصلاحياته من الخادم (يُستدعى دورياً وعند الإقلاع)
  Future<void> refreshProfile() async {
    try {
      final res = await ApiClient.instance.get('/auth/me');
      if (res is Map && res['user'] != null) {
        await updateUser(Map<String, dynamic>.from(res['user']));
      }
    } catch (_) {}
  }

  /// Hint: تطبيق نتيجة تحديث الملف الشخصي؛ عند تغيير كلمة المرور يُرجع الخادم رمز جلسة جديداً
  Future<void> applyProfileUpdate(dynamic res) async {
    if (res is! Map) return;
    if (res['token'] is String) {
      await ApiClient.instance.setToken(res['token']);
    }
    if (res['user'] is Map) {
      await updateUser(Map<String, dynamic>.from(res['user']));
    }
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
    await _saveBranding();
    notifyListeners();
  }

  void setMaintenanceMode(bool isMaint) {
    _isMaintenance = isMaint;
    notifyListeners();
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
