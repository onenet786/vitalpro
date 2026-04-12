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

enum AdminPanelSection { dashboard, companies, users, servers, queries }

enum _ChartVisualType { bar, pie }

class ReportingHomePage extends StatefulWidget {
  const ReportingHomePage({
    super.key,
    required this.session,
    required this.onLogout,
    required this.homeMode,
    required this.locale,
    required this.onLocaleChanged,
  });

  final AuthSession session;
  final VoidCallback onLogout;
  final HomeMode homeMode;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<ReportingHomePage> createState() => _ReportingHomePageState();
}

class _ReportingHomePageState extends State<ReportingHomePage> {
  static const _defaultServerPreferenceKey = 'default_reporting_server_id';
  static const _rowLabelColumnKey = '__row__';

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
  final Map<String, List<String>> _reportFilterOptions = {};
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
  String _chartLabelColumn = _rowLabelColumnKey;
  List<String> _chartValueColumns = const [];
  _ChartVisualType _chartVisualType = _ChartVisualType.pie;
  String? _statusMessage;
  String? _healthMessage;
  Set<String> _loadingReportFilterOptions = const {};
  int? _editingCompanyId;
  int? _selectedAssignedCompanyId;
  Set<int> _selectedAssignedServerIds = <int>{};
  Set<int> _selectedAssignedQueryIds = <int>{};
  int? _selectedServerId;
  int? _selectedQueryId;
  int? _editingServerId;
  int? _editingQueryId;
  int? _editingUserId;
  CompanyProfile _companyProfile = const CompanyProfile();
  List<CompanyProfile> _companies = const [];
  List<ReportingServer> _servers = const [];
  List<SavedQuery> _queries = const [];
  List<AppUser> _users = const [];
  ReportResult? _reportResult;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  bool get _isAdminUser => widget.homeMode == HomeMode.admin;
  bool get _isUrdu => widget.locale.languageCode == 'ur';
  String _tr(String en, String ur) => _isUrdu ? ur : en;
  String _displayLabel(String value) {
    if (!_isUrdu) {
      return value;
    }

    switch (value.trim().toLowerCase()) {
      case 'cash':
      case 'cash_amount':
        return 'نقد';
      case 'credit':
      case 'credit_amount':
        return 'ادھار';
      case 'amount':
      case 'total':
      case 'total_amount':
        return 'رقم';
      case 'documentdate':
        return 'دستاویز کی تاریخ';
      default:
        return value;
    }
  }

  String _displayCompanyName(String value) {
    if (!_isUrdu) {
      return value;
    }

    switch (value.trim().toLowerCase()) {
      case 'ajmairy garments':
        return 'اجمیری گارمنٹس';
      default:
        return value;
    }
  }

  String _displayCompanyAddress(String value) {
    if (!_isUrdu) {
      return value;
    }

    return value
        .replaceAll(RegExp(r'\bRang\s+Mahal\b', caseSensitive: false), 'رنگ محل')
        .replaceAll(RegExp(r'\bLahore\b', caseSensitive: false), 'لاہور');
  }

