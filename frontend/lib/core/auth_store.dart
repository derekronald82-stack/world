import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

class AuthStore extends ChangeNotifier {
  final ApiClient api;
  AuthStore(this.api) {
    api.onAuthenticationFailure = () {
      _notice = 'Session expired. Please login again.';
      clearCredentials();
    };
  }

  static const _storage = FlutterSecureStorage();
  bool loading = true;
  String? username;
  String? role;
  String? _notice;

  bool get loggedIn => api.token != null;
  bool get isAdmin => role == 'admin';

  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  Future<void> restore() async {
    try {
      api.token = await _storage.read(key: 'token');
      username = await _storage.read(key: 'username');
      role = await _storage.read(key: 'role');
    } catch (_) {
      api.token = null;
      username = null;
      role = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String user, String pass) async {
    try {
      // Never send or retain an old token while starting a fresh login.
      await clearCredentials();
      final data = await api.login(user, pass);
      await _save(data);
    } catch (_) {
      await clearCredentials();
      rethrow;
    }
  }

  Future<void> register(String user, String pass) async {
    final data = await api.register(user, pass);
    await _save(data);
  }

  Future<void> _save(Map<String, dynamic> data) async {
    api.token = data['access_token'];
    username = data['user']['username'];
    role = data['user']['role'];
    await _storage.write(key: 'token', value: api.token);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'role', value: role);
    notifyListeners();
  }

  Future<void> logout() async {
    await clearCredentials();
  }

  Future<void> clearCredentials() async {
    api.token = null;
    username = null;
    role = null;
    await Future.wait([
      _storage.delete(key: 'token'),
      _storage.delete(key: 'username'),
      _storage.delete(key: 'role'),
    ]);
    notifyListeners();
  }
}
