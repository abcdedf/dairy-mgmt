// lib/core/app_config.dart
import 'auth_service.dart';

class AppConfig {
  /// Your WordPress site URL — no trailing slash.
  /// Set via: flutter run --dart-define=DFM_WP_BASE=https://your-domain.com
  static const String wpBase = String.fromEnvironment(
      'DFM_WP_BASE', defaultValue: 'https://your-domain.com');

  /// Base URL for all dairy API calls (our custom plugin namespace).
  static const String baseUrl = '$wpBase/wp-json/dairy/v1';

  /// Max app width on web — modelled after iPhone 14 (390 logical px).
  /// Change this to match a different device, e.g. 414 for iPhone 6+/7+/8+.
  static const double maxAppWidth = 390;

  /// Background colour shown outside the app column on wide screens.
  static const int surroundColorHex = 0xFFECEFF1; // Blue Grey 50

  /// Headers for every API call. Reads the current token from AuthService.
  static Future<Map<String, String>> get headers =>
      AuthService.instance.headers;
}
