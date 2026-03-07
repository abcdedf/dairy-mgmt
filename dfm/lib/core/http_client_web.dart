// lib/core/http_client_web.dart
// Web implementation using BrowserClient for cookie support
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client createWebClient() {
  final client = BrowserClient();
  client.withCredentials = true;
  return client;
}
