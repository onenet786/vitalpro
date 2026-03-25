import 'dart:convert';

import 'package:http/http.dart' as http;

import 'report_models.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Future<String> fetchHealthMessage() async {
    final body = await _get('/health');
    return (body['message'] as String?) ?? 'API is reachable.';
  }

  Future<ReportingBootstrap> fetchReportingBootstrap() async {
    final body = await _get('/api/reporting/bootstrap');
    return ReportingBootstrap.fromJson(body);
  }

  Future<ReportingBootstrap> fetchAdminBootstrap(String adminPassword) async {
    final body = await _postJson('/api/admin/bootstrap', {
      'adminPassword': adminPassword,
    });
    return ReportingBootstrap.fromJson(body);
  }

  Future<MessageResult> verifyAdminPassword(String adminPassword) async {
    final body = await _postJson('/api/admin/verify', {
      'adminPassword': adminPassword,
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveCompanyProfile(
    CompanyProfile profile,
    String adminPassword,
  ) async {
    final body = await _postJson('/api/admin/settings', {
      ...profile.toJson(),
      'adminPassword': adminPassword,
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveServer(
    ReportingServer server,
    String adminPassword,
  ) async {
    final body = await _postJson('/api/admin/servers', {
      ...server.toJson(),
      'adminPassword': adminPassword,
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteServer(int id, String adminPassword) async {
    final body = await _deleteJson('/api/admin/servers/$id', {
      'adminPassword': adminPassword,
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> saveQuery(
    SavedQuery query,
    String adminPassword,
  ) async {
    final body = await _postJson('/api/admin/queries', {
      ...query.toJson(),
      'adminPassword': adminPassword,
    });
    return MessageResult.fromJson(body);
  }

  Future<MessageResult> deleteQuery(int id, String adminPassword) async {
    final body = await _deleteJson('/api/admin/queries/$id', {
      'adminPassword': adminPassword,
    });
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

    final response = await http.get(uri);
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
      headers: const {'Content-Type': 'application/json'},
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
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
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
