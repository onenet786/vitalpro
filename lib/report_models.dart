enum AuthenticationMode { windows, sqlServer }

enum UserRole { admin, reporting }

enum QueryFilterType { text, number, date }

UserRole _parseUserRole(dynamic value) {
  return '${value ?? ''}'.toLowerCase() == 'admin'
      ? UserRole.admin
      : UserRole.reporting;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
  });

  final int id;
  final String username;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}') ?? 0,
      username: (json['username'] ?? '').toString(),
      role: _parseUserRole(json['role']),
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
  });

  final String token;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: (json['token'] ?? '').toString(),
      user: AppUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
      ),
    );
  }
}

class CompanyProfile {
  const CompanyProfile({
    this.companyName = '',
    this.companyAddress = '',
    this.companyLogoUrl = '',
  });

  final String companyName;
  final String companyAddress;
  final String companyLogoUrl;

  factory CompanyProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CompanyProfile();
    }

    return CompanyProfile(
      companyName:
          (json['companyName'] ?? json['company_name'] ?? '').toString(),
      companyAddress:
          (json['companyAddress'] ?? json['company_address'] ?? '').toString(),
      companyLogoUrl:
          (json['companyLogoUrl'] ?? json['company_logo_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'companyName': companyName,
      'companyAddress': companyAddress,
      'companyLogoUrl': companyLogoUrl,
    };
  }

  CompanyProfile copyWith({
    String? companyName,
    String? companyAddress,
    String? companyLogoUrl,
  }) {
    return CompanyProfile(
      companyName: companyName ?? this.companyName,
      companyAddress: companyAddress ?? this.companyAddress,
      companyLogoUrl: companyLogoUrl ?? this.companyLogoUrl,
    );
  }
}

class ReportingServer {
  const ReportingServer({
    this.id,
    this.name = '',
    this.host = '',
    this.port = 1433,
    this.databaseName = '',
    this.authenticationMode = AuthenticationMode.sqlServer,
    this.username = '',
    this.password = '',
  });

  final int? id;
  final String name;
  final String host;
  final int port;
  final String databaseName;
  final AuthenticationMode authenticationMode;
  final String username;
  final String password;

  String get label => name.trim().isEmpty ? databaseName : name;

