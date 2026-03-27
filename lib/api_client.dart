import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'report_models.dart';

class ApiClient {
  ApiClient({required this.baseUrl, this.authToken});

  final String baseUrl;
  final String? authToken;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final body = await _postJson('/api/auth/login', {
      'username': username,
      'password': password,
    });
    return AuthSession.fromJson(body);
  }

  Future<MessageResult> logout() async {
    final body = await _postJson('/api/auth/logout', const {});
    return MessageResult.fromJson(body);
  }

  Future<String> fetchHealthMessage() async {
    final body = await _get('/health');
    return (body['message'] as String?) ?? 'API is reachable.';
  }

  Future<ReportingBootstrap> fetchReportingBootstrap() async {
    final body = await _get('/api/reporting/bootstrap');
    return ReportingBootstrap.fromJson(body);
  }

  Future<ReportingBootstrap> fetchAdminBootstrap() async {
    final body = await _postJson('/api/admin/bootstrap', const {});
    return ReportingBootstrap.fromJson(body);
  }

  Future<MessageResult> saveCompanyProfile(CompanyProfile profile) async {
    final body = await _postJson('/api/admin/companies', {...profile.toJson()});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteCompany(int id) async {
    final body = await _deleteJson('/api/admin/companies/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveServer(ReportingServer server) async {
    final body = await _postJson('/api/admin/servers', {...server.toJson()});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteServer(int id) async {
    final body = await _deleteJson('/api/admin/servers/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveQuery(SavedQuery query) async {
    final body = await _postJson('/api/admin/queries', {...query.toJson()});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteQuery(int id) async {
    final body = await _deleteJson('/api/admin/queries/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveUser(AdminUserInput user) async {
    final body = await _postJson('/api/admin/users', user.toJson());
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteUser(int id) async {
    final body = await _deleteJson('/api/admin/users/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<ReportResult> runReport({
    required int serverId,
    required int queryId,
    Map<String, String> filters = const {},
  }) async {
    final body = await _postJson('/api/reporting/run', {
      'serverId': serverId,
      'queryId': queryId,
      'filters': filters,
    });
    return ReportResult.fromJson(body);
  }

  Future<List<String>> fetchReportFilterOptions({
    required int serverId,
    required int queryId,
    required String filterKey,
    Map<String, String> filters = const {},
  }) async {
    final body = await _postJson('/api/reporting/filter-options', {
      'serverId': serverId,
      'queryId': queryId,
      'filterKey': filterKey,
      'filters': filters,
    });
    return (body['options'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    return _sendRequest(uri, () => http.get(uri, headers: _buildHeaders()));
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    return _sendRequest(
      uri,
      () => http.post(
        uri,
        headers: _buildHeaders(includeJsonContentType: true),
        body: jsonEncode(payload),
      ),
    );
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    return _sendRequest(
      uri,
      () => http.delete(
        uri,
        headers: _buildHeaders(includeJsonContentType: true),
        body: jsonEncode(payload),
      ),
    );
  }

  Future<Map<String, dynamic>> _sendRequest(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request().timeout(const Duration(seconds: 20));
      return _decodeResponse(response);
    } on TimeoutException {
      throw Exception(
        'Connection to ${uri.toString()} timed out. Check API_BASE_URL, server status, and firewall rules.',
      );
    } on http.ClientException catch (error) {
      throw Exception(
        'Could not connect to ${uri.toString()}. ${error.message}. Verify API_BASE_URL and that the remote API is reachable from this device.',
      );
    }
  }

  Map<String, String> _buildHeaders({bool includeJsonContentType = false}) {
    final headers = <String, String>{};
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri? _buildUri(String path) {
    final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (normalizedBaseUrl.isEmpty) {
      return null;
    }
    return Uri.parse('$normalizedBaseUrl$path');
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(
        (body['message'] as String?) ??
            'Request failed with status ${response.statusCode}.',
      );
    }

    return body;
  }
}
