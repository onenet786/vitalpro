import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'report_models.dart';
import 'vitalpro_logo.dart';

enum HomeMode { reporting, admin }

enum AdminPanelSection { dashboard, company, users, servers, queries }

class ReportingHomePage extends StatefulWidget {
  const ReportingHomePage({
    super.key,
    required this.session,
    required this.onLogout,
    required this.homeMode,
  });

  final AuthSession session;
  final VoidCallback onLogout;
  final HomeMode homeMode;

  @override
  State<ReportingHomePage> createState() => _ReportingHomePageState();
}

class _ReportingHomePageState extends State<ReportingHomePage> {
  static const _defaultServerPreferenceKey = 'default_reporting_server_id';

  final _companyNameController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyLogoController = TextEditingController();
  final _serverNameController = TextEditingController();
  final _serverHostController = TextEditingController();
  final _serverPortController = TextEditingController(text: '1433');
  final _serverDatabaseController = TextEditingController();
  final _serverUsernameController = TextEditingController();
  final _serverPasswordController = TextEditingController();
  final _queryNameController = TextEditingController();
  final _queryTextController = TextEditingController();
  final _userUsernameController = TextEditingController();
  final _userPasswordController = TextEditingController();

  final Map<String, TextEditingController> _reportFilterControllers = {};
  List<_EditableQueryFilter> _queryFilters = [];
  AuthenticationMode _serverAuthenticationMode = AuthenticationMode.sqlServer;
  UserRole _userRole = UserRole.reporting;
  bool _showChart = false;
  bool _isLoading = true;
  bool _isBusy = false;
  bool _isSqlPasswordVisible = false;
  bool _isUserPasswordVisible = false;
  bool _showQueryChartByDefault = false;
  bool _userIsActive = true;
  AdminPanelSection _adminSection = AdminPanelSection.dashboard;
  String? _statusMessage;
  String? _healthMessage;
  int? _selectedServerId;
  int? _selectedQueryId;
  int? _editingServerId;
  int? _editingQueryId;
  int? _editingUserId;
  CompanyProfile _companyProfile = const CompanyProfile();
  List<ReportingServer> _servers = const [];
  List<SavedQuery> _queries = const [];
  List<AppUser> _users = const [];
  ReportResult? _reportResult;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  bool get _isAdminUser => widget.homeMode == HomeMode.admin;

  ApiClient get _apiClient =>
      ApiClient(baseUrl: _apiBaseUrl, authToken: widget.session.token);

  ReportingServer? get _selectedServer {
    for (final server in _servers) {
      if (server.id == _selectedServerId) {
        return server;
      }
    }
    return null;
  }

  SavedQuery? get _selectedQuery {
    for (final query in _queries) {
      if (query.id == _selectedQueryId) {
        return query;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadBootstrap();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyAddressController.dispose();
    _companyLogoController.dispose();
    _serverNameController.dispose();
    _serverHostController.dispose();
    _serverPortController.dispose();
    _serverDatabaseController.dispose();
    _serverUsernameController.dispose();
    _serverPasswordController.dispose();
    _queryNameController.dispose();
    _queryTextController.dispose();
    _userUsernameController.dispose();
    _userPasswordController.dispose();
    _disposeQueryFilters(_queryFilters);
    for (final controller in _reportFilterControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBootstrap() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final healthMessage = await _apiClient.fetchHealthMessage();
      final bootstrap = _isAdminUser
          ? await _apiClient.fetchAdminBootstrap()
          : await _apiClient.fetchReportingBootstrap();
      final preferences = await SharedPreferences.getInstance();
      final storedDefaultServerId = preferences.getInt(
        _defaultServerPreferenceKey,
      );
      final nextServerId = _resolveServerSelection(
        bootstrap.servers,
        storedDefaultServerId,
      );
      final nextQueryId = _resolveQuerySelection(bootstrap.queries);
      final selectedQuery = _findQueryById(bootstrap.queries, nextQueryId);
      _syncReportFilterControllers(selectedQuery);

      if (!mounted) {
        return;
      }

      setState(() {
        _companyProfile = bootstrap.companyProfile;
        _servers = bootstrap.servers;
        _queries = bootstrap.queries;
        _users = bootstrap.users;
        _healthMessage = healthMessage;
        _selectedServerId = nextServerId;
        _selectedQueryId = nextQueryId;
        _showChart = selectedQuery?.showChartByDefault ?? false;
        _statusMessage = bootstrap.servers.isEmpty || bootstrap.queries.isEmpty
            ? (_isAdminUser
                  ? 'Add at least one SQL server and one saved query from Admin before running reports.'
                  : 'Ask an admin to add at least one SQL server and one saved query before running reports.')
            : 'Configuration loaded from MySQL.';
        _isLoading = false;
      });

      _companyNameController.text = _companyProfile.companyName;
      _companyAddressController.text = _companyProfile.companyAddress;
      _companyLogoController.text = _companyProfile.companyLogoUrl;
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage =
            'Could not load reporting configuration. Details: $error';
      });
    }
  }

  int? _resolveServerSelection(
    List<ReportingServer> servers,
    int? storedDefaultServerId,
  ) {
    final currentId = _selectedServerId;
    if (currentId != null && servers.any((server) => server.id == currentId)) {
      return currentId;
    }

    if (storedDefaultServerId != null &&
        servers.any((server) => server.id == storedDefaultServerId)) {
      return storedDefaultServerId;
    }

    return servers.isNotEmpty ? servers.first.id : null;
  }

  int? _resolveQuerySelection(List<SavedQuery> queries) {
    final currentId = _selectedQueryId;
    if (currentId != null && queries.any((query) => query.id == currentId)) {
      return currentId;
    }

    return queries.isNotEmpty ? queries.first.id : null;
  }

  SavedQuery? _findQueryById(List<SavedQuery> queries, int? id) {
    if (id == null) {
      return null;
    }

    for (final query in queries) {
      if (query.id == id) {
        return query;
      }
    }

    return null;
  }

