// lib/core/auth_service.dart
//
// Unified JWT auth — all platforms send Authorization: Bearer <token>
//   Mobile — token persisted in secure keychain (flutter_secure_storage)
//   Web    — token held in memory (_token); httpOnly cookie used only for
//            silent refresh (server reads it on /auth/cookie-refresh)
//
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'socket_stub.dart' if (dart.library.io) 'dart:io' show SocketException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'http_client_stub.dart'
    if (dart.library.html) 'http_client_web.dart';
import 'app_config.dart';
import 'permission_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _kToken    = 'dairy_access_token';
  static const _kRefresh  = 'dairy_refresh_token';
  static const _kUsername = 'dairy_username';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // In-memory access token — set after login/refresh, cleared on logout.
  // Mobile also persists this in secure storage for auto-login across restarts.
  String? _token;


  DairyUser? currentUser;

  bool get isLoggedIn => _token != null;

  // All platforms send the access token as Authorization: Bearer.
  Future<Map<String, String>> get headers async => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ── Auto-login on app start ─────────────────────────────

  Future<bool> tryAutoLogin() async {
    if (kIsWeb) {
      // Web has no persistent token storage — attempt a silent cookie-refresh
      // to get a new access token from the server using the httpOnly refresh
      // cookie set during the last login.
      final refreshed = await _tryRefresh();
      if (!refreshed) return false;
      return await _verifyAndLoadPermissions(autoLogin: true);
    }

    // Mobile: read persisted token from secure storage
    _token = await _storage.read(key: _kToken);
    final uname = await _storage.read(key: _kUsername);
    if (_token == null) return false;

    final ok = await _verifyAndLoadPermissions(autoLogin: true);
    if (ok) {
      currentUser = DairyUser(username: uname ?? '');
      debugPrint('[AuthService] auto-login OK for $uname');
      return true;
    }

    debugPrint('[AuthService] auto-login: token invalid, trying refresh');
    final refreshed = await _tryRefresh();
    if (refreshed) {
      currentUser = DairyUser(username: uname ?? '');
      return true;
    }

    debugPrint('[AuthService] auto-login failed');
    await _clearMobile();
    return false;
  }

  // ── Login ────────────────────────────────────────────────

  Future<AuthResult> login(String username, String password) async {
    const url = '${AppConfig.baseUrl}/auth/login';
    debugPrint('[AuthService] POST $url (web=$kIsWeb)');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      final res = await _client().post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({'username': username.trim(), 'password': password}),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[AuthService] login response ${res.statusCode}');

      if (res.statusCode == 301 || res.statusCode == 302) {
        final location = res.headers['location'] ?? '(unknown)';
        String hint = '';
        try {
          final uri = Uri.parse(location);
          hint = '${uri.scheme}://${uri.host}';
        } catch (_) { hint = location; }
        return AuthResult.failure(
          'Server redirected to a different URL.\n\n'
          'Update wpBase in app_config.dart to:\n$hint',
        );
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;

        // Store access token in memory on all platforms.
        // Mobile also persists it (and the refresh token) to secure storage.
        _token = data['token'] as String?;
        if (!kIsWeb) {
          final refreshToken = data['refresh_token'] as String?;
          await _storage.write(key: _kToken,    value: _token);
          await _storage.write(key: _kRefresh,  value: refreshToken);
          await _storage.write(key: _kUsername, value: username.trim());
        }
        // Web: refresh token lives in the httpOnly cookie set by the server.

        final loaded = await _verifyAndLoadPermissions();
        if (!loaded) {
          if (!kIsWeb) await _clearMobile();
          return AuthResult.failure(
              'Login succeeded but failed to load permissions. Please try again.');
        }

        final userData = data['user'] as Map<String, dynamic>?;
        currentUser = DairyUser(
          username:    username.trim(),
          email:       userData?['email']        as String?,
          displayName: userData?['display_name'] as String?,
        );
        debugPrint('[AuthService] login OK');
        return AuthResult.success(currentUser!);
      }

      if (res.statusCode == 403 || res.statusCode == 401) {
        return AuthResult.failure('Incorrect username or password.');
      }
      return AuthResult.failure(
          (body['message'] as String?) ?? 'Login failed (${res.statusCode}).');

    } on SocketException catch (e) {
      debugPrint('[AuthService] login SocketException: $e');
      return AuthResult.failure('Cannot reach server.\nCheck your internet connection.');
    } on TimeoutException catch (e) {
      debugPrint('[AuthService] login TimeoutException: $e');
      return AuthResult.failure('Server did not respond. Please try again.');
    } catch (e, st) {
      debugPrint('[AuthService] login unexpected: $e\n$st');
      return AuthResult.failure('Unexpected error. Please try again.');
    }
  }

  // ── Logout ───────────────────────────────────────────────

  Future<void> logout() async {
    debugPrint('[AuthService] logout for ${currentUser?.username}');
    // Tell server to revoke token/clear cookies
    try {
      await _client().post(
        Uri.parse('${AppConfig.baseUrl}/auth/logout'),
        headers: await headers,
      ).timeout(const Duration(seconds: 5));
    } catch (_) { /* best effort */ }

    currentUser = null;
    _token = null;
    PermissionService.instance.clear();
    if (!kIsWeb) await _clearMobile();
  }

  // ── Silent token refresh ─────────────────────────────────

  /// Public hook for ApiClient — allows a single refresh attempt
  /// before logging out on a 401 response.
  Future<bool> tryRefresh() => _tryRefresh();

  Future<bool> _tryRefresh() async {
    try {
      if (kIsWeb) {
        // Web: server reads the httpOnly refresh cookie automatically and
        // returns a new access token in the response body.
        final res = await _client().post(
          Uri.parse('${AppConfig.baseUrl}/auth/cookie-refresh'),
          headers: const {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body)['data'] as Map<String, dynamic>;
          _token = data['token'] as String?;
          return _token != null;
        }
        return false;
      } else {
        // Mobile: send refresh token in body
        final refreshToken = await _storage.read(key: _kRefresh);
        if (refreshToken == null) return false;
        final res = await http.post(
          Uri.parse('${AppConfig.baseUrl}/auth/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body)['data'] as Map<String, dynamic>;
          _token = data['token'] as String;
          await _storage.write(key: _kToken, value: _token);
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('[AuthService] refresh error: $e');
      return false;
    }
  }

  // ── Verify token + load permissions ──────────────────────

  Future<bool> _verifyAndLoadPermissions({bool autoLogin = false, bool isRetry = false}) async {
    try {
      final hdrs = <String, String>{
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

      final res = await _client().get(
        Uri.parse('${AppConfig.baseUrl}/me'),
        headers: hdrs,
      ).timeout(const Duration(seconds: 10));

      debugPrint('[AuthService] /me → ${res.statusCode}');

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          final permissions =
              body['data']['permissions'] as Map<String, dynamic>?;
          if (permissions != null) {
            PermissionService.instance.load(permissions);
          }
          // On web, populate currentUser from /me response if not set
          if (kIsWeb && currentUser == null) {
            final userData = body['data']['user'] as Map<String, dynamic>?;
            if (userData != null) {
              currentUser = DairyUser(
                username:    userData['username']     as String? ?? '',
                email:       userData['email']        as String?,
                displayName: userData['display_name'] as String?,
              );
            }
          }
          return true;
        }
      }

      if (res.statusCode == 401) {
        // Never retry more than once — prevents infinite loop
        if (autoLogin || isRetry) {
          debugPrint('[AuthService] 401 no further retries — clearing credentials');
          if (!kIsWeb) await _clearMobile();
          _token = null;
          return false;
        }
        debugPrint('[AuthService] /me 401 — trying refresh');
        final refreshed = await _tryRefresh();
        if (!refreshed) {
          if (!kIsWeb) await _clearMobile();
          _token = null;
          return false;
        }
        return await _verifyAndLoadPermissions(autoLogin: autoLogin, isRetry: true);
      }

      return false;

    } on SocketException {
      debugPrint('[AuthService] /me SocketException — assuming valid (offline)');
      return _token != null; // offline grace
    } on TimeoutException {
      debugPrint('[AuthService] /me timeout — assuming valid (offline)');
      return _token != null;
    } catch (e, st) {
      debugPrint('[AuthService] /me unexpected: $e\n$st');
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────

  // Returns a cookie-aware client on web, standard client on mobile
  http.Client _client() => createWebClient();

  Future<void> _clearMobile() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUsername);
  }
}

// ── Models ───────────────────────────────────────────────────

class DairyUser {
  final String  username;
  final String? email;
  final String? displayName;

  const DairyUser({required this.username, this.email, this.displayName});

  String get label =>
      (displayName?.isNotEmpty == true) ? displayName! : username;
}

class AuthResult {
  final bool       success;
  final DairyUser? user;
  final String?    error;
  const AuthResult._({required this.success, this.user, this.error});
  factory AuthResult.success(DairyUser u) => AuthResult._(success: true,  user: u);
  factory AuthResult.failure(String e)    => AuthResult._(success: false, error: e);
}