  factory ReportingServer.fromJson(Map<String, dynamic> json) {
    final authenticationModeValue =
        (json['authenticationMode'] ?? json['authentication_mode'] ?? 'sqlServer')
            .toString();

    return ReportingServer(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      name: (json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse('${json['port'] ?? ''}') ?? 1433,
      databaseName:
          (json['databaseName'] ?? json['database_name'] ?? '').toString(),
      authenticationMode: authenticationModeValue == 'windows'
          ? AuthenticationMode.windows
          : AuthenticationMode.sqlServer,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'databaseName': databaseName,
      'authenticationMode': authenticationMode == AuthenticationMode.windows
          ? 'windows'
          : 'sqlServer',
      'username': username,
      'password': password,
    };
  }

  ReportingServer copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? databaseName,
    AuthenticationMode? authenticationMode,
    String? username,
    String? password,
  }) {
    return ReportingServer(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      databaseName: databaseName ?? this.databaseName,
      authenticationMode: authenticationMode ?? this.authenticationMode,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

class SavedQuery {
  const SavedQuery({
    this.id,
    this.queryName = '',
    this.queryText = '',
    this.showChartByDefault = false,
    this.filters = const [],
  });

  final int? id;
  final String queryName;
  final String queryText;
  final bool showChartByDefault;
  final List<QueryFilterDefinition> filters;

  factory SavedQuery.fromJson(Map<String, dynamic> json) {
    return SavedQuery(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      queryName: (json['queryName'] ?? json['query_name'] ?? '').toString(),
      queryText: (json['queryText'] ?? json['query_text'] ?? '').toString(),
      showChartByDefault:
          json['showChartByDefault'] == true ||
          json['show_chart_default'] == true ||
          json['show_chart_default'] == 1 ||
          '${json['showChartByDefault'] ?? json['show_chart_default'] ?? ''}' ==
              '1',
      filters: (json['filters'] as List<dynamic>? ?? const [])
          .map(
            (item) => QueryFilterDefinition.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'queryName': queryName,
      'queryText': queryText,
      'showChartByDefault': showChartByDefault,
      'filters': filters.map((filter) => filter.toJson()).toList(),
    };
  }

  SavedQuery copyWith({
    int? id,
    String? queryName,
    String? queryText,
    bool? showChartByDefault,
    List<QueryFilterDefinition>? filters,
  }) {
    return SavedQuery(
      id: id ?? this.id,
      queryName: queryName ?? this.queryName,
      queryText: queryText ?? this.queryText,
      showChartByDefault: showChartByDefault ?? this.showChartByDefault,
      filters: filters ?? this.filters,
    );
  }
}

class QueryFilterDefinition {
  const QueryFilterDefinition({
    required this.key,
    required this.label,
    this.type = QueryFilterType.text,
    this.isRequired = false,
    this.placeholder = '',
    this.defaultValue = '',
  });

  final String key;
  final String label;
  final QueryFilterType type;
  final bool isRequired;
  final String placeholder;
  final String defaultValue;

  factory QueryFilterDefinition.fromJson(Map<String, dynamic> json) {
    final typeValue = (json['type'] ?? '').toString().toLowerCase();
    final type = switch (typeValue) {
      'number' => QueryFilterType.number,
      'date' => QueryFilterType.date,
      _ => QueryFilterType.text,
    };

    return QueryFilterDefinition(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      type: type,
      isRequired:
          json['isRequired'] == true ||
          json['is_required'] == true ||
          json['is_required'] == 1 ||
          '${json['isRequired'] ?? json['is_required'] ?? ''}' == '1',
      placeholder: (json['placeholder'] ?? '').toString(),
      defaultValue: (json['defaultValue'] ?? json['default_value'] ?? '')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type.name,
      'isRequired': isRequired,
      'placeholder': placeholder,
      'defaultValue': defaultValue,
    };
  }

  QueryFilterDefinition copyWith({
    String? key,
    String? label,
    QueryFilterType? type,
    bool? isRequired,
    String? placeholder,
    String? defaultValue,
  }) {
    return QueryFilterDefinition(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      isRequired: isRequired ?? this.isRequired,
      placeholder: placeholder ?? this.placeholder,
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }
}

class ReportingBootstrap {
  const ReportingBootstrap({
    required this.companyProfile,
    required this.servers,
    required this.queries,
  });

  final CompanyProfile companyProfile;
  final List<ReportingServer> servers;
  final List<SavedQuery> queries;

  factory ReportingBootstrap.fromJson(Map<String, dynamic> json) {
    return ReportingBootstrap(
      companyProfile: CompanyProfile.fromJson(
        json['companyProfile'] as Map<String, dynamic>?,
      ),
      servers: (json['servers'] as List<dynamic>? ?? const [])
          .map((item) => ReportingServer.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      queries: (json['queries'] as List<dynamic>? ?? const [])
          .map((item) => SavedQuery.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class MessageResult {
  const MessageResult({required this.success, required this.message});

  final bool success;
  final String message;

  factory MessageResult.fromJson(Map<String, dynamic> json) {
    return MessageResult(
      success: json['success'] == true,
      message: (json['message'] ?? 'Unexpected API response.').toString(),
    );
  }
}

class ReportResult {
  const ReportResult({
    required this.serverName,
    required this.queryName,
    required this.executedAt,
    required this.columns,
    required this.rows,
    required this.rowCount,
  });

  final String serverName;
  final String queryName;
  final String executedAt;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int rowCount;

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      serverName: (json['serverName'] ?? json['server_name'] ?? '').toString(),
      queryName: (json['queryName'] ?? json['query_name'] ?? '').toString(),
      executedAt: (json['executedAt'] ?? json['executed_at'] ?? '').toString(),
      columns: (json['columns'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      rows: (json['rows'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      rowCount: json['rowCount'] is int
          ? json['rowCount'] as int
          : int.tryParse('${json['rowCount'] ?? ''}') ??
                (json['rows'] as List<dynamic>? ?? const []).length,
    );
  }
}
