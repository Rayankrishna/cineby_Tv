import 'package:cineby_tv/models/auth_user.dart';
import 'package:cineby_tv/services/api_client.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_store.g.dart';

class AuthStore = _AuthStore with _$AuthStore;

abstract class _AuthStore with Store {
  @observable
  AuthUser? user;

  @observable
  String? avatarPath;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @computed
  bool get isAuthenticated => user != null;

  @action
  Future<void> bootstrap() async {
    await apiClient.loadTokens();
    apiClient.onAuthFailed = () {
      logout();
    };
    if (!apiClient.hasTokens) return;
    isLoading = true;
    try {
      final res = await apiClient.get('/me');
      if (res.statusCode == 200 && res.data is Map) {
        user = AuthUser.fromJson(Map<String, dynamic>.from(res.data));
        await _loadAvatar();
      } else {
        await apiClient.clearTokens();
      }
    } catch (_) {
      await apiClient.clearTokens();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> login({required String email, required String password}) async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await apiClient.post('/auth/login', body: {
        'email': email,
        'password': password,
      });
      return await _handleAuthResponse(res, 'Login failed');
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await apiClient.post('/auth/register', body: {
        'name': name,
        'email': email,
        'password': password,
      });
      return await _handleAuthResponse(res, 'Registration failed');
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  Future<bool> _handleAuthResponse(dynamic res, String fallbackErr) async {
    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = Map<String, dynamic>.from(res.data as Map);
      final access = data['accessToken'] as String?;
      final refresh = data['refreshToken'] as String?;
      final u = data['user'] as Map<String, dynamic>?;
      if (access != null && refresh != null && u != null) {
        await apiClient.saveTokens(access: access, refresh: refresh);
        user = AuthUser.fromJson(u);
        await _loadAvatar();
        return true;
      }
    }
    final msg = (res.data is Map) ? res.data['message']?.toString() : null;
    errorMessage = msg ?? fallbackErr;
    return false;
  }

  Future<void> _loadAvatar() async {
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    avatarPath = prefs.getString(kPrefAvatar(user!.id));
  }

  @action
  Future<void> setAvatarPath(String path) async {
    avatarPath = path;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefAvatar(user!.id), path);
    }
  }

  @action
  Future<void> logout() async {
    await apiClient.clearTokens();
    user = null;
    avatarPath = null;
    errorMessage = null;
  }
}
