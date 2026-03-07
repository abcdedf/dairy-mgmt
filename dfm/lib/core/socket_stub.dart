// Web stub for SocketException — dart:io is not available on web.
// On web, network errors are thrown as different exception types.
class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => 'SocketException: \$message';
}
