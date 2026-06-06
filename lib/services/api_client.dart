import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

typedef OnAuthFailed = void Function();

class ApiClient {
  late final Dio _dio;
  String? _accessToken;
  String? _refreshToken;
  OnAuthFailed? onAuthFailed;
  bool _refreshing = false;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (_) => true,
    ));
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get hasTokens => _accessToken != null && _refreshToken != null;

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(kPrefAccessToken);
    _refreshToken = prefs.getString(kPrefRefreshToken);
  }

  Future<void> saveTokens({required String access, required String refresh}) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAccessToken, access);
    await prefs.setString(kPrefRefreshToken, refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefAccessToken);
    await prefs.remove(kPrefRefreshToken);
  }

  Map<String, dynamic> _authHeader(String path) {
    if (path.startsWith('/auth/')) return {};
    if (_accessToken == null) return {};
    return {'Authorization': 'Bearer $_accessToken'};
  }

  Future<Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool retried = false,
  }) async {
    final opts = Options(
      method: method,
      headers: _authHeader(path),
    );
    final res = await _dio.request(
      path,
      options: opts,
      queryParameters: query,
      data: body,
    );
    if (res.statusCode == 401 && !path.startsWith('/auth/') && !retried) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(method, path, query: query, body: body, retried: true);
      } else {
        onAuthFailed?.call();
      }
    }
    return res;
  }

  Future<bool> _tryRefresh() async {
    if (_refreshing) return false;
    if (_refreshToken == null) return false;
    _refreshing = true;
    try {
      final res = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': _refreshToken},
      );
      if (res.statusCode == 200 && res.data is Map && res.data['accessToken'] != null) {
        _accessToken = res.data['accessToken'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kPrefAccessToken, _accessToken!);
        return true;
      }
      await clearTokens();
      return false;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<Response> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<Response> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<Response> delete(String path, {Map<String, dynamic>? query}) =>
      _send('DELETE', path, query: query);
}

final ApiClient apiClient = ApiClient();
