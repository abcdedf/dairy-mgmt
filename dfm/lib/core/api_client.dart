// lib/core/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'socket_stub.dart' if (dart.library.io) 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'http_client_stub.dart'
    if (dart.library.html) 'http_client_web.dart';
import 'app_config.dart';
import 'auth_service.dart';

class ApiClient {
  static const _timeout = Duration(seconds: 15);

  /// Test-only override. When set, all static get/post/delete calls
  /// delegate to instance methods on this object instead of hitting HTTP.
  @visibleForTesting
  static ApiClient? testOverride;

  // ── HTTP client (BrowserClient on web for cookie support) ──

  static http.Client _client() => createWebClient();

  // ── Instance methods for test override ──────────────────

  /// Override in subclass (e.g. FakeApiClient) for test responses.
  Future<ApiResponse> instanceGet(String path) async =>
      throw UnimplementedError('Override instanceGet in test fake');

  /// Override in subclass for test responses.
  Future<ApiResponse> instancePost(String path, Map<String, dynamic> body) async =>
      throw UnimplementedError('Override instancePost in test fake');

  /// Override in subclass for test responses.
  Future<ApiResponse> instanceDelete(String path) async =>
      throw UnimplementedError('Override instanceDelete in test fake');

  // ── GET ────────────────────────────────────────────────

  static Future<ApiResponse> get(String path) async {
    if (testOverride != null) return testOverride!.instanceGet(path);
    final url = '${AppConfig.baseUrl}$path';
    try {
      final res = await _withRefreshRetry(
        'GET', url,
        (hdrs) => _client().get(Uri.parse(url), headers: hdrs).timeout(_timeout),
      );
      return res;
    } on SocketException {
      return _networkError('GET $url');
    } on TimeoutException {
      return _timeoutError('GET $url');
    } catch (e, st) {
      return _unexpectedError('GET $url', e, st);
    }
  }

  // ── POST ───────────────────────────────────────────────

  // TODO(feature): Implement offline write queue. When isNetworkError is true,
  // serialise the payload to a local database (Hive/SQLite) and replay when
  // connectivity is restored.
  static Future<ApiResponse> post(String path, Map<String, dynamic> body) async {
    if (testOverride != null) return testOverride!.instancePost(path, body);
    final url = '${AppConfig.baseUrl}$path';
    try {
      final encodedBody = jsonEncode(body);
      final res = await _withRefreshRetry(
        'POST', url,
        (hdrs) => _client().post(Uri.parse(url), headers: hdrs, body: encodedBody)
            .timeout(_timeout),
        body: body,
      );
      return res;
    } on SocketException {
      return _networkError('POST $url');
    } on TimeoutException {
      return _timeoutError('POST $url');
    } catch (e, st) {
      return _unexpectedError('POST $url', e, st);
    }
  }

  // ── DELETE ─────────────────────────────────────────────

  static Future<ApiResponse> delete(String path) async {
    if (testOverride != null) return testOverride!.instanceDelete(path);
    final url = '${AppConfig.baseUrl}$path';
    try {
      final res = await _withRefreshRetry(
        'DELETE', url,
        (hdrs) => _client().delete(Uri.parse(url), headers: hdrs).timeout(_timeout),
      );
      return res;
    } on SocketException {
      return _networkError('DELETE $url');
    } on TimeoutException {
      return _timeoutError('DELETE $url');
    } catch (e, st) {
      return _unexpectedError('DELETE $url', e, st);
    }
  }

  // ── Refresh-and-retry on 401 ─────────────────────────

  static Future<ApiResponse> _withRefreshRetry(
    String method,
    String url,
    Future<http.Response> Function(Map<String, String> headers) makeRequest, {
    Map<String, dynamic>? body,
  }) async {
    _logReq(method, url, body: body);
    final hdrs = await AppConfig.headers;
    final res = await makeRequest(hdrs);

    if (res.statusCode == 401) {
      debugPrint('[ApiClient] 401 on $method $url — attempting refresh');
      final refreshed = await AuthService.instance.tryRefresh();
      if (refreshed) {
        // Retry once with new token
        final hdrs2 = await AppConfig.headers;
        final res2 = await makeRequest(hdrs2);
        if (res2.statusCode != 401) return _process(method, url, res2);
      }
      // Refresh failed or still 401 — log out
      debugPrint('[ApiClient] refresh failed — logging out');
      _handleExpiredSession();
      return ApiResponse.error(
        statusCode: 401,
        message: 'Your session has expired. Please sign in again.',
      );
    }

    return _process(method, url, res);
  }

  // ── Response processing ────────────────────────────────

  static ApiResponse _process(String method, String url, http.Response res) {
    _logRes(method, url, res.statusCode, res.body);

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ApiClient] JSON parse error on $method $url — ${res.body}');
      return ApiResponse.error(
        statusCode: res.statusCode,
        message: 'Server returned an unexpected response.',
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300 && decoded['success'] == true) {
      return ApiResponse.success(statusCode: res.statusCode, data: decoded['data']);
    }

    final msg = decoded['message'] as String? ?? 'Request failed (${res.statusCode}).';
    return ApiResponse.error(statusCode: res.statusCode, message: msg);
  }

  // ── Session handling ───────────────────────────────────

  static void _handleExpiredSession() {
    AuthService.instance.logout();
    if (Get.currentRoute != '/login') Get.offAllNamed('/login');
  }

  // ── Error helpers ──────────────────────────────────────

  static ApiResponse _networkError(String context) {
    debugPrint('[ApiClient] SocketException on $context');
    return ApiResponse.error(
      statusCode: 0,
      message: 'Cannot reach server. Check your internet connection.',
    );
  }

  static ApiResponse _timeoutError(String context) {
    debugPrint('[ApiClient] Timeout on $context');
    return ApiResponse.error(
      statusCode: 0,
      message: 'Request timed out. Please retry.',
    );
  }

  static ApiResponse _unexpectedError(String context, Object e, StackTrace st) {
    debugPrint('[ApiClient] Unexpected error on $context: $e\n$st');
    return ApiResponse.error(
      statusCode: 0,
      message: 'An unexpected error occurred. Please try again.',
    );
  }

  // ── Logging (debug builds only) ────────────────────────

  static void _logReq(String method, String url, {Map<String, dynamic>? body}) {
    if (!kDebugMode) return;
    debugPrint('[ApiClient] → $method $url');
    if (body != null) debugPrint('[ApiClient]   body: ${jsonEncode(body)}');
  }

  static void _logRes(String method, String url, int status, String body) {
    if (!kDebugMode) return;
    final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    debugPrint('[ApiClient] ← $status $method $url  |  $snippet');
  }
}

// ── Response wrapper ───────────────────────────────────────

class ApiResponse {
  final bool    ok;
  final int     statusCode;
  final dynamic data;
  final String? message;

  const ApiResponse._({
    required this.ok,
    required this.statusCode,
    this.data,
    this.message,
  });

  factory ApiResponse.success({required int statusCode, dynamic data}) =>
      ApiResponse._(ok: true,  statusCode: statusCode, data: data);

  factory ApiResponse.error({required int statusCode, required String message}) =>
      ApiResponse._(ok: false, statusCode: statusCode, message: message);

  bool get isAuthError    => statusCode == 401;
  bool get isServerError  => statusCode >= 500;
  bool get isNetworkError => statusCode == 0;
}