  String _displayQueryName(String value) {
    return _localizedQueryName(value, isUrdu: _isUrdu);
  }
  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return _tr('Admin', 'ایڈمن');
      case UserRole.reporting:
        return _tr('Reporting', 'رپورٹنگ');
    }
  }

  String _authenticationModeLabel(
    AuthenticationMode mode, {
    String username = '',
  }) {
    switch (mode) {
      case AuthenticationMode.windows:
        return _tr('Authentication: Windows', 'تصدیق: ونڈوز');
      case AuthenticationMode.sqlServer:
        return _tr(
          'Authentication: SQL Login${username.isEmpty ? '' : ' ($username)'}',
          'تصدیق: SQL لاگ اِن${username.isEmpty ? '' : ' ($username)'}',
        );
    }
  }

  String _queryFilterTypeLabel(QueryFilterType type) {
    switch (type) {
      case QueryFilterType.text:
        return _tr('Text', 'متن');
      case QueryFilterType.number:
        return _tr('Number', 'نمبر');
      case QueryFilterType.date:
        return _tr('Date', 'تاریخ');
    }
  }

  String _queryFilterInputModeLabel(QueryFilterInputType inputType) {
    switch (inputType) {
      case QueryFilterInputType.text:
        return _tr('Text Input', 'متنی اندراج');
      case QueryFilterInputType.dropdown:
        return _tr('Dropdown', 'ڈراپ ڈاؤن');
    }
  }

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
        _companies = bootstrap.companies;
        _servers = bootstrap.servers;
        _queries = bootstrap.queries;
        _users = bootstrap.users;
        _healthMessage = healthMessage;
        _selectedServerId = nextServerId;
        _selectedQueryId = nextQueryId;
        _showChart = selectedQuery?.showChartByDefault ?? false;
        _statusMessage = bootstrap.servers.isEmpty || bootstrap.queries.isEmpty
            ? (_isAdminUser
                  ? _tr(
                      'Add at least one SQL server and one saved query from Admin before running reports.',
                      'رپورٹس چلانے سے پہلے ایڈمن سے کم از کم ایک SQL سرور اور ایک محفوظ کوئری شامل کریں۔',
                    )
                  : _tr(
                      'Ask an admin to add at least one SQL server and one saved query before running reports.',
                      'رپورٹس چلانے سے پہلے ایڈمن سے کہیں کہ کم از کم ایک SQL سرور اور ایک محفوظ کوئری شامل کرے۔',
                    ))
            : _tr(
                'Configuration loaded from MySQL.',
                'کنفیگریشن MySQL سے لوڈ ہو گئی ہے۔',
              );
        _isLoading = false;
      });

      await _refreshReportFilterOptions();

      if (_isAdminUser && _editingCompanyId == null) {
        _resetCompanyForm();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage = _tr(
          'Could not load reporting configuration. Details: $error',
          'رپورٹنگ کنفیگریشن لوڈ نہیں ہو سکی۔ تفصیل: $error',
        );
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

    _showSnack(
      _tr(
        'Default reporting server updated.',
        'ڈیفالٹ رپورٹنگ سرور اپڈیٹ ہو گیا ہے۔',
      ),
    );
  }

  void _onQueryChanged(int? queryId) {
    final query = _findQueryById(_queries, queryId);
    _syncReportFilterControllers(query);
    setState(() {
      _selectedQueryId = queryId;
      _showChart = query?.showChartByDefault ?? false;
      _reportResult = null;
    });
    _refreshReportFilterOptions();
  }

  void _syncReportFilterControllers(SavedQuery? query) {
    final activeKeys = <String>{};
    final todayText = _formatQueryDate(DateTime.now());
    for (final filter in query?.filters ?? const <QueryFilterDefinition>[]) {
      activeKeys.add(filter.key);
      final controller = _reportFilterControllers.putIfAbsent(
        filter.key,
        () => TextEditingController(),
      );
      if (controller.text.trim().isEmpty &&
          filter.defaultValue.trim().isNotEmpty) {
        controller.text = filter.defaultValue.trim();
      } else if (controller.text.trim().isEmpty && _shouldAutoFillToday(filter)) {
        controller.text = todayText;
      }
    }

    final staleKeys = _reportFilterControllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      _reportFilterControllers.remove(key)?.dispose();
      _reportFilterOptions.remove(key);
    }
  }

  bool _shouldAutoFillToday(QueryFilterDefinition filter) {
    if (filter.type != QueryFilterType.date) {
      return false;
    }

    final normalizedKey = filter.key.trim().toLowerCase();
    return normalizedKey == 'fromdate' || normalizedKey == 'todate';
  }

  Future<void> _refreshReportFilterOptions({String? filterKey}) async {
    final serverId = _selectedServerId;
    final query = _selectedQuery;
    final queryId = query?.id;
    if (serverId == null || query == null || queryId == null) {
      if (mounted && _reportFilterOptions.isNotEmpty) {
        setState(() {
          _reportFilterOptions.clear();
          _loadingReportFilterOptions = const {};
        });
      }
      return;
    }

    final targets = query.filters
        .where(
          (filter) =>
              filter.inputType == QueryFilterInputType.dropdown &&
              filter.optionsQuery.trim().isNotEmpty &&
              (filterKey == null || filter.key == filterKey),
        )
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingReportFilterOptions = {
          ..._loadingReportFilterOptions,
          ...targets.map((filter) => filter.key),
        };
      });
    }

    final activeFilters = _collectReportFilters(query);
    for (final filter in targets) {
      try {
        final options = await _apiClient.fetchReportFilterOptions(
          serverId: serverId,
          queryId: queryId,
          filterKey: filter.key,
          filters: activeFilters,
        );
        if (!mounted) {
          return;
        }

        final controller = _reportFilterControllers[filter.key];
        setState(() {
          _reportFilterOptions[filter.key] = options;
          _loadingReportFilterOptions = Set<String>.from(
            _loadingReportFilterOptions,
          )..remove(filter.key);
          if (controller != null &&
              controller.text.trim().isNotEmpty &&
              !options.contains(controller.text.trim())) {
            controller.clear();
          }
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _reportFilterOptions[filter.key] = const [];
          _loadingReportFilterOptions = Set<String>.from(
            _loadingReportFilterOptions,
          )..remove(filter.key);
        });
      }
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
      _showSnack(
        _tr(
          'Select one SQL server and one saved query first.',
          'پہلے ایک SQL سرور اور ایک محفوظ کوئری منتخب کریں۔',
        ),
      );
      return;
    }

    for (final filter in query?.filters ?? const <QueryFilterDefinition>[]) {
      final value = _reportFilterControllers[filter.key]?.text.trim() ?? '';
      if (filter.isRequired && value.isEmpty) {
        _showSnack(
          _tr(
            '${filter.label} is required.',
            '${filter.label} درج کرنا ضروری ہے۔',
          ),
        );
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _tr(
        'Running report query...',
        'رپورٹ کوئری چل رہی ہے...',
      );
    });

    try {
      final stopwatch = Stopwatch()..start();
      final rawResult = await _apiClient.runReport(
        serverId: serverId,
        queryId: queryId,
        filters: _collectReportFilters(query),
      );
      stopwatch.stop();
      final result = rawResult.copyWith(elapsedMs: stopwatch.elapsedMilliseconds);
      debugPrint('================ REPORT QUERY DEBUG ================');
      debugPrint('Query: ${result.queryName}');
      debugPrint('Server: ${result.serverName}');
      debugPrint('Executed At: ${result.executedAt}');
      debugPrint('Time Taken: ${_formatElapsedDuration(result.elapsedMs)}');
      debugPrint('SQL:');
      debugPrint(result.executedQuery);
      debugPrint('====================================================');
      if (!mounted) {
        return;
      }

      final chartDefaults = _resolveChartSelection(result);
      setState(() {
        _reportResult = result;
        _chartLabelColumn = chartDefaults.labelColumn;
        _chartValueColumns = chartDefaults.valueColumns;
        _isBusy = false;
        _statusMessage = _tr(
          'Report returned ${result.rowCount} row(s).',
          'رپورٹ نے ${result.rowCount} قطاریں واپس کیں۔',
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openReportViewer(result);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = _tr(
          'Could not run report. Details: $error',
          'رپورٹ نہیں چل سکی۔ تفصیل: $error',
        );
      });
    }
  }

  Future<void> _saveCompanyProfile() async {
    if (_companyNameController.text.trim().isEmpty) {
      _showSnack(_tr('Company name is required.', 'کمپنی کا نام ضروری ہے۔'));
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingCompanyId == null
          ? _tr('Creating company...', 'کمپنی بنائی جا رہی ہے...')
          : _tr('Updating company...', 'کمپنی اپڈیٹ کی جا رہی ہے...');
    });

    try {
      final result = await _apiClient.saveCompanyProfile(
        CompanyProfile(
          id: _editingCompanyId,
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

      _resetCompanyForm();
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure(
        _tr(
          'Could not save company. Details: $error',
          'کمپنی محفوظ نہیں ہو سکی۔ تفصیل: $error',
        ),
      );
    }
  }

  Future<void> _deleteCompany(CompanyProfile company) async {
    if (company.id == null) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_tr('Delete Company', 'کمپنی حذف کریں')),
          content: Text(
            _tr(
              'Delete ${company.companyName} from saved companies?',
              '${company.companyName} کو محفوظ کمپنیوں سے حذف کریں؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr('Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr('Delete', 'حذف کریں')),
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
      _statusMessage = _tr('Deleting company...', 'کمپنی حذف کی جا رہی ہے...');
    });

    try {
      final result = await _apiClient.deleteCompany(company.id!);
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = result.message;
      });

      if (_editingCompanyId == company.id) {
        _resetCompanyForm();
      }
      await _loadBootstrap();
      _showSnack(result.message);
    } catch (error) {
      _handleAdminFailure(
        _tr(
          'Could not delete company. Details: $error',
          'کمپنی حذف نہیں ہو سکی۔ تفصیل: $error',
        ),
      );
    }
  }

  Future<void> _saveServer() async {
    if (_serverNameController.text.trim().isEmpty ||
        _serverHostController.text.trim().isEmpty ||
        _serverDatabaseController.text.trim().isEmpty) {
      _showSnack(
        _tr(
          'Server name, host, and database are required.',
          'سرور کا نام، ہوسٹ، اور ڈیٹابیس ضروری ہیں۔',
        ),
      );
      return;
    }

    if (_serverAuthenticationMode == AuthenticationMode.sqlServer &&
        (_serverUsernameController.text.trim().isEmpty ||
            _serverPasswordController.text.isEmpty)) {
      _showSnack(
        _tr(
          'Username and password are required for SQL login.',
          'SQL لاگ اِن کے لیے صارف نام اور پاس ورڈ ضروری ہیں۔',
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingServerId == null
          ? _tr('Saving SQL server...', 'SQL سرور محفوظ کیا جا رہا ہے...')
          : _tr('Updating SQL server...', 'SQL سرور اپڈیٹ کیا جا رہا ہے...');
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
      _handleAdminFailure(
        _tr(
          'Could not save SQL server. Details: $error',
          'SQL سرور محفوظ نہیں ہو سکا۔ تفصیل: $error',
        ),
      );
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
          title: Text(_tr('Delete SQL Server', 'SQL سرور حذف کریں')),
          content: Text(
            _tr(
              'Delete ${server.label} from the saved server list?',
              '${server.label} کو محفوظ سرور فہرست سے حذف کریں؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr('Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr('Delete', 'حذف کریں')),
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
      _statusMessage = _tr(
        'Deleting SQL server...',
        'SQL سرور حذف کیا جا رہا ہے...',
      );
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
      _handleAdminFailure(
        _tr(
          'Could not delete SQL server. Details: $error',
          'SQL سرور حذف نہیں ہو سکا۔ تفصیل: $error',
        ),
      );
    }
  }

  Future<void> _saveQuery() async {
    if (_queryNameController.text.trim().isEmpty ||
        _queryTextController.text.trim().isEmpty) {
      _showSnack(
        _tr(
          'Query name and SQL query text are required.',
          'کوئری کا نام اور SQL کوئری ٹیکسٹ ضروری ہیں۔',
        ),
      );
      return;
    }

    final filterDefinitions = _queryFilters
        .map((filter) => filter.toDefinition())
        .toList(growable: false);
    final seenKeys = <String>{};
    for (final filter in filterDefinitions) {
      if (filter.key.isEmpty || filter.label.isEmpty) {
        _showSnack(
          _tr(
            'Each query filter needs both a key and a label.',
            'ہر کوئری فلٹر کے لیے key اور label دونوں ضروری ہیں۔',
          ),
        );
        return;
      }
      if (!seenKeys.add(filter.key.toLowerCase())) {
        _showSnack(
          _tr(
            'Each query filter key must be unique.',
            'ہر کوئری فلٹر key منفرد ہونی چاہیے۔',
          ),
        );
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingQueryId == null
          ? _tr('Saving report query...', 'رپورٹ کوئری محفوظ کی جا رہی ہے...')
          : _tr('Updating report query...', 'رپورٹ کوئری اپڈیٹ کی جا رہی ہے...');
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
      _handleAdminFailure(
        _tr(
          'Could not save report query. Details: $error',
          'رپورٹ کوئری محفوظ نہیں ہو سکی۔ تفصیل: $error',
        ),
      );
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
          title: Text(_tr('Delete Query', 'کوئری حذف کریں')),
          content: Text(
            _tr(
              'Delete ${query.queryName} from saved report queries?',
              '${query.queryName} کو محفوظ رپورٹ کوئریز سے حذف کریں؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr('Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr('Delete', 'حذف کریں')),
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
      _statusMessage = _tr(
        'Deleting report query...',
        'رپورٹ کوئری حذف کی جا رہی ہے...',
      );
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
      _handleAdminFailure(
        _tr(
          'Could not delete report query. Details: $error',
          'رپورٹ کوئری حذف نہیں ہو سکی۔ تفصیل: $error',
        ),
      );
    }
  }

  Future<void> _saveUser() async {
    if (_userUsernameController.text.trim().isEmpty) {
      _showSnack(_tr('Username is required.', 'صارف نام ضروری ہے۔'));
      return;
    }

    if (_editingUserId == null && _userPasswordController.text.isEmpty) {
      _showSnack(
        _tr(
          'Password is required for a new user.',
          'نئے صارف کے لیے پاس ورڈ ضروری ہے۔',
        ),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = _editingUserId == null
          ? _tr('Creating user...', 'صارف بنایا جا رہا ہے...')
          : _tr('Updating user...', 'صارف اپڈیٹ کیا جا رہا ہے...');
    });

    try {
      final result = await _apiClient.saveUser(
        AdminUserInput(
          id: _editingUserId,
          username: _userUsernameController.text.trim(),
          password: _userPasswordController.text,
          role: _userRole,
          isActive: _userIsActive,
          assignedCompanyId: _selectedAssignedCompanyId,
          assignedServerIds: _selectedAssignedServerIds.toList()..sort(),
          assignedQueryIds: _selectedAssignedQueryIds.toList()..sort(),
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
      _handleAdminFailure(
        _tr(
          'Could not save user. Details: $error',
          'صارف محفوظ نہیں ہو سکا۔ تفصیل: $error',
        ),
      );
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_tr('Delete User', 'صارف حذف کریں')),
          content: Text(
            _tr(
              'Delete ${user.username} from app users?',
              '${user.username} کو ایپ صارفین سے حذف کریں؟',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr('Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr('Delete', 'حذف کریں')),
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
      _statusMessage = _tr('Deleting user...', 'صارف حذف کیا جا رہا ہے...');
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
      _handleAdminFailure(
        _tr(
          'Could not delete user. Details: $error',
          'صارف حذف نہیں ہو سکا۔ تفصیل: $error',
        ),
      );
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
      _selectedAssignedCompanyId = user.assignedCompanyId;
      _selectedAssignedServerIds = user.assignedServerIds.toSet();
      _selectedAssignedQueryIds = user.assignedQueryIds.toSet();
      _userIsActive = user.isActive;
      _isUserPasswordVisible = false;
    });
  }

  void _loadCompanyForEditing(CompanyProfile company) {
    _companyNameController.text = company.companyName;
    _companyAddressController.text = company.companyAddress;
    _companyLogoController.text = company.companyLogoUrl;
    setState(() {
      _editingCompanyId = company.id;
    });
  }

  void _resetCompanyForm() {
    _companyNameController.clear();
    _companyAddressController.clear();
    _companyLogoController.clear();
    setState(() {
      _editingCompanyId = null;
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
      _selectedAssignedCompanyId = null;
      _selectedAssignedServerIds = <int>{};
      _selectedAssignedQueryIds = <int>{};
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
    _refreshReportFilterOptions();
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
                            : _displayCompanyName(_companyProfile.companyName),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (_companyProfile.companyAddress.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(
                            _displayCompanyAddress(_companyProfile.companyAddress),
                          ),
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
                  pw.Text('Query: ${_displayQueryName(report.queryName)}'),
                  pw.Text('Server: ${report.serverName}'),
                  pw.Text('Executed: ${_formatTimestamp(report.executedAt)}'),
                  pw.Text(
                    'Time Taken: ${_formatElapsedDuration(report.elapsedMs)}',
                  ),
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
      return _tr('VitalPro Reporting', 'وائٹل پرو رپورٹنگ');
    }

    switch (_adminSection) {
      case AdminPanelSection.dashboard:
        return _tr('VitalPro Admin', 'وائٹل پرو ایڈمن');
      case AdminPanelSection.companies:
        return _tr('Admin - Companies', 'ایڈمن - کمپنیاں');
      case AdminPanelSection.users:
        return _tr('Admin - Users', 'ایڈمن - صارفین');
      case AdminPanelSection.servers:
        return _tr('Admin - SQL Servers', 'ایڈمن - SQL سرورز');
      case AdminPanelSection.queries:
        return _tr('Admin - Queries', 'ایڈمن - کوئریز');
    }
  }

  String _adminSectionLabel(AdminPanelSection section) {
    switch (section) {
      case AdminPanelSection.dashboard:
        return _tr('Dashboard', 'ڈیش بورڈ');
      case AdminPanelSection.companies:
        return _tr('Companies', 'کمپنیاں');
      case AdminPanelSection.users:
        return _tr('Users', 'صارفین');
      case AdminPanelSection.servers:
        return _tr('SQL Servers', 'SQL سرورز');
      case AdminPanelSection.queries:
        return _tr('Queries', 'کوئریز');
    }
  }

  IconData _adminSectionIcon(AdminPanelSection section) {
    switch (section) {
      case AdminPanelSection.dashboard:
        return Icons.space_dashboard_outlined;
      case AdminPanelSection.companies:
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
                _healthMessage ??
                (_apiBaseUrl.trim().isEmpty
                    ? _tr(
                        'API connection is not configured.',
                        'API کنکشن کنفیگر نہیں ہے۔',
                      )
                    : _tr('API configured.', 'API کنفیگر ہے۔')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                (_healthMessage ?? '').toLowerCase().contains('could not') ||
                        _apiBaseUrl.trim().isEmpty
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
            ),
          ),
          Tooltip(
            message:
                _tr(
                  'Signed in as ${widget.session.user.username} (${_roleLabel(widget.session.user.role)})',
                  '${widget.session.user.username} کے طور پر سائن اِن ہے (${_roleLabel(widget.session.user.role)})',
                ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.account_circle_outlined),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: _tr('Change language', 'زبان تبدیل کریں'),
            onSelected: (value) {
              widget.onLocaleChanged(
                value == 'ur'
                    ? const Locale('ur', 'PK')
                    : const Locale('en', 'US'),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ur', child: Text('اردو')),
            ],
            icon: const Icon(Icons.language_outlined),
          ),
          IconButton(
            tooltip: _tr('Reload', 'ری لوڈ'),
            onPressed: _isLoading || _isBusy ? null : _loadBootstrap,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _tr('Sign out', 'سائن آؤٹ'),
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
        : _deriveChartData(
            _reportResult!,
            labelColumn: _chartLabelColumn,
            valueColumns: _chartValueColumns,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final horizontalPadding = constraints.maxWidth >= 1400 ? 8.0 : 12.0;
        final verticalPadding = constraints.maxWidth >= 1400 ? 10.0 : 14.0;
        final panelGap = isWide ? 12.0 : 16.0;
        final leftPanel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCompanyCard(),
            const SizedBox(height: 16),
            _buildFilterCard(),
          ],
        );
        final rightPanel = _buildResultsCard(chartData);

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: leftPanel),
                    SizedBox(width: panelGap),
                    Expanded(flex: 8, child: rightPanel),
                  ],
                )
              : ListView(
                  children: [leftPanel, SizedBox(height: panelGap), rightPanel],
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
        padding: const EdgeInsets.all(18),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _companyProfile.companyName.trim().isEmpty
                      ? _tr(
                          'Client reporting workspace',
                          'کلائنٹ رپورٹنگ ورک اسپیس',
                        )
                      : _displayCompanyName(_companyProfile.companyName),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A2540),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _companyProfile.companyAddress.trim().isEmpty
                      ? _tr(
                          'Save the client company name, address, and logo from Admin.',
                          'کلائنٹ کمپنی کا نام، پتہ، اور لوگو ایڈمن سے محفوظ کریں۔',
                        )
                      : _displayCompanyAddress(_companyProfile.companyAddress),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4F6478),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  identityBlock,
                  const SizedBox(height: 14),
                  detailsBlock,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(child: identityBlock),
                const SizedBox(height: 14),
                Center(child: detailsBlock),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tr('Report Controls', 'رپورٹ کنٹرولز'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 12),
            if (_servers.isEmpty)
              _buildEmptyMessage(
                _tr(
                  'No SQL servers saved yet.',
                  'ابھی تک کوئی SQL سرور محفوظ نہیں کیا گیا۔',
                ),
              )
            else
              RadioGroup<int>(
                groupValue: _selectedServerId,
                onChanged: (value) {
                  setState(() {
                    _selectedServerId = value;
                    _reportResult = null;
                  });
                  _refreshReportFilterOptions();
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
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
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
                      ? _tr(
                          'Choose a server first.',
                          'پہلے ایک سرور منتخب کریں۔',
                        )
                      : _tr(
                          'Selected server: ${selectedServer.label}',
                          'منتخب سرور: ${selectedServer.label}',
                        ),
                  style: Theme.of(context).textTheme.bodyMedium,
                );
                final actionButton = OutlinedButton.icon(
                  onPressed: selectedServer == null ? null : _setDefaultServer,
                  icon: const Icon(Icons.star_outline),
                  label: Text(_tr('Set Default', 'ڈیفالٹ بنائیں')),
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
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedQueryId,
              items: _queries
                  .where((query) => query.id != null)
                  .map(
                    (query) => DropdownMenuItem<int>(
                      value: query.id,
                      child: Text(_displayQueryName(query.queryName)),
                    ),
                  )
                  .toList(),
              onChanged: _queries.isEmpty ? null : _onQueryChanged,
              decoration: InputDecoration(
                labelText: _tr('Saved query', 'محفوظ کوئری'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            if (selectedQuery != null && selectedQuery.filters.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...selectedQuery.filters.map(_buildReportFilterInput),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showChart,
              onChanged: (value) {
                setState(() {
                  _showChart = value ?? false;
                });
              },
              title: Text(
                _tr(
                  'Show chart if the result is chartable',
                  'اگر نتیجہ چارٹ کے قابل ہو تو چارٹ دکھائیں',
                ),
              ),
              subtitle: Text(
                selectedQuery == null
                    ? _tr(
                        'Select a query to use its default chart preference.',
                        'ڈیفالٹ چارٹ ترجیح استعمال کرنے کے لیے کوئری منتخب کریں۔',
                      )
                    : selectedQuery.showChartByDefault
                    ? _tr(
                        'This query is saved to show a chart by default.',
                        'یہ کوئری ڈیفالٹ طور پر چارٹ دکھانے کے لیے محفوظ ہے۔',
                      )
                    : _tr(
                        'This query is saved without a default chart.',
                        'یہ کوئری بغیر ڈیفالٹ چارٹ کے محفوظ ہے۔',
                      ),
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              _buildStatusBanner(_statusMessage!),
            ],
            const SizedBox(height: 16),
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
                label: Text(_tr('Run Report', 'رپورٹ چلائیں')),
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
        padding: const EdgeInsets.all(18),
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
                      _tr('Report Output', 'رپورٹ آؤٹ پٹ'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0A2540),
                          ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    IconButton(
                      onPressed: result == null ? null : _printReport,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      tooltip: _tr('Print', 'پرنٹ'),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                    ),
                    IconButton(
                      onPressed: result == null ? null : _exportReportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      tooltip: _tr('Export PDF', 'PDF ایکسپورٹ کریں'),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                    ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [summary, const SizedBox(height: 8), actions],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            if (result == null)
              _buildEmptyMessage(
                _tr(
                  'No report results yet. Run a saved query to load a table and optional chart.',
                  'ابھی تک رپورٹ کے نتائج موجود نہیں۔ جدول اور اختیاری چارٹ لوڈ کرنے کے لیے محفوظ کوئری چلائیں۔',
                ),
              )
            else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildMetricChip(_tr('Server', 'سرور'), result.serverName),
                  _buildMetricChip(
                    _tr('Query', 'کوئری'),
                    _displayQueryName(result.queryName),
                  ),
                  _buildMetricChip(_tr('Rows', 'قطاریں'), '${result.rowCount}'),
                  _buildMetricChip(
                    _tr('Executed', 'اجراء'),
                    _formatTimestamp(result.executedAt),
                  ),
                  _buildMetricChip(
                    _tr('Time Taken', 'لگا ہوا وقت'),
                    _formatElapsedDuration(result.elapsedMs),
                  ),
                ],
              ),
              if (_showChart) ...[
                const SizedBox(height: 16),
                if (chartData == null)
                  _buildStatusBanner(_buildChartUnavailableMessage(result))
                else ...[
                  _buildChartOptionsCard(result),
                  const SizedBox(height: 12),
                  _buildChartCard(chartData),
                ],
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _openReportViewer(result),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -2,
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: Text(_tr('Open Report Viewer', 'رپورٹ ویور کھولیں')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
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
      case AdminPanelSection.companies:
        return [
          _buildAdminPageIntro(
            title: _tr('Companies & Clients', 'کمپنیاں اور کلائنٹس'),
            description:
                _tr(
                  'Add multiple client companies and maintain each client profile separately.',
                  'متعدد کلائنٹ کمپنیز شامل کریں اور ہر کلائنٹ پروفائل کو الگ سے منظم کریں۔',
                ),
          ),
          const SizedBox(height: 20),
          _buildCompanyAdminCard(),
          const SizedBox(height: 20),
          _buildSavedCompaniesCard(),
        ];
      case AdminPanelSection.users:
        return [
          _buildAdminPageIntro(
            title: _tr('User Management', 'صارف انتظام'),
            description:
                _tr(
                  'Create, update, and review application accounts from one place.',
                  'ایک ہی جگہ سے ایپلیکیشن اکاؤنٹس بنائیں، اپڈیٹ کریں، اور جائزہ لیں۔',
                ),
          ),
          const SizedBox(height: 20),
          _buildUserAdminCard(),
          const SizedBox(height: 20),
          _buildSavedUsersCard(),
        ];
      case AdminPanelSection.servers:
        return [
          _buildAdminPageIntro(
            title: _tr('SQL Server Management', 'SQL سرور انتظام'),
            description:
                _tr(
                  'Configure MSSQL connections and maintain the saved server library.',
                  'MSSQL کنکشنز کنفیگر کریں اور محفوظ سرور لائبریری کو برقرار رکھیں۔',
                ),
          ),
          const SizedBox(height: 20),
          _buildServerAdminCard(),
          const SizedBox(height: 20),
          _buildSavedServersCard(),
        ];
      case AdminPanelSection.queries:
        return [
          _buildAdminPageIntro(
            title: _tr('Query Management', 'کوئری انتظام'),
            description:
                _tr(
                  'Maintain reusable SQL queries and their reporting filters.',
                  'دوبارہ قابل استعمال SQL کوئریز اور ان کے رپورٹنگ فلٹرز کو منظم کریں۔',
                ),
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
                  VitalProLogo(
                    size: 56,
                    subtitle: _tr('Admin Workspace', 'ایڈمن ورک اسپیس'),
                  ),
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
                    _tr(
                      'Use the drawer to open each admin area separately.',
                      'ہر ایڈمن سیکشن الگ سے کھولنے کے لیے ڈراور استعمال کریں۔',
                    ),
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
    final companyName = _companies.isEmpty
        ? _tr('No client companies yet', 'ابھی کوئی کلائنٹ کمپنی نہیں')
        : _tr(
            '${_companies.length} client companies',
            '${_companies.length} کلائنٹ کمپنیاں',
          );

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
                VitalProLogo(
                  size: 72,
                  subtitle: _tr('Admin Workspace', 'ایڈمن ورک اسپیس'),
                ),
                const SizedBox(height: 18),
                Text(
                  _tr('Operational Control Center', 'آپریشنل کنٹرول سینٹر'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tr(
                    'Manage client identity, user access, SQL connections, and reusable reporting queries from one controlled workspace.',
                    'ایک کنٹرول شدہ ورک اسپیس سے کلائنٹ شناخت، صارف رسائی، SQL کنکشنز، اور محفوظ رپورٹنگ کوئریز منظم کریں۔',
                  ),
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
                    _tr('Current profile', 'موجودہ پروفائل'),
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
                    text: _tr(
                      '${_users.length} user accounts available',
                      '${_users.length} صارف اکاؤنٹس دستیاب',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildHeroMetaRow(
                    icon: Icons.storage_outlined,
                    text: _tr(
                      '${_servers.length} SQL endpoints configured',
                      '${_servers.length} SQL اینڈ پوائنٹس کنفیگر ہیں',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildHeroMetaRow(
                    icon: Icons.description_outlined,
                    text: _tr(
                      '${_queries.length} saved report queries',
                      '${_queries.length} محفوظ رپورٹ کوئریز',
                    ),
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
              _tr('Admin Sections', 'ایڈمن حصے'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _tr(
                'A polished overview of your core admin data, with quick entry points for the areas that need attention.',
                'آپ کے بنیادی ایڈمن ڈیٹا کا جامع جائزہ، اور ان حصوں کے لیے فوری راستے جہاں توجہ درکار ہے۔',
              ),
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
                      label: _tr('Client Companies', 'کلائنٹ کمپنیاں'),
                      value: '${_companies.length}',
                      caption: _companies.isEmpty
                          ? _tr(
                              'No client companies have been added yet.',
                              'ابھی تک کوئی کلائنٹ کمپنی شامل نہیں کی گئی۔',
                            )
                          : _tr(
                              'Client records are available for assignment and reporting.',
                              'کلائنٹ ریکارڈز تفویض اور رپورٹنگ کے لیے دستیاب ہیں۔',
                            ),
                      icon: Icons.business_outlined,
                      accent: const Color(0xFFE8F1F8),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: _tr('User Accounts', 'صارف اکاؤنٹس'),
                      value: '${_users.length}',
                      caption: _tr(
                        '${_users.where((user) => user.isActive).length} active accounts currently available.',
                        'اس وقت ${_users.where((user) => user.isActive).length} فعال اکاؤنٹس دستیاب ہیں۔',
                      ),
                      icon: Icons.people_alt_outlined,
                      accent: const Color(0xFFEAF5F1),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: _tr('SQL Servers', 'SQL سرورز'),
                      value: '${_servers.length}',
                      caption: _servers.isEmpty
                          ? _tr(
                              'No MSSQL servers connected yet.',
                              'ابھی تک کوئی MSSQL سرور منسلک نہیں ہوا۔',
                            )
                          : _tr(
                              'Saved endpoints are ready for reporting sessions.',
                              'محفوظ اینڈ پوائنٹس رپورٹنگ سیشنز کے لیے تیار ہیں۔',
                            ),
                      icon: Icons.storage_outlined,
                      accent: const Color(0xFFF4ECFA),
                      width: tileWidth,
                    ),
                    _buildOverviewStatCard(
                      label: _tr('Saved Queries', 'محفوظ کوئریز'),
                      value: '${_queries.length}',
                      caption: _queries.isEmpty
                          ? _tr(
                              'No reusable SQL query library yet.',
                              'ابھی تک دوبارہ استعمال کے قابل SQL کوئری لائبریری موجود نہیں۔',
                            )
                          : _tr(
                              'Report query catalog is available for runtime use.',
                              'رپورٹ کوئری کیٹلاگ رَن ٹائم استعمال کے لیے دستیاب ہے۔',
                            ),
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
            _tr('Quick Actions', 'فوری اقدامات'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              'Jump directly into the area that usually needs the next administrative update.',
              'براہ راست اس حصے میں جائیں جہاں عموماً اگلی انتظامی اپڈیٹ درکار ہوتی ہے۔',
            ),
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
                label: _tr('Manage Companies', 'کمپنیاں منظم کریں'),
                section: AdminPanelSection.companies,
                isPrimary: true,
              ),
              _buildDashboardActionButton(
                icon: Icons.people_alt_outlined,
                label: _tr('Manage Users', 'صارفین منظم کریں'),
                section: AdminPanelSection.users,
              ),
              _buildDashboardActionButton(
                icon: Icons.storage_outlined,
                label: _tr('Review Servers', 'سرورز دیکھیں'),
                section: AdminPanelSection.servers,
              ),
              _buildDashboardActionButton(
                icon: Icons.description_outlined,
                label: _tr('Open Queries', 'کوئریز کھولیں'),
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
    void onPressed() {
      setState(() {
        _adminSection = section;
      });
    }

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
        title: _tr('Client companies', 'کلائنٹ کمپنیاں'),
        ready: _companies.isNotEmpty,
      ),
      (title: _tr('User access', 'صارف رسائی'), ready: _users.isNotEmpty),
      (title: _tr('SQL connectivity', 'SQL کنیکٹیویٹی'), ready: _servers.isNotEmpty),
      (title: _tr('Query library', 'کوئری لائبریری'), ready: _queries.isNotEmpty),
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
            _tr('Operational Readiness', 'آپریشنل تیاری'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              'A quick health snapshot of the configuration needed for a smooth reporting workflow.',
              'ہموار رپورٹنگ ورک فلو کے لیے درکار کنفیگریشن کی فوری حالت۔',
            ),
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
                    _tr('API Status', 'API اسٹیٹس'),
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
          ready ? _tr('Ready', 'تیار') : _tr('Needs setup', 'سیٹ اپ درکار ہے'),
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
              _tr('Company Profile', 'کمپنی پروفائل'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _companyNameController,
              label: _tr('Company name', 'کمپنی کا نام'),
              hint: _tr('VitalPro Client', 'وائٹل پرو کلائنٹ'),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _companyAddressController,
              label: _tr('Company address', 'کمپنی کا پتہ'),
              hint: _tr(
                'Office address shown on the report header',
                'رپورٹ ہیڈر میں دکھایا جانے والا دفتر کا پتہ',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _companyLogoController,
              label: _tr('Company logo URL', 'کمپنی لوگو URL'),
              hint: 'https://example.com/logo.png',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBusy ? null : _saveCompanyProfile,
                  icon: Icon(
                    _editingCompanyId == null
                        ? Icons.add_business_outlined
                        : Icons.save_outlined,
                  ),
                  label: Text(
                    _editingCompanyId == null
                        ? _tr('Create Company', 'کمپنی بنائیں')
                        : _tr('Update Company', 'کمپنی اپڈیٹ کریں'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetCompanyForm,
                  icon: const Icon(Icons.refresh),
                  label: Text(_tr('Clear', 'صاف کریں')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedCompaniesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tr('Saved Companies', 'محفوظ کمپنیاں'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_companies.isEmpty)
              _buildEmptyMessage(
                _tr(
                  'No client companies saved yet.',
                  'ابھی تک کوئی کلائنٹ کمپنی محفوظ نہیں کی گئی۔',
                ),
              )
            else
              ..._companies.map(
                (company) => Container(
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
                              company.companyName.trim().isEmpty
                                  ? _tr('Unnamed company', 'بے نام کمپنی')
                                  : _displayCompanyName(company.companyName),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _tr('Edit company', 'کمپنی میں ترمیم کریں'),
                            onPressed: () => _loadCompanyForEditing(company),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: _tr('Delete company', 'کمپنی حذف کریں'),
                            onPressed: () => _deleteCompany(company),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        company.companyAddress.trim().isEmpty
                            ? _tr(
                                'No company address saved.',
                                'کمپنی کا کوئی پتہ محفوظ نہیں۔',
                              )
                            : _displayCompanyAddress(company.companyAddress),
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
              _tr('SQL Server Setup', 'SQL سرور سیٹ اپ'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _serverNameController,
              label: _tr('Server label', 'سرور لیبل'),
              hint: 'Head Office ERP',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverHostController,
              label: _tr('Server host', 'سرور ہوسٹ'),
              hint: '192.168.1.10 or SQLSERVER01',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverPortController,
              label: _tr('Port', 'پورٹ'),
              hint: '1433',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _serverDatabaseController,
              label: _tr('Database name', 'ڈیٹابیس کا نام'),
              hint: 'ERPDB',
            ),
            const SizedBox(height: 20),
            SegmentedButton<AuthenticationMode>(
              segments: [
                ButtonSegment(
                  value: AuthenticationMode.sqlServer,
                  label: Text(_tr('SQL Login', 'SQL لاگ اِن')),
                  icon: Icon(Icons.key_outlined),
                ),
                ButtonSegment(
                  value: AuthenticationMode.windows,
                  label: Text(_tr('Windows Auth', 'ونڈوز تصدیق')),
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
                label: _tr('Username', 'صارف نام'),
                hint: 'sa',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _serverPasswordController,
                label: _tr('Password', 'پاس ورڈ'),
                hint: _tr('SQL login password', 'SQL لاگ اِن پاس ورڈ'),
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
                        ? _tr('Save SQL Server', 'SQL سرور محفوظ کریں')
                        : _tr('Update Server', 'سرور اپڈیٹ کریں'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetServerForm,
                  icon: const Icon(Icons.refresh),
                  label: Text(_tr('Clear', 'صاف کریں')),
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
              _tr('App Users', 'ایپ صارفین'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _userUsernameController,
              label: _tr('Username', 'صارف نام'),
              hint: 'saleuser',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              key: ValueKey('assigned-company-${_selectedAssignedCompanyId ?? 'none'}'),
              initialValue: _selectedAssignedCompanyId,
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(_tr('Unassigned', 'غیر تفویض شدہ')),
                ),
                ..._companies
                    .where((company) => company.id != null)
                    .map(
                      (company) => DropdownMenuItem<int?>(
                        value: company.id,
                        child: Text(company.companyName),
                      ),
                    ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedAssignedCompanyId = value;
                });
              },
              decoration: InputDecoration(
                labelText: _tr('Assigned company', 'تفویض کردہ کمپنی'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: _tr(
                  'Assigned database servers',
                  'تفویض کردہ ڈیٹابیس سرورز',
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              child: _servers.isEmpty
                  ? Text(
                      _tr(
                        'No SQL servers available yet.',
                        'ابھی تک کوئی SQL سرور دستیاب نہیں۔',
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedAssignedServerIds.isEmpty
                              ? [
                                  Chip(
                                    label: Text(
                                      _tr('Unassigned', 'غیر تفویض شدہ'),
                                    ),
                                  ),
                                ]
                              : _servers
                                  .where(
                                    (server) =>
                                        server.id != null &&
                                        _selectedAssignedServerIds.contains(
                                          server.id,
                                        ),
                                  )
                                  .map(
                                    (server) => Chip(label: Text(server.label)),
                                  )
                                  .toList(),
                        ),
                        const SizedBox(height: 12),
                        ..._servers
                            .where((server) => server.id != null)
                            .map(
                              (server) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _selectedAssignedServerIds.contains(
                                  server.id,
                                ),
                                onChanged: (selected) {
                                  setState(() {
                                    final nextIds =
                                        _selectedAssignedServerIds.toSet();
                                    if (selected ?? false) {
                                      nextIds.add(server.id!);
                                    } else {
                                      nextIds.remove(server.id);
                                    }
                                    _selectedAssignedServerIds = nextIds;
                                  });
                                },
                                title: Text(server.label),
                                subtitle: Text(
                                  '${server.host}:${server.port} · ${server.databaseName}',
                                ),
                              ),
                            ),
                        if (_selectedAssignedServerIds.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedAssignedServerIds = <int>{};
                                });
                              },
                              icon: const Icon(Icons.clear_all),
                              label: Text(
                                _tr('Clear selected servers', 'منتخب سرور صاف کریں'),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: _tr(
                  'Assigned report queries',
                  'تفویض کردہ رپورٹ کوئریز',
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              child: _queries.isEmpty
                  ? Text(
                      _tr(
                        'No report queries available yet.',
                        'ابھی تک کوئی رپورٹ کوئری دستیاب نہیں۔',
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedAssignedQueryIds.isEmpty
                              ? [
                                  Chip(
                                    label: Text(
                                      _tr('Unassigned', 'غیر تفویض شدہ'),
                                    ),
                                  ),
                                ]
                              : _queries
                                  .where(
                                    (query) =>
                                        query.id != null &&
                                        _selectedAssignedQueryIds.contains(
                                          query.id,
                                        ),
                                  )
                                  .map(
                                    (query) =>
                                        Chip(label: Text(query.queryName)),
                                  )
                                  .toList(),
                        ),
                        const SizedBox(height: 12),
                        ..._queries
                            .where((query) => query.id != null)
                            .map(
                              (query) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _selectedAssignedQueryIds.contains(
                                  query.id,
                                ),
                                onChanged: (selected) {
                                  setState(() {
                                    final nextIds =
                                        _selectedAssignedQueryIds.toSet();
                                    if (selected ?? false) {
                                      nextIds.add(query.id!);
                                    } else {
                                      nextIds.remove(query.id);
                                    }
                                    _selectedAssignedQueryIds = nextIds;
                                  });
                                },
                                title: Text(query.queryName),
                              ),
                            ),
                        if (_selectedAssignedQueryIds.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedAssignedQueryIds = <int>{};
                                });
                              },
                              icon: const Icon(Icons.clear_all),
                              label: Text(
                                _tr('Clear selected queries', 'منتخب کوئریز صاف کریں'),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _userPasswordController,
              label: _editingUserId == null
                  ? _tr('Password', 'پاس ورڈ')
                  : _tr(
                      'Password (leave blank to keep current)',
                      'پاس ورڈ (موجودہ رکھنے کے لیے خالی چھوڑ دیں)',
                    ),
              hint: _editingUserId == null
                  ? _tr('Enter user password', 'صارف کا پاس ورڈ درج کریں')
                  : _tr('Optional new password', 'اختیاری نیا پاس ورڈ'),
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
                      child: Text(_roleLabel(role)),
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
              decoration: InputDecoration(
                labelText: _tr('Role', 'کردار'),
                border: const OutlineInputBorder(),
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
              title: Text(_tr('Active account', 'فعال اکاؤنٹ')),
              subtitle: Text(
                _tr(
                  'Inactive users cannot sign in until re-enabled.',
                  'غیر فعال صارف دوبارہ فعال ہونے تک سائن اِن نہیں کر سکتے۔',
                ),
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
                    _editingUserId == null
                        ? _tr('Create User', 'صارف بنائیں')
                        : _tr('Update User', 'صارف اپڈیٹ کریں'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetUserForm,
                  icon: const Icon(Icons.refresh),
                  label: Text(_tr('Clear', 'صاف کریں')),
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
              _tr('User Directory', 'صارف فہرست'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_users.isEmpty)
              _buildEmptyMessage(
                _tr('No app users found yet.', 'ابھی تک کوئی ایپ صارف نہیں ملا۔'),
              )
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
                            tooltip: _tr('Edit user', 'صارف میں ترمیم کریں'),
                            onPressed: () => _loadUserForEditing(user),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: _tr('Delete user', 'صارف حذف کریں'),
                            onPressed: user.id == widget.session.user.id
                                ? null
                                : () => _deleteUser(user),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        _tr(
                          'Role: ${_roleLabel(user.role)}',
                          'کردار: ${_roleLabel(user.role)}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'Assigned company: ${user.assignedCompanyName.trim().isEmpty ? 'Unassigned' : user.assignedCompanyName}',
                          'تفویض کردہ کمپنی: ${user.assignedCompanyName.trim().isEmpty ? 'غیر تفویض شدہ' : user.assignedCompanyName}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'Assigned database servers: ${user.assignedServerNames.isEmpty ? 'Unassigned' : user.assignedServerNames.join(', ')}',
                          'تفویض کردہ ڈیٹابیس سرورز: ${user.assignedServerNames.isEmpty ? 'غیر تفویض شدہ' : user.assignedServerNames.join(', ')}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'Assigned report queries: ${user.assignedQueryNames.isEmpty ? 'Unassigned' : user.assignedQueryNames.join(', ')}',
                          'تفویض کردہ رپورٹ کوئریز: ${user.assignedQueryNames.isEmpty ? 'غیر تفویض شدہ' : user.assignedQueryNames.join(', ')}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.isActive
                            ? _tr('Status: active', 'حالت: فعال')
                            : _tr('Status: inactive', 'حالت: غیر فعال'),
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
              _tr('Saved SQL Servers', 'محفوظ SQL سرورز'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_servers.isEmpty)
              _buildEmptyMessage(
                _tr(
                  'No SQL servers saved in MySQL yet.',
                  'ابھی تک MySQL میں کوئی SQL سرور محفوظ نہیں کیا گیا۔',
                ),
              )
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
                            tooltip: _tr('Edit server', 'سرور میں ترمیم کریں'),
                            onPressed: () => _loadServerForEditing(server),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: _tr('Delete server', 'سرور حذف کریں'),
                            onPressed: () => _deleteServer(server),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text('${server.host}:${server.port}'),
                      const SizedBox(height: 4),
                      Text(
                        _tr(
                          'Database: ${server.databaseName}',
                          'ڈیٹابیس: ${server.databaseName}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _authenticationModeLabel(
                          server.authenticationMode,
                          username: server.username,
                        ),
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
              _tr('Saved Queries', 'محفوظ کوئریز'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _queryNameController,
              label: _tr('Query name', 'کوئری کا نام'),
              hint: 'Show Product',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _queryTextController,
              label: _tr('SQL query', 'SQL کوئری'),
              hint:
                  'SELECT * FROM products WHERE DocumentDate = {{DocumentDate}}',
              maxLines: 8,
            ),
            const SizedBox(height: 12),
            _buildStatusBanner(
              _tr(
                'Use placeholders like {{DocumentDate}} inside the SQL. Filters can be text/date inputs or dropdowns backed by an options query, and the reporting screen will show matching filter fields above Run Report.',
                'SQL کے اندر {{DocumentDate}} جیسے پلیس ہولڈرز استعمال کریں۔ فلٹرز متن/تاریخ کے اندراج یا options query سے چلنے والے ڈراپ ڈاؤن ہو سکتے ہیں، اور رپورٹنگ اسکرین Run Report کے اوپر متعلقہ فلٹر فیلڈز دکھائے گی۔',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _tr('Query Filters', 'کوئری فلٹرز'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _addQueryFilter,
                  icon: const Icon(Icons.add),
                  label: Text(_tr('Add Filter', 'فلٹر شامل کریں')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_queryFilters.isEmpty)
              _buildEmptyMessage(
                _tr(
                  'No filters added yet. Example: add a date filter with key DocumentDate and use {{DocumentDate}} in the SQL.',
                  'ابھی تک کوئی فلٹر شامل نہیں کیا گیا۔ مثال کے طور پر DocumentDate key کے ساتھ تاریخ فلٹر شامل کریں اور SQL میں {{DocumentDate}} استعمال کریں۔',
                ),
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
              title: Text(_tr('Show chart by default', 'چارٹ بطور ڈیفالٹ دکھائیں')),
              subtitle: Text(
                _tr(
                  'The reporting page will automatically enable the chart toggle for this query.',
                  'رپورٹنگ صفحہ اس کوئری کے لیے چارٹ ٹوگل خودکار طور پر فعال کر دے گا۔',
                ),
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
                    _editingQueryId == null
                        ? _tr('Save Query', 'کوئری محفوظ کریں')
                        : _tr('Update Query', 'کوئری اپڈیٹ کریں'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _resetQueryForm,
                  icon: const Icon(Icons.refresh),
                  label: Text(_tr('Clear', 'صاف کریں')),
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
              _tr('Query Library', 'کوئری لائبریری'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_queries.isEmpty)
              _buildEmptyMessage(
                _tr(
                  'No report queries saved in MySQL yet.',
                  'ابھی تک MySQL میں کوئی رپورٹ کوئری محفوظ نہیں کی گئی۔',
                ),
              )
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
                              _displayQueryName(query.queryName),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _tr('Edit query', 'کوئری میں ترمیم کریں'),
                            onPressed: () => _loadQueryForEditing(query),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: _tr('Delete query', 'کوئری حذف کریں'),
                            onPressed: () => _deleteQuery(query),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        query.queryText.trim().isEmpty
                            ? _tr(
                                'Query text hidden until admin data is loaded.',
                                'ایڈمن ڈیٹا لوڈ ہونے تک کوئری ٹیکسٹ مخفی ہے۔',
                              )
                            : query.queryText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.showChartByDefault
                            ? _tr(
                                'Chart default: enabled',
                                'چارٹ ڈیفالٹ: فعال',
                              )
                            : _tr(
                                'Chart default: disabled',
                                'چارٹ ڈیفالٹ: غیر فعال',
                              ),
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
                                    '${filter.label} (${_queryFilterTypeLabel(filter.type)})',
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

  Future<void> _openReportViewer(ReportResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ReportViewerDialog(
        result: result,
        locale: widget.locale,
        onPrint: _printReport,
        onExportPdf: _exportReportPdf,
      ),
    );
  }

  Future<void> _openChartViewer(_ChartData chartData) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ChartViewerDialog(
        chartData: chartData,
        initialVisualType: _chartVisualType,
        locale: widget.locale,
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
                ? _tr('dd-MMM-yyyy', 'dd-MMM-yyyy')
                : filter.placeholder,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              tooltip: _tr('Pick date', 'تاریخ منتخب کریں'),
              onPressed: () => _pickDateFilterValue(filter),
              icon: const Icon(Icons.calendar_today_outlined),
            ),
          ),
        ),
      );
    }

    if (filter.inputType == QueryFilterInputType.dropdown) {
      final options = _reportFilterOptions[filter.key] ?? const <String>[];
      final isLoading = _loadingReportFilterOptions.contains(filter.key);
      final currentValue = controller.text.trim();
      final effectiveValue = currentValue.isEmpty || options.contains(currentValue)
          ? currentValue
          : null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: effectiveValue?.isEmpty == true ? null : effectiveValue,
          decoration: InputDecoration(
            labelText: label,
            hintText: filter.placeholder.isEmpty
                ? _tr(
                    'Select ${filter.label.toLowerCase()}',
                    '${filter.label} منتخب کریں',
                  )
                : filter.placeholder,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: _tr('Refresh values', 'ویلیوز ریفریش کریں'),
                    onPressed: () => _refreshReportFilterOptions(filterKey: filter.key),
                    icon: const Icon(Icons.refresh_outlined),
                  ),
          ),
          items: [
            if (!filter.isRequired)
              DropdownMenuItem<String>(
                value: '',
                child: Text(_tr('All', 'تمام')),
              ),
            ...options.map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
            ),
          ],
          onChanged: (value) {
            controller.text = (value ?? '').trim();
            setState(() {});
          },
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
                  _tr('Filter ${index + 1}', 'فلٹر ${index + 1}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: _tr('Remove filter', 'فلٹر ہٹائیں'),
                onPressed: _isBusy ? null : () => _removeQueryFilter(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.keyController,
            label: _tr('Filter key', 'فلٹر key'),
            hint: 'DocumentDate',
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.labelController,
            label: _tr('Filter label', 'فلٹر label'),
            hint: _tr('Document Date', 'دستاویز کی تاریخ'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<QueryFilterType>(
            initialValue: filter.type,
            items: QueryFilterType.values
                .map(
                  (type) => DropdownMenuItem<QueryFilterType>(
                    value: type,
                    child: Text(_queryFilterTypeLabel(type)),
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
            decoration: InputDecoration(
              labelText: _tr('Filter type', 'فلٹر کی قسم'),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<QueryFilterInputType>(
            initialValue: filter.inputType,
            items: QueryFilterInputType.values
                .map(
                  (inputType) => DropdownMenuItem<QueryFilterInputType>(
                    value: inputType,
                    child: Text(_queryFilterInputModeLabel(inputType)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final nextFilter = filter.copyWith(inputType: value);
              setState(() {
                _queryFilters[index] = nextFilter;
              });
              filter.dispose();
            },
            decoration: InputDecoration(
              labelText: _tr('Input mode', 'ان پٹ موڈ'),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.placeholderController,
            label: _tr('Placeholder', 'پلیس ہولڈر'),
            hint: filter.type == QueryFilterType.date
                ? 'dd-MMM-yyyy'
                : _tr('Optional hint', 'اختیاری اشارہ'),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: filter.defaultValueController,
            label: _tr('Default value', 'ڈیفالٹ ویلیو'),
            hint: filter.type == QueryFilterType.date
                ? '09-Feb-2026'
                : _tr('Optional default', 'اختیاری ڈیفالٹ'),
          ),
          if (filter.inputType == QueryFilterInputType.dropdown) ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: filter.optionsQueryController,
              label: _tr('Options query', 'آپشنز کوئری'),
              hint:
                  'SELECT DISTINCT SubsideryTitle FROM ... WHERE CAST(DocumentDate AS date) = {{DocumentDate}} ORDER BY 1',
              maxLines: 5,
            ),
          ],
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
            title: Text(_tr('Required filter', 'لازمی فلٹر')),
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
                .map((column) => DataColumn(label: Text(_displayLabel(column))))
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
        .expand((point) => point.values.values)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final seriesTotals = chartData.seriesTotals;
    final totalValue = seriesTotals.values.fold<double>(0, (sum, value) => sum + value);
    final chartColors = [
      const Color(0xFF2563EB),
      const Color(0xFFDC2626),
      const Color(0xFF059669),
      const Color(0xFFD97706),
      const Color(0xFF7C3AED),
      const Color(0xFFDB2777),
      const Color(0xFF0891B2),
      const Color(0xFF65A30D),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 640;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Chart Preview', 'چارٹ پری ویو'),
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tr(
                      'Type: ${_chartVisualType == _ChartVisualType.bar ? 'Bar' : 'Pie'}  -  Label: ${_displayLabel(chartData.labelColumn)}  -  Values: ${chartData.valueColumns.map(_displayLabel).join(', ')}',
                      'قسم: ${_chartVisualType == _ChartVisualType.bar ? 'بار' : 'پائی'}  -  لیبل: ${_displayLabel(chartData.labelColumn)}  -  ویلیوز: ${chartData.valueColumns.map(_displayLabel).join(', ')}',
                    ),
                  ),
                ],
              );
              final actionBlock = SegmentedButton<_ChartVisualType>(
                segments: [
                  ButtonSegment<_ChartVisualType>(
                    value: _ChartVisualType.bar,
                    icon: Icon(Icons.bar_chart_rounded),
                    label: Text(_tr('Bar', 'بار')),
                  ),
                  ButtonSegment<_ChartVisualType>(
                    value: _ChartVisualType.pie,
                    icon: Icon(Icons.pie_chart_rounded),
                    label: Text(_tr('Pie', 'پائی')),
                  ),
                ],
                selected: {_chartVisualType},
                onSelectionChanged: (selection) {
                  setState(() {
                    _chartVisualType = selection.first;
                  });
                },
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    actionBlock,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 12),
                  actionBlock,
                ],
              );
            },
          ),
          if (chartData.truncated) ...[
            const SizedBox(height: 4),
            Text(
              _tr(
                'Showing the first ${chartData.points.length} rows for readability.',
                'آسان مطالعہ کے لیے پہلی ${chartData.points.length} قطاریں دکھائی جا رہی ہیں۔',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4F6478)),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _tr(
              'Double-tap the chart to open it in a larger viewer.',
              'چارٹ کو بڑے ویور میں کھولنے کے لیے اسے دو بار تھپتھپائیں۔',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5E7688)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8E2EC)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.functions_rounded,
                  size: 18,
                  color: Color(0xFF355468),
                ),
                const SizedBox(width: 10),
                Text(
                  _tr('Total Amount', 'کل رقم'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF355468),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  totalValue.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF0A2540),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onDoubleTap: () => _openChartViewer(chartData),
            child: SizedBox(
              height: 260,
              child: _chartVisualType == _ChartVisualType.bar
                  ? BarChart(
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
                              barsSpace: 6,
                              barRods: [
                                for (var seriesIndex = 0;
                                    seriesIndex < chartData.valueColumns.length;
                                    seriesIndex++)
                                  BarChartRodData(
                                    toY: chartData.points[index].values[
                                            chartData.valueColumns[seriesIndex]] ??
                                        0,
                                    width: 12,
                                    borderRadius: BorderRadius.circular(6),
                                    color: chartColors[
                                        seriesIndex % chartColors.length],
                                  ),
                              ],
                            ),
                      ],
                    ),
                  )
                : PieChart(
                      PieChartData(
                        centerSpaceRadius: 34,
                      sectionsSpace: 2,
                      sections: [
                        for (var index = 0;
                            index < chartData.valueColumns.length;
                            index++)
                          PieChartSectionData(
                            color: chartColors[index % chartColors.length],
                            value: seriesTotals[chartData.valueColumns[index]] ?? 0,
                            radius: 90,
                            title: totalValue <= 0
                                ? (seriesTotals[chartData.valueColumns[index]] ?? 0)
                                    .toStringAsFixed(0)
                                : '${((((seriesTotals[chartData.valueColumns[index]] ?? 0) / totalValue) * 100)).toStringAsFixed(1)}%',
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          if (_chartVisualType == _ChartVisualType.pie) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (var index = 0; index < chartData.valueColumns.length; index++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: chartColors[index % chartColors.length],
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_displayLabel(chartData.valueColumns[index])}: ${(seriesTotals[chartData.valueColumns[index]] ?? 0).toStringAsFixed(2)}',
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var index = 0; index < chartData.valueColumns.length; index++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: chartColors[index % chartColors.length],
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_displayLabel(chartData.valueColumns[index])),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartOptionsCard(ReportResult result) {
    final labelOptions = [
      DropdownMenuItem<String>(
        value: _rowLabelColumnKey,
        child: Text(_tr('Row number', 'قطار نمبر')),
      ),
      ...result.columns.map(
        (column) => DropdownMenuItem<String>(
          value: column,
          child: Text(_displayLabel(column)),
        ),
      ),
    ];
    final valueColumns = _numericChartColumns(result);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('Chart Options', 'چارٹ آپشنز'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _tr(
              'Choose which columns to use for chart labels and values at runtime.',
              'رَن ٹائم پر چارٹ لیبلز اور ویلیوز کے لیے استعمال ہونے والے کالم منتخب کریں۔',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 640;
              final labelField = DropdownButtonFormField<String>(
                initialValue: _chartLabelColumn,
                decoration: InputDecoration(
                  labelText: _tr('Label column', 'لیبل کالم'),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: labelOptions,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _chartLabelColumn = value;
                  });
                },
              );
              final valueField = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFC7D2E0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Value columns', 'ویلیو کالمز'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF355468),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: valueColumns
                          .map(
                            (column) => FilterChip(
                              label: Text(_displayLabel(column)),
                              selected: _chartValueColumns.contains(column),
                              onSelected: (selected) {
                                setState(() {
                                  final next = List<String>.from(
                                    _chartValueColumns,
                                  );
                                  if (selected) {
                                    if (!next.contains(column)) {
                                      next.add(column);
                                    }
                                  } else {
                                    next.remove(column);
                                  }
                                  _chartValueColumns = next;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );

              if (isCompact) {
                return Column(
                  children: [
                    labelField,
                    const SizedBox(height: 12),
                    valueField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: labelField),
                  const SizedBox(width: 12),
                  Expanded(child: valueField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _buildChartUnavailableMessage(ReportResult result) {
    final valueColumns = _numericChartColumns(result);
    if (valueColumns.isEmpty) {
      return _tr(
        'Chart preview is enabled, but the result set needs at least one numeric column.',
        'چارٹ پری ویو فعال ہے، لیکن نتیجے کے مجموعے میں کم از کم ایک عددی کالم ہونا چاہیے۔',
      );
    }
    return _tr(
      'Chart preview is enabled, but the selected chart columns do not produce any numeric points.',
      'چارٹ پری ویو فعال ہے، لیکن منتخب چارٹ کالمز کوئی عددی پوائنٹس پیدا نہیں کرتے۔',
    );
  }

  _ChartSelection _resolveChartSelection(ReportResult result) {
    final valueColumns = _numericChartColumns(result);
    final selectedValueColumns = _preferredChartValueColumns(valueColumns);
    final labelColumn = result.columns.any(
            (column) => !selectedValueColumns.contains(column))
        ? result.columns.firstWhere(
            (column) => !selectedValueColumns.contains(column),
          )
        : _rowLabelColumnKey;
    return _ChartSelection(
      labelColumn: labelColumn,
      valueColumns: selectedValueColumns,
    );
  }

  List<String> _preferredChartValueColumns(List<String> valueColumns) {
    final normalized = {
      for (final column in valueColumns) column.toLowerCase(): column,
    };
    final cash = normalized['cash_amount'];
    final credit = normalized['credit_amount'];
    final total = normalized['total'];

    if (cash != null && credit != null) {
      return [cash, credit];
    }

    if (cash != null && total != null) {
      return [cash];
    }

    if (credit != null && total != null) {
      return [credit];
    }

    return valueColumns.take(3).toList(growable: false);
  }

  List<String> _numericChartColumns(ReportResult result) {
    return result.columns
        .where((column) => result.rows.any((row) => _asDouble(row[column]) != null))
        .toList();
  }

  _ChartData? _deriveChartData(
    ReportResult result, {
    required String labelColumn,
    required List<String> valueColumns,
  }) {
    if (result.rows.isEmpty || result.columns.isEmpty) {
      return null;
    }

    if (valueColumns.isEmpty) {
      return null;
    }
    final safeValueColumns = valueColumns
        .where((column) => result.columns.contains(column))
        .toList(growable: false);
    if (safeValueColumns.isEmpty) {
      return null;
    }

    const limit = 12;
    final points = <_ChartPoint>[];
    final seriesTotals = <String, double>{
      for (final column in safeValueColumns) column: 0,
    };
    for (
      var index = 0;
      index < result.rows.length && points.length < limit;
      index++
    ) {
      final row = result.rows[index];
      final values = <String, double>{};
      for (final column in safeValueColumns) {
        final value = _asDouble(row[column]);
        if (value != null) {
          values[column] = value;
          seriesTotals[column] = (seriesTotals[column] ?? 0) + value;
        }
      }
      if (values.isEmpty) {
        continue;
      }
      final rawLabel = labelColumn == _rowLabelColumnKey
          ? _tr('Row ${index + 1}', 'قطار ${index + 1}')
          : _formatCell(row[labelColumn]);
      points.add(_ChartPoint(_trimLabel(rawLabel), values));
    }

    if (points.isEmpty) {
      return null;
    }

    return _ChartData(
      labelColumn:
          labelColumn == _rowLabelColumnKey
              ? _tr('Row number', 'قطار نمبر')
              : _displayLabel(labelColumn),
      valueColumns: safeValueColumns,
      points: points,
      truncated: result.rows.length > points.length,
      seriesTotals: seriesTotals,
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

  String _formatElapsedDuration(int? elapsedMs) {
    if (elapsedMs == null || elapsedMs < 0) {
      return 'N/A';
    }
    final minutes = elapsedMs ~/ 60000;
    final seconds = (elapsedMs % 60000) ~/ 1000;
    final milliseconds = elapsedMs % 1000;
    return '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s '
        '${milliseconds.toString().padLeft(3, '0')}ms';
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E2EC)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, height: 1.1),
      ),
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
    required this.valueColumns,
    required this.points,
    required this.truncated,
    required this.seriesTotals,
  });

  final String labelColumn;
  final List<String> valueColumns;
  final List<_ChartPoint> points;
  final bool truncated;
  final Map<String, double> seriesTotals;
}

class _ChartPoint {
  const _ChartPoint(this.label, this.values);

  final String label;
  final Map<String, double> values;
}

class _ChartSelection {
  const _ChartSelection({
    required this.labelColumn,
    required this.valueColumns,
  });

  final String labelColumn;
  final List<String> valueColumns;
}

class _ReportViewerDialog extends StatefulWidget {
  const _ReportViewerDialog({
    required this.result,
    required this.locale,
    required this.onPrint,
    required this.onExportPdf,
  });

  final ReportResult result;
  final Locale locale;
  final Future<void> Function() onPrint;
  final Future<void> Function() onExportPdf;

  @override
  State<_ReportViewerDialog> createState() => _ReportViewerDialogState();
}

class _ReportViewerDialogState extends State<_ReportViewerDialog> {
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1;
  bool get _isUrdu => widget.locale.languageCode == 'ur';
  String _tr(String en, String ur) => _isUrdu ? ur : en;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _setScale(double value) {
    final nextScale = value.clamp(0.75, 3.0);
    _transformationController.value = Matrix4.identity()..scale(nextScale);
    setState(() {
      _scale = nextScale;
    });
  }

  void _zoomIn() => _setScale(_scale + 0.2);

  void _zoomOut() => _setScale(_scale - 0.2);

  void _resetZoom() => _setScale(1);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xFFF3F7FB),
      child: SizedBox(
        width: 1200,
        height: 760,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 760;
                  final summary = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('Report Viewer', 'رپورٹ ویور'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A2540),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tr(
                          '${_localizedQueryName(widget.result.queryName, isUrdu: _isUrdu)}  -  ${widget.result.rowCount} row(s)',
                          '${_localizedQueryName(widget.result.queryName, isUrdu: _isUrdu)}  -  ${widget.result.rowCount} قطاریں',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF4F6478),
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ViewerIconButton(
                        onPressed: _zoomOut,
                        tooltip: _tr('Zoom out', 'زوم آؤٹ'),
                        icon: Icons.zoom_out_rounded,
                      ),
                      _ViewerIconButton(
                        onPressed: _resetZoom,
                        tooltip: _tr('Reset zoom', 'زوم ری سیٹ کریں'),
                        icon: Icons.center_focus_strong_rounded,
                        badge: '${(_scale * 100).round()}%',
                      ),
                      _ViewerIconButton(
                        onPressed: _zoomIn,
                        tooltip: _tr('Zoom in', 'زوم اِن'),
                        icon: Icons.zoom_in_rounded,
                      ),
                      _ViewerIconButton(
                        onPressed: widget.onPrint,
                        tooltip: _tr('Print', 'پرنٹ'),
                        icon: Icons.print_outlined,
                      ),
                      _ViewerIconButton(
                        onPressed: widget.onExportPdf,
                        tooltip: _tr('Export PDF', 'PDF ایکسپورٹ کریں'),
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                      _ViewerIconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: _tr('Close', 'بند کریں'),
                        icon: Icons.close_rounded,
                        isPrimary: true,
                      ),
                    ],
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [summary, const SizedBox(height: 12), actions],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 12),
                      Flexible(child: actions),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: _tr('Server', 'سرور'),
                    value: widget.result.serverName,
                  ),
                  _MetricChip(
                    label: _tr('Executed', 'اجراء'),
                    value: _formatViewerTimestamp(widget.result.executedAt),
                  ),
                  _MetricChip(
                    label: _tr('Time Taken', 'لگا ہوا وقت'),
                    value: _formatViewerElapsed(widget.result.elapsedMs),
                  ),
                  _MetricChip(
                    label: _tr('Rows', 'قطاریں'),
                    value: '${widget.result.rowCount}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFF6FAFD)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCFE0EC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140B3353),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.75,
                      maxScale: 3,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor:
                                WidgetStateProperty.resolveWith<Color?>(
                              (_) => const Color(0xFFDCEAF4),
                            ),
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 52,
                            columnSpacing: 24,
                            columns: widget.result.columns
                                .map(
                                  (column) => DataColumn(
                                    label: Text(
                                      _localizedReportLabel(
                                        column,
                                        isUrdu: _isUrdu,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF103B5C),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            rows: widget.result.rows
                                .asMap()
                                .map(
                                  (index, row) => MapEntry(
                                    index,
                                    DataRow(
                                      color: WidgetStateProperty.resolveWith<
                                          Color?>(
                                        (_) => index.isEven
                                            ? const Color(0xFFFFFFFF)
                                            : const Color(0xFFF7FBFE),
                                      ),
                                      cells: widget.result.columns
                                          .map(
                                            (column) => DataCell(
                                              Text(
                                                (row[column] ?? '').toString(),
                                                style: const TextStyle(
                                                  color: Color(0xFF29465B),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                )
                                .values
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartViewerDialog extends StatefulWidget {
  const _ChartViewerDialog({
    required this.chartData,
    required this.initialVisualType,
    required this.locale,
  });

  final _ChartData chartData;
  final _ChartVisualType initialVisualType;
  final Locale locale;

  @override
  State<_ChartViewerDialog> createState() => _ChartViewerDialogState();
}

class _ChartViewerDialogState extends State<_ChartViewerDialog> {
  late _ChartVisualType _visualType;
  bool get _isUrdu => widget.locale.languageCode == 'ur';
  String _tr(String en, String ur) => _isUrdu ? ur : en;

  static const _chartColors = [
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
  ];

  @override
  void initState() {
    super.initState();
    _visualType = widget.initialVisualType;
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = widget.chartData.points
        .expand((point) => point.values.values)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final seriesTotals = widget.chartData.seriesTotals;
    final totalValue = seriesTotals.values.fold<double>(0, (sum, value) => sum + value);

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xFFF3F7FB),
      child: SizedBox(
        width: 1080,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('Chart Viewer', 'چارٹ ویور'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0A2540),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Label: ${_localizedReportLabel(widget.chartData.labelColumn, isUrdu: _isUrdu)}  -  Values: ${widget.chartData.valueColumns.map((column) => _localizedReportLabel(column, isUrdu: _isUrdu)).join(', ')}',
                            'لیبل: ${_localizedReportLabel(widget.chartData.labelColumn, isUrdu: _isUrdu)}  -  ویلیوز: ${widget.chartData.valueColumns.map((column) => _localizedReportLabel(column, isUrdu: _isUrdu)).join(', ')}',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4F6478),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                        _ViewerIconButton(
                          onPressed: () {
                            setState(() {
                              _visualType = _ChartVisualType.bar;
                            });
                          },
                        tooltip: _tr('Bar chart', 'بار چارٹ'),
                        icon: Icons.bar_chart_rounded,
                        isPrimary: _visualType == _ChartVisualType.bar,
                      ),
                      _ViewerIconButton(
                          onPressed: () {
                            setState(() {
                              _visualType = _ChartVisualType.pie;
                            });
                          },
                        tooltip: _tr('Pie chart', 'پائی چارٹ'),
                        icon: Icons.pie_chart_rounded,
                        isPrimary: _visualType == _ChartVisualType.pie,
                      ),
                      _ViewerIconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: _tr('Close', 'بند کریں'),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD8E2EC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.functions_rounded,
                      size: 18,
                      color: Color(0xFF355468),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _tr('Total Amount', 'کل رقم'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF355468),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      totalValue.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF0A2540),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFFFF), Color(0xFFF6FAFD)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCFE0EC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140B3353),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _visualType == _ChartVisualType.bar
                        ? BarChart(
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
                                    reservedSize: 48,
                                    getTitlesWidget: (value, meta) => Text(
                                      value.toStringAsFixed(0),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 56,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index < 0 ||
                                          index >= widget.chartData.points.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Transform.rotate(
                                          angle: -0.42,
                                          child: Text(
                                            widget.chartData.points[index].label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              barGroups: [
                                for (var index = 0;
                                    index < widget.chartData.points.length;
                                    index++)
                                  BarChartGroupData(
                                    x: index,
                                    barsSpace: 6,
                                    barRods: [
                                      for (var seriesIndex = 0;
                                          seriesIndex <
                                              widget.chartData.valueColumns.length;
                                          seriesIndex++)
                                        BarChartRodData(
                                          toY: widget.chartData.points[index].values[
                                                  widget.chartData.valueColumns[
                                                      seriesIndex]] ??
                                              0,
                                          width: 16,
                                          borderRadius: BorderRadius.circular(8),
                                          color: _chartColors[
                                              seriesIndex % _chartColors.length],
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              Expanded(
                                child: PieChart(
                                  PieChartData(
                                    centerSpaceRadius: 48,
                                    sectionsSpace: 3,
                                    sections: [
                                      for (var index = 0;
                                          index < widget.chartData.valueColumns.length;
                                          index++)
                                        PieChartSectionData(
                                          color:
                                              _chartColors[index % _chartColors.length],
                                          value:
                                              seriesTotals[widget.chartData.valueColumns[index]] ?? 0,
                                          radius: 120,
                                          title: totalValue <= 0
                                              ? (seriesTotals[widget.chartData.valueColumns[index]] ?? 0)
                                                  .toStringAsFixed(0)
                                              : '${((((seriesTotals[widget.chartData.valueColumns[index]] ?? 0) / totalValue) * 100)).toStringAsFixed(1)}%',
                                          titleStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 14,
                                runSpacing: 10,
                                children: [
                                  for (var index = 0;
                                      index < widget.chartData.valueColumns.length;
                                      index++)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _chartColors[
                                                index % _chartColors.length],
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${_localizedReportLabel(widget.chartData.valueColumns[index], isUrdu: _isUrdu)}: ${(seriesTotals[widget.chartData.valueColumns[index]] ?? 0).toStringAsFixed(2)}',
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _localizedReportLabel(String value, {required bool isUrdu}) {
  if (!isUrdu) {
    return value;
  }

  switch (value.trim().toLowerCase()) {
    case 'cash':
    case 'cash_amount':
      return 'نقد';
    case 'credit':
    case 'credit_amount':
      return 'ادھار';
    case 'amount':
    case 'total':
    case 'total_amount':
      return 'رقم';
    case 'documentdate':
      return 'دستاویز کی تاریخ';
    default:
      return value;
  }
}

String _localizedQueryName(String value, {required bool isUrdu}) {
  if (!isUrdu) {
    return value;
  }

  switch (value.trim().toLowerCase()) {
    case 'sales by payment mode':
      return 'ادائیگی کے طریقے کے لحاظ سے فروخت';
    case 'branch wise sale summary':
      return 'برانچ کے لحاظ سے فروخت کا خلاصہ';
    case 'pending bag details':
      return 'زیر التوا بیگ کی تفصیلات';
    default:
      return value;
  }
}

String _formatViewerTimestamp(String value) {
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

String _formatViewerElapsed(int? elapsedMs) {
  if (elapsedMs == null || elapsedMs < 0) {
    return 'N/A';
  }
  final minutes = elapsedMs ~/ 60000;
  final seconds = (elapsedMs % 60000) ~/ 1000;
  final milliseconds = elapsedMs % 1000;
  return '${minutes.toString().padLeft(2, '0')}m '
      '${seconds.toString().padLeft(2, '0')}s '
      '${milliseconds.toString().padLeft(3, '0')}ms';
}

class _ViewerIconButton extends StatelessWidget {
  const _ViewerIconButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    this.badge,
    this.isPrimary = false,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;
  final String? badge;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final iconButton = Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF103B5C) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFF103B5C)
                : const Color(0xFFD0DEE8),
          ),
        ),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 18,
            color: isPrimary ? Colors.white : const Color(0xFF27485F),
          ),
        ),
      ),
    );

    if (badge == null) {
      return iconButton;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconButton,
        const SizedBox(width: 4),
        Text(
          badge!,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF486173),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
}

class _EditableQueryFilter {
  _EditableQueryFilter({
    String key = '',
    String label = '',
    this.type = QueryFilterType.text,
    this.inputType = QueryFilterInputType.text,
    this.isRequired = false,
    String placeholder = '',
    String defaultValue = '',
    String optionsQuery = '',
  }) : keyController = TextEditingController(text: key),
       labelController = TextEditingController(text: label),
       placeholderController = TextEditingController(text: placeholder),
       defaultValueController = TextEditingController(text: defaultValue),
       optionsQueryController = TextEditingController(text: optionsQuery);

  factory _EditableQueryFilter.fromDefinition(QueryFilterDefinition filter) {
    return _EditableQueryFilter(
      key: filter.key,
      label: filter.label,
      type: filter.type,
      inputType: filter.inputType,
      isRequired: filter.isRequired,
      placeholder: filter.placeholder,
      defaultValue: filter.defaultValue,
      optionsQuery: filter.optionsQuery,
    );
  }

  final TextEditingController keyController;
  final TextEditingController labelController;
  final TextEditingController placeholderController;
  final TextEditingController defaultValueController;
  final TextEditingController optionsQueryController;
  final QueryFilterType type;
  final QueryFilterInputType inputType;
  final bool isRequired;

  _EditableQueryFilter copyWith({
    QueryFilterType? type,
    QueryFilterInputType? inputType,
    bool? isRequired,
  }) {
    return _EditableQueryFilter(
      key: keyController.text,
      label: labelController.text,
      type: type ?? this.type,
      inputType: inputType ?? this.inputType,
      isRequired: isRequired ?? this.isRequired,
      placeholder: placeholderController.text,
      defaultValue: defaultValueController.text,
      optionsQuery: optionsQueryController.text,
    );
  }

  QueryFilterDefinition toDefinition() {
    return QueryFilterDefinition(
      key: keyController.text.trim(),
      label: labelController.text.trim(),
      type: type,
      inputType: inputType,
      isRequired: isRequired,
      placeholder: placeholderController.text.trim(),
      defaultValue: defaultValueController.text.trim(),
      optionsQuery: optionsQueryController.text.trim(),
    );
  }

  void dispose() {
    keyController.dispose();
    labelController.dispose();
    placeholderController.dispose();
    defaultValueController.dispose();
    optionsQueryController.dispose();
  }
}
