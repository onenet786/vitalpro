import 'dart:convert';

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
    final body = await _postJson('/api/admin/settings', {
      ...profile.toJson(),
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveServer(ReportingServer server) async {
    final body = await _postJson('/api/admin/servers', {
      ...server.toJson(),
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteServer(int id) async {
    final body = await _deleteJson('/api/admin/servers/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveQuery(SavedQuery query) async {
    final body = await _postJson('/api/admin/queries', {
      ...query.toJson(),
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteQuery(int id) async {
    final body = await _deleteJson('/api/admin/queries/$id', const {});
    return MessageResult.fromJson(body);
  }

  Future<ReportResult> runReport({
    required int serverId,
    required int queryId,
  }) async {
    final body = await _postJson('/api/reporting/run', {
      'serverId': serverId,
      'queryId': queryId,
    });
    return ReportResult.fromJson(body);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri, headers: _buildHeaders());
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.post(
      uri,
      headers: _buildHeaders(includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = _buildUri(path);
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.delete(
      uri,
      headers: _buildHeaders(includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
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
