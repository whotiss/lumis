import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'models.dart';

enum AuthStatus { starting, loggedOut, needsConsent, ready, error }

/// Who is logged in, and whether they have agreed to the current consent text.
/// The login token is kept in Android's encrypted storage, never in plain preferences.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage() {
    api.onUnauthorized = () => _clear(notify: true);
  }

  static const _tokenKey = 'lumis_token';
  final Api api;
  final FlutterSecureStorage _storage;

  AuthStatus status = AuthStatus.starting;
  AppUser? user;
  String? errorMessage;

  Future<void> start() async {
    status = AuthStatus.starting;
    errorMessage = null;
    notifyListeners();
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    await refresh();
  }

  /// Reloads the account. Sends the person to the consent screen if the consent text changed.
  Future<void> refresh() async {
    try {
      _setUser(await api.me());
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _clear(notify: true);
      } else {
        status = AuthStatus.error;
        errorMessage = e.message;
        notifyListeners();
      }
    }
  }

  void _setUser(AppUser u) {
    user = u;
    status = u.consentCurrent ? AuthStatus.ready : AuthStatus.needsConsent;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> _saveToken(String token) async {
    api.token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> register({
    required String email,
    required String password,
    required String consentVersion,
    required bool consentStorage,
    required bool consentLocation,
  }) async {
    final token = await api.register(
      email: email,
      password: password,
      consentVersion: consentVersion,
      confirmAdult: true,
      consentStorage: consentStorage,
      consentLocation: consentLocation,
    );
    await _saveToken(token);
    _setUser(await api.me());
  }

  Future<void> login(String email, String password) async {
    await _saveToken(await api.login(email, password));
    _setUser(await api.me());
  }

  Future<void> acceptConsent(String version, {bool? storage, bool? location}) async {
    var u = await api.acceptConsent(version);
    if (storage != null || location != null) u = await api.updateConsent(storage: storage, location: location);
    _setUser(u);
  }

  Future<void> updateConsent({bool? storage, bool? location}) async =>
      _setUser(await api.updateConsent(storage: storage, location: location));

  Future<void> logout() => _clear(notify: true);

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await _clear(notify: true);
  }

  Future<void> _clear({required bool notify}) async {
    api.token = null;
    user = null;
    status = AuthStatus.loggedOut;
    await _storage.delete(key: _tokenKey);
    if (notify) notifyListeners();
  }
}