  Future<void> _setDefaultServer() async {
    final serverId = _selectedServerId;
    if (serverId == null) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_defaultServerPreferenceKey, serverId);
    if (!mounted) {
      return;
    }

    _showSnack('Default reporting server updated.');
  }

  void _onQueryChanged(int? queryId) {
    final query = _findQueryById(_queries, queryId);
    _syncReportFilterControllers(query);
    setState(() {
      _selectedQueryId = queryId;
      _showChart = query?.showChartByDefault ?? false;
      _reportResult = null;
    });
  }

  void _syncReportFilterControllers(SavedQuery? query) {
    final activeKeys = <String>{};
    for (final filter in query?.filters ?? const <QueryFilterDefinition>[]) {
      activeKeys.add(filter.key);
      final controller = _reportFilterControllers.putIfAbsent(
        filter.key,
        () => TextEditingController(),
      );
      if (controller.text.trim().isEmpty &&
          filter.defaultValue.trim().isNotEmpty) {
        controller.text = filter.defaultValue.trim();
      }
    }

    final staleKeys = _reportFilterControllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _reportFilterControllers.remove(key)?.dispose();
    }
  }

  Map<String, String> _collectReportFilters(SavedQuery? query) {
    final values = <String, String>{};
    if (query == null) {
      return values;
    }

    for (final filter in query.filters) {
      final text = _reportFilterControllers[filter.key]?.text.trim() ?? '';
      if (text.isNotEmpty) {
        values[filter.key] = text;
      }
    }
    return values;
  }

  Future<void> _runReport() async {
    final serverId = _selectedServerId;
    final queryId = _selectedQueryId;
    final query = _selectedQuery;
    if (serverId == null || queryId == null) {
      _showSnack('Select one SQL server and one saved query first.');
      return;
    }

    for (final filter in query?.filters ?? const <QueryFilterDefinition>[]) {
      final value = _reportFilterControllers[filter.key]?.text.trim() ?? '';
      if (filter.isRequired && value.isEmpty) {
        _showSnack('${filter.label} is required.');
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Running report query...';
    });

    try {
      final result = await _apiClient.runReport(
        serverId: serverId,
        queryId: queryId,
        filters: _collectReportFilters(query),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _reportResult = result;
        _isBusy = false;
        _statusMessage = 'Report returned ${result.rowCount} row(s).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = 'Could not run report. Details: $error';
      });
    }
  }

  Future<void> _saveCompanyProfile() async {
    setState(() {
      _isBusy = true;
      _statusMessage = 'Saving company profile...';
    });

    try {
      final result = await _apiClient.saveCompanyProfile(
        CompanyProfile(
          companyName: _companyNameController.text.trim(),
          companyAddress: _companyAddressController.text.trim(),
          companyLogoUrl: _companyLogoController.text.trim(),
        ),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not save company profile. Details: $error');
    }
  }

  Future<void> _saveServer() async {
    if (_serverNameController.text.trim().isEmpty ||
        _serverHostController.text.trim().isEmpty ||
        _serverDatabaseController.text.trim().isEmpty) {
      _showSnack('Server name, host, and database are required.');
      return;
    }

    if (_serverAuthenticationMode == AuthenticationMode.sqlServer &&
        (_serverUsernameController.text.trim().isEmpty ||
            _serverPasswordController.text.isEmpty)) {
      _showSnack('Username and password are required for SQL login.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingServerId == null
          ? 'Saving SQL server...'
          : 'Updating SQL server...';
    });

    try {
      final result = await _apiClient.saveServer(
        ReportingServer(
          id: _editingServerId,
          name: _serverNameController.text.trim(),
          host: _serverHostController.text.trim(),
          port: int.tryParse(_serverPortController.text.trim()) ?? 1433,
          databaseName: _serverDatabaseController.text.trim(),
          authenticationMode: _serverAuthenticationMode,
          username: _serverUsernameController.text.trim(),
          password: _serverPasswordController.text,
        ),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      _resetServerForm();
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not save SQL server. Details: $error');
    }
  }

  Future<void> _deleteServer(ReportingServer server) async {
    if (server.id == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete SQL Server'),
          content: Text('Delete ${server.label} from the saved server list?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Deleting SQL server...';
    });

    try {
      final result = await _apiClient.deleteServer(server.id!);
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      if (_editingServerId == server.id) {
        _resetServerForm();
      }
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not delete SQL server. Details: $error');
    }
  }

  Future<void> _saveQuery() async {
    if (_queryNameController.text.trim().isEmpty ||
        _queryTextController.text.trim().isEmpty) {
      _showSnack('Query name and SQL query text are required.');
      return;
    }

    final filterDefinitions = _queryFilters
        .map((filter) => filter.toDefinition())
        .toList(growable: false);
    final seenKeys = <String>{};
    for (final filter in filterDefinitions) {
      if (filter.key.isEmpty || filter.label.isEmpty) {
        _showSnack('Each query filter needs both a key and a label.');
        return;
      }
      if (!seenKeys.add(filter.key.toLowerCase())) {
        _showSnack('Each query filter key must be unique.');
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingQueryId == null
          ? 'Saving report query...'
          : 'Updating report query...';
    });

    try {
      final result = await _apiClient.saveQuery(
        SavedQuery(
          id: _editingQueryId,
          queryName: _queryNameController.text.trim(),
          queryText: _queryTextController.text.trim(),
          showChartByDefault: _showQueryChartByDefault,
          filters: filterDefinitions,
        ),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      _resetQueryForm();
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not save report query. Details: $error');
    }
  }

  Future<void> _deleteQuery(SavedQuery query) async {
    if (query.id == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Query'),
          content: Text('Delete ${query.queryName} from saved report queries?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Deleting report query...';
    });

    try {
      final result = await _apiClient.deleteQuery(query.id!);
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      if (_editingQueryId == query.id) {
        _resetQueryForm();
      }
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not delete report query. Details: $error');
    }
  }

  Future<void> _saveUser() async {
    if (_userUsernameController.text.trim().isEmpty) {
      _showSnack('Username is required.');
      return;
    }

    if (_editingUserId == null && _userPasswordController.text.isEmpty) {
      _showSnack('Password is required for a new user.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingUserId == null
          ? 'Creating user...'
          : 'Updating user...';
    });

    try {
      final result = await _apiClient.saveUser(
        AdminUserInput(
          id: _editingUserId,
          username: _userUsernameController.text.trim(),
          password: _userPasswordController.text,
          role: _userRole,
          isActive: _userIsActive,
        ),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      _resetUserForm();
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not save user. Details: $error');
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete User'),
          content: Text('Delete ${user.username} from app users?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Deleting user...';
    });

    try {
      final result = await _apiClient.deleteUser(user.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      if (_editingUserId == user.id) {
        _resetUserForm();
      }
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure('Could not delete user. Details: $error');
    }
  }

  void _loadServerForEditing(ReportingServer server) {
    _serverNameController.text = server.name;
    _serverHostController.text = server.host;
    _serverPortController.text = server.port.toString();
    _serverDatabaseController.text = server.databaseName;
    _serverUsernameController.text = server.username;
    _serverPasswordController.text = server.password;
    setState(() {
      _editingServerId = server.id;
      _serverAuthenticationMode = server.authenticationMode;
      _isSqlPasswordVisible = false;
    });
  }

  void _loadQueryForEditing(SavedQuery query) {
    _queryNameController.text = query.queryName;
    _queryTextController.text = query.queryText;
    _disposeQueryFilters(_queryFilters);
    setState(() {
      _editingQueryId = query.id;
      _showQueryChartByDefault = query.showChartByDefault;
      _queryFilters = query.filters
          .map((filter) => _EditableQueryFilter.fromDefinition(filter))
          .toList();
    });
  }

  void _loadUserForEditing(AppUser user) {
    _userUsernameController.text = user.username;
    _userPasswordController.clear();
    setState(() {
      _editingUserId = user.id;
      _userRole = user.role;
      _userIsActive = user.isActive;
      _isUserPasswordVisible = false;
    });
  }

  void _resetServerForm() {
    _serverNameController.clear();
    _serverHostController.clear();
    _serverPortController.text = '1433';
    _serverDatabaseController.clear();
    _serverUsernameController.clear();
    _serverPasswordController.clear();
    setState(() {
      _editingServerId = null;
      _serverAuthenticationMode = AuthenticationMode.sqlServer;
      _isSqlPasswordVisible = false;
    });
  }

  void _resetQueryForm() {
    _queryNameController.clear();
    _queryTextController.clear();
    _disposeQueryFilters(_queryFilters);
    setState(() {
      _editingQueryId = null;
      _showQueryChartByDefault = false;
      _queryFilters = [];
    });
  }

  void _resetUserForm() {
    _userUsernameController.clear();
    _userPasswordController.clear();
    setState(() {
      _editingUserId = null;
      _userRole = UserRole.reporting;
      _userIsActive = true;
      _isUserPasswordVisible = false;
    });
  }

  void _addQueryFilter() {
    setState(() {
      _queryFilters = [
        ..._queryFilters,
        _EditableQueryFilter(
          key: 'DocumentDate',
          label: 'Document Date',
          type: QueryFilterType.date,
          isRequired: false,
          placeholder: 'dd-MMM-yyyy',
        ),
      ];
    });
  }

  void _removeQueryFilter(int index) {
    final removed = _queryFilters[index];
    setState(() {
      _queryFilters = List<_EditableQueryFilter>.from(_queryFilters)
        ..removeAt(index);
    });
    removed.dispose();
  }

  void _disposeQueryFilters(List<_EditableQueryFilter> filters) {
    for (final filter in filters) {
      filter.dispose();
    }
  }

  Future<void> _pickDateFilterValue(QueryFilterDefinition filter) async {
    final controller = _reportFilterControllers[filter.key];
    if (controller == null) {
      return;
    }

    final now = DateTime.now();
    final currentValue = controller.text.trim();
    final initialDate = _parseQueryDate(currentValue) ?? now;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selectedDate == null) {
      return;
    }

    controller.text = _formatQueryDate(selectedDate);
    setState(() {});
  }

  DateTime? _parseQueryDate(String value) {
    final match = RegExp(r'^(\d{2})-([A-Za-z]{3})-(\d{4})$').firstMatch(value);
    if (match == null) {
      return null;
    }

    final day = int.tryParse(match.group(1)!);
    final month = _monthIndex(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) {
      return null;
    }

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  String _formatQueryDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = _monthLabel(date.month);
    return '$day-$month-${date.year}';
  }

  int? _monthIndex(String value) {
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    final index = months.indexOf(value.toLowerCase());
    return index == -1 ? null : index + 1;
  }

  String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  void _handleAdminFailure(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = false;
      _statusMessage = message;
    });
    _showSnack(message);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut() async {
    try {
      await _apiClient.logout();
    } catch (_) {
      // Clear local session even if the server-side token is already gone.
    }

    if (!mounted) {
      return;
    }

    widget.onLogout();
  }

  Future<void> _printReport() async {
    if (_reportResult == null) {
      return;
    }

    final bytes = await _buildPdfBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _exportReportPdf() async {
    if (_reportResult == null) {
      return;
    }

    final result = _reportResult!;
    final bytes = await _buildPdfBytes();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          '${_slugify(result.queryName)}_${_slugify(result.serverName)}.pdf',
    );
  }

  Future<Uint8List> _buildPdfBytes() async {
    final report = _reportResult!;
    final document = pw.Document();
    pw.ImageProvider? logo;
    final logoUrl = _companyProfile.companyLogoUrl.trim();

    if (logoUrl.isNotEmpty) {
      try {
        logo = await networkImage(logoUrl);
      } catch (_) {
        logo = null;
      }
    }

    final tableData = report.rows
        .map(
          (row) => report.columns
              .map((column) => _formatCell(row[column]))
              .toList(growable: false),
        )
        .toList(growable: false);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 64,
                    height: 64,
                    margin: const pw.EdgeInsets.only(right: 16),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _companyProfile.companyName.trim().isEmpty
                            ? 'VitalPro Report'
                            : _companyProfile.companyName,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (_companyProfile.companyAddress.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(_companyProfile.companyAddress),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Query: ${report.queryName}'),
                  pw.Text('Server: ${report.serverName}'),
                  pw.Text('Executed: ${_formatTimestamp(report.executedAt)}'),
                  pw.Text('Rows: ${report.rowCount}'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: report.columns,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue100,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ];
        },
      ),
    );

    return document.save();
  }

  String _slugify(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String get _pageTitle {
    if (widget.homeMode == HomeMode.reporting) {
      return 'VitalPro Reporting';
    }

    switch (_adminSection) {
      case AdminPanelSection.dashboard:
        return 'VitalPro Admin';
      case AdminPanelSection.company:
        return 'Admin - Company';
      case AdminPanelSection.users:
        return 'Admin - Users';
      case AdminPanelSection.servers:
        return 'Admin - SQL Servers';
      case AdminPanelSection.queries:
        return 'Admin - Queries';
    }
  }

  String _adminSectionLabel(AdminPanelSection section) {
    switch (section) {
      case AdminPanelSection.dashboard:
        return 'Dashboard';
      case AdminPanelSection.company:
        return 'Company';
      case AdminPanelSection.users:
        return 'Users';
      case AdminPanelSection.servers:
        return 'SQL Servers';
      case AdminPanelSection.queries:
        return 'Queries';
    }
  }

  IconData _adminSectionIcon(AdminPanelSection section) {
    switch (section) {
      case AdminPanelSection.dashboard:
        return Icons.space_dashboard_outlined;
      case AdminPanelSection.company:
        return Icons.business_outlined;
      case AdminPanelSection.users:
        return Icons.people_alt_outlined;
      case AdminPanelSection.servers:
        return Icons.storage_outlined;
      case AdminPanelSection.queries:
        return Icons.description_outlined;
    }
  }

  void _selectAdminSection(AdminPanelSection section) {
    setState(() {
      _adminSection = section;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _isAdminUser ? _buildAdminDrawer() : null,
      appBar: AppBar(
        title: Text(_pageTitle),
        centerTitle: false,
        actions: [
          Tooltip(
            message:
                'Signed in as ${widget.session.user.username} (${widget.session.user.role.name})',
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.account_circle_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _isLoading || _isBusy ? null : _loadBootstrap,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _isBusy ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : widget.homeMode == HomeMode.reporting
            ? _buildReportingSection()
            : _buildAdminSection(),
      ),
    );
  }

  Widget _buildReportingSection() {
    final chartData = _reportResult == null
        ? null
        : _deriveChartData(_reportResult!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final leftPanel = Column(
          children: [
            _buildCompanyCard(),
            const SizedBox(height: 20),
            _buildFilterCard(),
          ],
        );
        final rightPanel = _buildResultsCard(chartData);

        return Padding(
          padding: const EdgeInsets.all(20),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: leftPanel),
                    const SizedBox(width: 20),
                    Expanded(flex: 7, child: rightPanel),
                  ],
                )
              : ListView(
                  children: [leftPanel, const SizedBox(height: 20), rightPanel],
                ),
        );
      },
    );
  }

  Widget _buildCompanyCard() {
    final hasLogo = _companyProfile.companyLogoUrl.trim().isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;
            final identityBlock = Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE3EEF5),
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasLogo
                  ? Image.network(
                      _companyProfile.companyLogoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.business_outlined,
                        size: 34,
                        color: Color(0xFF355468),
                      ),
                    )
                  : const Center(
                      child: VitalProLogo(size: 48, showWordmark: false),
                    ),
            );
            final detailsBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _companyProfile.companyName.trim().isEmpty
                      ? 'Client reporting workspace'
                      : _companyProfile.companyName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A2540),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _companyProfile.companyAddress.trim().isEmpty
                      ? 'Save the client company name, address, and logo from Admin.'
                      : _companyProfile.companyAddress,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4F6478),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E2EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Status',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF355468),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _healthMessage ??
                            (_apiBaseUrl.trim().isEmpty
                                ? 'API connection is not configured.'
                                : 'API configured.'),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identityBlock,
                  const SizedBox(height: 18),
                  detailsBlock,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identityBlock,
                const SizedBox(width: 18),
                Expanded(child: detailsBlock),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    final selectedServer = _selectedServer;
    final selectedQuery = _selectedQuery;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report Controls',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select one SQL Server at a time, choose a saved report query, then run the report.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
            ),
            const SizedBox(height: 20),
            if (_servers.isEmpty)
              _buildEmptyMessage('No SQL servers saved yet.')
            else
              RadioGroup<int>(
                groupValue: _selectedServerId,
                onChanged: (value) {
                  setState(() {
                    _selectedServerId = value;
                    _reportResult = null;
                  });
                },
                child: Column(
                  children: _servers.map((server) {
                    final isSelected = server.id == _selectedServerId;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0B5D7A)
                              : const Color(0xFFD8E2EC),
                        ),
                        color: isSelected
                            ? const Color(0xFFE9F5FA)
                            : Colors.white,
                      ),
                      child: RadioListTile<int>(
                        value: server.id ?? -1,
                        title: Text(
                          server.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${server.host}:${server.port}  -  ${server.databaseName}',
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                final infoText = Text(
                  selectedServer == null
                      ? 'Choose a server first.'
                      : 'Selected server: ${selectedServer.label}',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
                final actionButton = OutlinedButton.icon(
                  onPressed: selectedServer == null ? null : _setDefaultServer,
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Set Default'),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      infoText,
                      const SizedBox(height: 12),
                      actionButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: infoText),
                    const SizedBox(width: 12),
                    actionButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              initialValue: _selectedQueryId,
              items: _queries
                  .where((query) => query.id != null)
                  .map(
                    (query) => DropdownMenuItem<int>(
                      value: query.id,
                      child: Text(query.queryName),
                    ),
                  )
                  .toList(),
              onChanged: _queries.isEmpty ? null : _onQueryChanged,
              decoration: const InputDecoration(
                labelText: 'Saved query',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            if (selectedQuery != null && selectedQuery.filters.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...selectedQuery.filters.map(_buildReportFilterInput),
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showChart,
              onChanged: (value) {
                setState(() {
                  _showChart = value ?? false;
                });
              },
              title: const Text('Show chart if the result is chartable'),
              subtitle: Text(
                selectedQuery == null
                    ? 'Select a query to use its default chart preference.'
                    : selectedQuery.showChartByDefault
                    ? 'This query is saved to show a chart by default.'
                    : 'This query is saved without a default chart.',
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              _buildStatusBanner(_statusMessage!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isBusy ? null : _runReport,
                icon: _isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: const Text('Run Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard(_ChartData? chartData) {
    final result = _reportResult;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 640;
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Output',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0A2540),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Table results, chart preview, and PDF actions appear here after a report runs.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4F6478),
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: result == null ? null : _printReport,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: result == null ? null : _exportReportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Export PDF'),
                    ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [summary, const SizedBox(height: 16), actions],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            if (result == null)
              _buildEmptyMessage(
                'No report results yet. Run a saved query to load a table and optional chart.',
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildMetricChip('Server', result.serverName),
                  _buildMetricChip('Query', result.queryName),
                  _buildMetricChip('Rows', '${result.rowCount}'),
                  _buildMetricChip(
                    'Executed',
                    _formatTimestamp(result.executedAt),
                  ),
                ],
              ),
              if (_showChart) ...[
                const SizedBox(height: 20),
                if (chartData == null)
                  _buildStatusBanner(
                    'Chart preview is enabled, but the result set needs at least one numeric column.',
                  )
                else
                  _buildChartCard(chartData),
              ],
              const SizedBox(height: 20),
              _buildTable(result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSection() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(children: _buildAdminSectionChildren()),
    );
  }

  List<Widget> _buildAdminSectionChildren() {
    switch (_adminSection) {
      case AdminPanelSection.dashboard:
        return [
          _buildAdminHeader(),
          const SizedBox(height: 20),
          _buildAdminOverviewCard(),
        ];
      case AdminPanelSection.company:
        return [
          _buildAdminPageIntro(
            title: 'Company Setup',
            description:
                'Manage client identity details used across the reporting workspace.',
          ),
          const SizedBox(height: 20),
          _buildCompanyAdminCard(),
        ];
      case AdminPanelSection.users:
        return [
          _buildAdminPageIntro(
            title: 'User Management',
            description:
                'Create, update, and review application accounts from one place.',
          ),
          const SizedBox(height: 20),
          _buildUserAdminCard(),
          const SizedBox(height: 20),
          _buildSavedUsersCard(),
        ];
      case AdminPanelSection.servers:
        return [
          _buildAdminPageIntro(
            title: 'SQL Server Management',
            description:
                'Configure MSSQL connections and maintain the saved server library.',
          ),
          const SizedBox(height: 20),
          _buildServerAdminCard(),
          const SizedBox(height: 20),
          _buildSavedServersCard(),
        ];
      case AdminPanelSection.queries:
        return [
          _buildAdminPageIntro(
            title: 'Query Management',
            description:
                'Maintain reusable SQL queries and their reporting filters.',
          ),
          const SizedBox(height: 20),
          _buildQueryAdminCard(),
          const SizedBox(height: 20),
          _buildSavedQueriesCard(),
        ];
    }
  }

  Widget _buildAdminDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VitalProLogo(size: 56, subtitle: 'Admin Workspace'),
                  const SizedBox(height: 12),
                  Text(
                    widget.session.user.username,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use the drawer to open each admin area separately.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFB8C7D9),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF284B63)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: AdminPanelSection.values.map((section) {
                  return ListTile(
                    leading: Icon(_adminSectionIcon(section)),
                    title: Text(_adminSectionLabel(section)),
                    selected: _adminSection == section,
                    iconColor: _adminSection == section
                        ? Colors.white
                        : const Color(0xFF9FB3C8),
                    textColor: _adminSection == section
                        ? Colors.white
                        : const Color(0xFFD9E2EC),
                    selectedColor: Colors.white,
                    selectedTileColor: const Color(0xFF163754),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onTap: () => _selectAdminSection(section),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminHeader() {
    final companyName = _companyProfile.companyName.trim().isEmpty
        ? 'Client profile pending'
        : _companyProfile.companyName;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF103B5C), Color(0xFF1E5A73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A103B5C),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 760;
            final intro = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VitalProLogo(size: 72, subtitle: 'Admin Workspace'),
                const SizedBox(height: 18),
                Text(
                  'Operational Control Center',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Manage client identity, user access, SQL connections, and reusable reporting queries from one controlled workspace.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFD9E7F2),
                    height: 1.45,
                  ),
                ),
              ],
            );
            final summary = Container(
              width: isCompact ? double.infinity : 260,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current profile',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFD9E7F2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    companyName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildHeroMetaRow(
                    icon: Icons.people_alt_outlined,
                    text: '${_users.length} active admin records',
                  ),
                  const SizedBox(height: 8),
                  _buildHeroMetaRow(
                    icon: Icons.storage_outlined,
                    text: '${_servers.length} SQL endpoints configured',
                  ),
                  const SizedBox(height: 8),
                  _buildHeroMetaRow(
                    icon: Icons.description_outlined,
                    text: '${_queries.length} saved report queries',
                  ),
                ],
              ),
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [intro, const SizedBox(height: 20), summary],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: intro),
                const SizedBox(width: 20),
                summary,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAdminPageIntro({
    required String title,
    required String description,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminOverviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Sections',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A polished overview of your core admin data, with quick entry points for the areas that need attention.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = constraints.maxWidth < 760
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16) / 2;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildOverviewStatCard(
                      label: 'Company Profile',
                      value: _companyProfile.companyName.trim().isEmpty
                          ? 'Not configured'
                          : _companyProfile.companyName,
                      caption: _companyProfile.companyAddress.trim().isEmpty
                          ? 'Client identity details still need attention.'
                          : 'Brand identity and reporting address are available.',
                      icon: Icons.business_outlined,
                      accent: const Color(0xFFE8F1F8),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: 'User Accounts',
                      value: '${_users.length}',
                      caption:
                          '${_users.where((user) => user.isActive).length} active accounts currently available.',
                      icon: Icons.people_alt_outlined,
                      accent: const Color(0xFFEAF5F1),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: 'SQL Servers',
                      value: '${_servers.length}',
                      caption: _servers.isEmpty
                          ? 'No MSSQL servers connected yet.'
                          : 'Saved endpoints are ready for reporting sessions.',
                      icon: Icons.storage_outlined,
                      accent: const Color(0xFFF4ECFA),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: 'Saved Queries',
                      value: '${_queries.length}',
                      caption: _queries.isEmpty
                          ? 'No reusable SQL query library yet.'
                          : 'Report query catalog is available for runtime use.',
                      icon: Icons.description_outlined,
                      accent: const Color(0xFFFEF3E8),
                      width: tileWidth,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 980;
                final quickActions = _buildAdminActionPanel();
                final operations = _buildAdminOperationsPanel();

                if (isCompact) {
                  return Column(
                    children: [
                      quickActions,
                      const SizedBox(height: 16),
                      operations,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: quickActions),
                    const SizedBox(width: 16),
                    Expanded(child: operations),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStatCard({
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color accent,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF103B5C)),
              ),
              const Spacer(),
              Text(
                label,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF486581),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF627D98),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminActionPanel() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Jump directly into the area that usually needs the next administrative update.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF627D98)),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildDashboardActionButton(
                icon: Icons.business_outlined,
                label: 'Edit Company',
                section: AdminPanelSection.company,
                isPrimary: true,
              ),
              _buildDashboardActionButton(
                icon: Icons.people_alt_outlined,
                label: 'Manage Users',
                section: AdminPanelSection.users,
              ),
              _buildDashboardActionButton(
                icon: Icons.storage_outlined,
                label: 'Review Servers',
                section: AdminPanelSection.servers,
              ),
              _buildDashboardActionButton(
                icon: Icons.description_outlined,
                label: 'Open Queries',
                section: AdminPanelSection.queries,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardActionButton({
    required IconData icon,
    required String label,
    required AdminPanelSection section,
    bool isPrimary = false,
  }) {
    final onPressed = () {
      setState(() {
        _adminSection = section;
      });
    };

    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildAdminOperationsPanel() {
    final readinessItems = [
      (
        title: 'Company identity',
        ready: _companyProfile.companyName.trim().isNotEmpty,
      ),
      (title: 'User access', ready: _users.isNotEmpty),
      (title: 'SQL connectivity', ready: _servers.isNotEmpty),
      (title: 'Query library', ready: _queries.isNotEmpty),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operational Readiness',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A quick health snapshot of the configuration needed for a smooth reporting workflow.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF627D98)),
          ),
          const SizedBox(height: 18),
          ...readinessItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildReadinessRow(title: item.title, ready: item.ready),
            ),
          ),
          if (_healthMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD8E2EC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Status',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF486581),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_healthMessage!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadinessRow({required String title, required bool ready}) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: ready ? const Color(0xFFE7F7EF) : const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            ready ? Icons.check_circle_outline : Icons.schedule_outlined,
            color: ready ? const Color(0xFF137752) : const Color(0xFFB56A00),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF243B53),
            ),
          ),
        ),
        Text(
          ready ? 'Ready' : 'Needs setup',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ready ? const Color(0xFF137752) : const Color(0xFFB56A00),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroMetaRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFD9E7F2)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFD9E7F2)),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyAdminCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Client Company',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _companyNameController,
              label: 'Company name',
              hint: 'VitalPro Client',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _companyAddressController,
              label: 'Company address',
              hint: 'Office address shown on the report header',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _companyLogoController,
              label: 'Company logo URL',
              hint: 'https://example.com/logo.png',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isBusy ? null : _saveCompanyProfile,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Company Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerAdminCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SQL Server Setup',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _serverNameController,
              label: 'Server label',
              hint: 'Head Office ERP',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverHostController,
              label: 'Server host',
              hint: '192.168.1.10 or SQLSERVER01',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverPortController,
              label: 'Port',
              hint: '1433',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverDatabaseController,
              label: 'Database name',
              hint: 'ERPDB',
            ),
            const SizedBox(height: 20),
            SegmentedButton<AuthenticationMode>(
              segments: const [
                ButtonSegment(
                  value: AuthenticationMode.sqlServer,
                  label: Text('SQL Login'),
                  icon: Icon(Icons.key_outlined),
                ),
                ButtonSegment(
                  value: AuthenticationMode.windows,
                  label: Text('Windows Auth'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_serverAuthenticationMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _serverAuthenticationMode = selection.first;
                });
              },
            ),
            if (_serverAuthenticationMode == AuthenticationMode.sqlServer) ...[
              const SizedBox(height: 16),
              _buildTextField(
                controller: _serverUsernameController,
                label: 'Username',
                hint: 'sa',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _serverPasswordController,
                label: 'Password',
                hint: 'SQL login password',
                obscureText: true,
                isPasswordVisible: _isSqlPasswordVisible,
                onTogglePasswordVisibility: () {
                  setState(() {
                    _isSqlPasswordVisible = !_isSqlPasswordVisible;
                  });
                },
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ? null : _saveServer,
                  icon: Icon(
                    _editingServerId == null
                        ? Icons.add_circle_outline
                        : Icons.save_outlined,
                  ),
                  label: Text(
                    _editingServerId == null
                        ? 'Save SQL Server'
                        : 'Update Server',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetServerForm,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAdminCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Users',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _userUsernameController,
              label: 'Username',
              hint: 'saleuser',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _userPasswordController,
              label: _editingUserId == null
                  ? 'Password'
                  : 'Password (leave blank to keep current)',
              hint: _editingUserId == null
                  ? 'Enter user password'
                  : 'Optional new password',
              obscureText: true,
              isPasswordVisible: _isUserPasswordVisible,
              onTogglePasswordVisibility: () {
                setState(() {
                  _isUserPasswordVisible = !_isUserPasswordVisible;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<UserRole>(
              initialValue: _userRole,
              items: UserRole.values
                  .map(
                    (role) => DropdownMenuItem<UserRole>(
                      value: role,
                      child: Text(role.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _userRole = value;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _userIsActive,
              onChanged: (value) {
                setState(() {
                  _userIsActive = value ?? true;
                });
              },
              title: const Text('Active account'),
              subtitle: const Text(
                'Inactive users cannot sign in until re-enabled.',
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ? null : _saveUser,
                  icon: Icon(
                    _editingUserId == null
                        ? Icons.person_add_alt_1_outlined
                        : Icons.save_outlined,
                  ),
                  label: Text(
                    _editingUserId == null ? 'Create User' : 'Update User',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetUserForm,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedUsersCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Directory',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_users.isEmpty)
              _buildEmptyMessage('No app users found yet.')
            else
              ..._users.map(
                (user) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E2EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit user',
                            onPressed: () => _loadUserForEditing(user),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete user',
                            onPressed: user.id == widget.session.user.id
                                ? null
                                : () => _deleteUser(user),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text('Role: ${user.role.name}'),
                      const SizedBox(height: 4),
                      Text(
                        user.isActive ? 'Status: active' : 'Status: inactive',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedServersCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved SQL Servers',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_servers.isEmpty)
              _buildEmptyMessage('No SQL servers saved in MySQL yet.')
            else
              ..._servers.map(
                (server) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E2EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              server.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit server',
                            onPressed: () => _loadServerForEditing(server),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete server',
                            onPressed: () => _deleteServer(server),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text('${server.host}:${server.port}'),
                      const SizedBox(height: 4),
                      Text('Database: ${server.databaseName}'),
                      const SizedBox(height: 4),
                      Text(
                        server.authenticationMode == AuthenticationMode.windows
                            ? 'Authentication: Windows'
                            : 'Authentication: SQL Login (${server.username})',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueryAdminCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Queries',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _queryNameController,
              label: 'Query name',
              hint: 'Show Product',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _queryTextController,
              label: 'SQL query',
              hint:
                  'SELECT * FROM products WHERE DocumentDate = {{DocumentDate}}',
              maxLines: 8,
            ),
            const SizedBox(height: 12),
            _buildStatusBanner(
              'Use placeholders like {{DocumentDate}} inside the SQL. The reporting screen will show matching filter fields above Run Report.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Query Filters',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _addQueryFilter,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Filter'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_queryFilters.isEmpty)
              _buildEmptyMessage(
                'No filters added yet. Example: add a date filter with key DocumentDate and use {{DocumentDate}} in the SQL.',
              )
            else
              ...List.generate(
                _queryFilters.length,
                (index) => _buildQueryFilterEditor(index, _queryFilters[index]),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showQueryChartByDefault,
              onChanged: (value) {
                setState(() {
                  _showQueryChartByDefault = value ?? false;
                });
              },
              title: const Text('Show chart by default'),
              subtitle: const Text(
                'The reporting page will automatically enable the chart toggle for this query.',
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ? null : _saveQuery,
                  icon: Icon(
                    _editingQueryId == null
                        ? Icons.add_circle_outline
                        : Icons.save_outlined,
                  ),
                  label: Text(
                    _editingQueryId == null ? 'Save Query' : 'Update Query',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetQueryForm,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedQueriesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Query Library',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_queries.isEmpty)
              _buildEmptyMessage('No report queries saved in MySQL yet.')
            else
              ..._queries.map(
                (query) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E2EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              query.queryName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit query',
                            onPressed: () => _loadQueryForEditing(query),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete query',
                            onPressed: () => _deleteQuery(query),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        query.queryText.trim().isEmpty
                            ? 'Query text hidden until admin data is loaded.'
                            : query.queryText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.showChartByDefault
                            ? 'Chart default: enabled'
                            : 'Chart default: disabled',
                      ),
                      if (query.filters.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: query.filters
                              .map(
                                (filter) => Chip(
                                  label: Text(
                                    '${filter.label} (${filter.type.name})',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportFilterInput(QueryFilterDefinition filter) {
    final controller = _reportFilterControllers.putIfAbsent(
      filter.key,
      () => TextEditingController(text: filter.defaultValue),
    );

    final label = filter.isRequired ? '${filter.label} *' : filter.label;

    if (filter.type == QueryFilterType.date) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          readOnly: true,
          onTap: () => _pickDateFilterValue(filter),
          decoration: InputDecoration(
            labelText: label,
            hintText: filter.placeholder.isEmpty
                ? 'dd-MMM-yyyy'
                : filter.placeholder,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              tooltip: 'Pick date',
              onPressed: () => _pickDateFilterValue(filter),
              icon: const Icon(Icons.calendar_today_outlined),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: filter.type == QueryFilterType.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: filter.placeholder,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildQueryFilterEditor(int index, _EditableQueryFilter filter) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Remove filter',
                onPressed: _isBusy ? null : () => _removeQueryFilter(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.keyController,
            label: 'Filter key',
            hint: 'DocumentDate',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.labelController,
            label: 'Filter label',
            hint: 'Document Date',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<QueryFilterType>(
            initialValue: filter.type,
            items: QueryFilterType.values
                .map(
                  (type) => DropdownMenuItem<QueryFilterType>(
                    value: type,
                    child: Text(type.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final nextFilter = filter.copyWith(type: value);
              setState(() {
                _queryFilters[index] = nextFilter;
              });
              filter.dispose();
            },
            decoration: const InputDecoration(
              labelText: 'Filter type',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.placeholderController,
            label: 'Placeholder',
            hint: filter.type == QueryFilterType.date
                ? 'dd-MMM-yyyy'
                : 'Optional hint',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.defaultValueController,
            label: 'Default value',
            hint: filter.type == QueryFilterType.date
                ? '09-Feb-2026'
                : 'Optional default',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: filter.isRequired,
            onChanged: (value) {
              final nextFilter = filter.copyWith(isRequired: value ?? false);
              setState(() {
                _queryFilters[index] = nextFilter;
              });
              filter.dispose();
            },
            title: const Text('Required filter'),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(ReportResult result) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.resolveWith<Color?>(
              (_) => const Color(0xFFE9F5FA),
            ),
            columns: result.columns
                .map((column) => DataColumn(label: Text(column)))
                .toList(),
            rows: result.rows
                .map(
                  (row) => DataRow(
                    cells: result.columns
                        .map(
                          (column) => DataCell(Text(_formatCell(row[column]))),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(_ChartData chartData) {
    final maxValue = chartData.points
        .map((point) => point.value)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chart Preview',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Label: ${chartData.labelColumn}  -  Value: ${chartData.valueColumn}',
          ),
          if (chartData.truncated) ...[
            const SizedBox(height: 4),
            Text(
              'Showing the first ${chartData.points.length} rows for readability.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4F6478)),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= chartData.points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Transform.rotate(
                            angle: -0.5,
                            child: Text(
                              chartData.points[index].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < chartData.points.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: chartData.points[index].value,
                          width: 20,
                          borderRadius: BorderRadius.circular(6),
                          color: const Color(0xFF0B5D7A),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _ChartData? _deriveChartData(ReportResult result) {
    if (result.rows.isEmpty || result.columns.isEmpty) {
      return null;
    }

    String? valueColumn;
    for (final column in result.columns) {
      if (result.rows.any((row) => _asDouble(row[column]) != null)) {
        valueColumn = column;
        break;
      }
    }

    if (valueColumn == null) {
      return null;
    }

    String? labelColumn;
    for (final column in result.columns) {
      if (column != valueColumn) {
        labelColumn = column;
        break;
      }
    }

    const limit = 12;
    final points = <_ChartPoint>[];
    for (
      var index = 0;
      index < result.rows.length && points.length < limit;
      index++
    ) {
      final row = result.rows[index];
      final value = _asDouble(row[valueColumn]);
      if (value == null) {
        continue;
      }
      final rawLabel = labelColumn == null
          ? 'Row ${index + 1}'
          : _formatCell(row[labelColumn]);
      points.add(_ChartPoint(_trimLabel(rawLabel), value));
    }

    if (points.isEmpty) {
      return null;
    }

    return _ChartData(
      labelColumn: labelColumn ?? 'Row',
      valueColumn: valueColumn,
      points: points,
      truncated: result.rows.length > points.length,
    );
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(_formatCell(value));
  }

  String _trimLabel(String value) {
    if (value.length <= 10) {
      return value;
    }
    return '${value.substring(0, 10)}...';
  }

  String _formatCell(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return value.toString();
  }

  String _formatTimestamp(String value) {
    final dateTime = DateTime.tryParse(value);
    if (dateTime == null) {
      return value;
    }

    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isPasswordVisible = false,
    VoidCallback? onTogglePasswordVisibility,
  }) {
    return TextField(
      controller: controller,
      maxLines: obscureText && !isPasswordVisible ? 1 : maxLines,
      keyboardType: keyboardType,
      obscureText: obscureText && !isPasswordVisible,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: obscureText
            ? IconButton(
                onPressed: onTogglePasswordVisibility,
                icon: Icon(
                  isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Text('$label: $value'),
    );
  }

  Widget _buildStatusBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Text(message),
    );
  }

  Widget _buildEmptyMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Text(message),
    );
  }
}

class _ChartData {
  const _ChartData({
    required this.labelColumn,
    required this.valueColumn,
    required this.points,
    required this.truncated,
  });

  final String labelColumn;
  final String valueColumn;
  final List<_ChartPoint> points;
  final bool truncated;
}

class _ChartPoint {
  const _ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

class _EditableQueryFilter {
  _EditableQueryFilter({
    String key = '',
    String label = '',
    this.type = QueryFilterType.text,
    this.isRequired = false,
    String placeholder = '',
    String defaultValue = '',
  }) : keyController = TextEditingController(text: key),
       labelController = TextEditingController(text: label),
       placeholderController = TextEditingController(text: placeholder),
       defaultValueController = TextEditingController(text: defaultValue);

  factory _EditableQueryFilter.fromDefinition(QueryFilterDefinition filter) {
    return _EditableQueryFilter(
      key: filter.key,
      label: filter.label,
      type: filter.type,
      isRequired: filter.isRequired,
      placeholder: filter.placeholder,
      defaultValue: filter.defaultValue,
    );
  }

  final TextEditingController keyController;
  final TextEditingController labelController;
  final TextEditingController placeholderController;
  final TextEditingController defaultValueController;
  final QueryFilterType type;
  final bool isRequired;

  _EditableQueryFilter copyWith({QueryFilterType? type, bool? isRequired}) {
    return _EditableQueryFilter(
      key: keyController.text,
      label: labelController.text,
      type: type ?? this.type,
      isRequired: isRequired ?? this.isRequired,
      placeholder: placeholderController.text,
      defaultValue: defaultValueController.text,
    );
  }

  QueryFilterDefinition toDefinition() {
    return QueryFilterDefinition(
      key: keyController.text.trim(),
      label: labelController.text.trim(),
      type: type,
      isRequired: isRequired,
      placeholder: placeholderController.text.trim(),
      defaultValue: defaultValueController.text.trim(),
    );
  }

  void dispose() {
    keyController.dispose();
    labelController.dispose();
    placeholderController.dispose();
    defaultValueController.dispose();
  }
}
