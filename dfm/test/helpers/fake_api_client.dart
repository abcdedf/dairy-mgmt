import 'package:dairy_mgmt/core/api_client.dart';

/// A call record captured by [FakeApiClient].
class ApiCall {
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  const ApiCall(this.method, this.path, [this.body]);

  @override
  String toString() => '$method $path${body != null ? ' $body' : ''}';
}

/// In-memory fake for [ApiClient] used in controller unit tests.
///
/// Register canned responses via [onGet], [onPost], [onDelete].
/// All calls are recorded in [calls] for assertions.
class FakeApiClient extends ApiClient {
  final Map<String, ApiResponse> _getResponses = {};
  final Map<String, ApiResponse> _postResponses = {};
  final Map<String, ApiResponse> _deleteResponses = {};
  final List<ApiCall> calls = [];

  /// Register a canned GET response. [pathPrefix] is matched against the
  /// start of the request path, so `/vendors` matches `/vendors?location_id=1`.
  void onGet(String pathPrefix, ApiResponse response) =>
      _getResponses[pathPrefix] = response;

  /// Register a canned POST response.
  void onPost(String pathPrefix, ApiResponse response) =>
      _postResponses[pathPrefix] = response;

  /// Register a canned DELETE response.
  void onDelete(String pathPrefix, ApiResponse response) =>
      _deleteResponses[pathPrefix] = response;

  ApiResponse _match(Map<String, ApiResponse> map, String path) {
    // Try exact match first, then prefix match
    if (map.containsKey(path)) return map[path]!;
    for (final entry in map.entries) {
      if (path.startsWith(entry.key)) return entry.value;
    }
    return ApiResponse.error(
      statusCode: 404,
      message: 'FakeApiClient: no canned response for $path',
    );
  }

  @override
  Future<ApiResponse> instanceGet(String path) async {
    calls.add(ApiCall('GET', path));
    return _match(_getResponses, path);
  }

  @override
  Future<ApiResponse> instancePost(String path, Map<String, dynamic> body) async {
    calls.add(ApiCall('POST', path, body));
    return _match(_postResponses, path);
  }

  @override
  Future<ApiResponse> instanceDelete(String path) async {
    calls.add(ApiCall('DELETE', path));
    return _match(_deleteResponses, path);
  }

  /// Clear all canned responses and recorded calls.
  void reset() {
    _getResponses.clear();
    _postResponses.clear();
    _deleteResponses.clear();
    calls.clear();
  }
}
