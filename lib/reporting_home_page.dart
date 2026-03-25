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

enum _AppSection { reporting, admin }

class ReportingHomePage extends StatefulWidget {
  const ReportingHomePage({super.key});

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

  _AppSection _currentSection = _AppSection.reporting;
  AuthenticationMode _serverAuthenticationMode = AuthenticationMode.sqlServer;
  bool _showChart = false;
  bool _isLoading = true;
  bool _isBusy = false;
  bool _isAdminUnlocked = false;
  bool _isSqlPasswordVisible = false;
  bool _showQueryChartByDefault = false;
  String? _adminPassword;
  String? _statusMessage;
  String? _healthMessage;
  int? _selectedServerId;
  int? _selectedQueryId;
  int? _editingServerId;
  int? _editingQueryId;
  CompanyProfile _companyProfile = const CompanyProfile();
  List<ReportingServer> _servers = const [];
  List<SavedQuery> _queries = const [];
  ReportResult? _reportResult;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  ApiClient get _apiClient => ApiClient(baseUrl: _apiBaseUrl);

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
    super.dispose();
  }

  Future<void> _loadBootstrap() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final healthMessage = await _apiClient.fetchHealthMessage();
      final bootstrap = _isAdminUnlocked && _adminPassword != null
          ? await _apiClient.fetchAdminBootstrap(_adminPassword!)
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

      if (!mounted) {
        return;
      }

      setState(() {
        _companyProfile = bootstrap.companyProfile;
        _servers = bootstrap.servers;
        _queries = bootstrap.queries;
        _healthMessage = healthMessage;
        _selectedServerId = nextServerId;
        _selectedQueryId = nextQueryId;
        _showChart = selectedQuery?.showChartByDefault ?? false;
        _statusMessage = bootstrap.servers.isEmpty || bootstrap.queries.isEmpty
            ? 'Add at least one SQL server and one saved query from Admin before running reports.'
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
        _statusMessage = 'Could not load reporting configuration. Details: $error';
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
    setState(() {
      _selectedQueryId = queryId;
      _showChart = query?.showChartByDefault ?? false;
      _reportResult = null;
    });
  }

  Future<void> _runReport() async {
    final serverId = _selectedServerId;
    final queryId = _selectedQueryId;
    if (serverId == null || queryId == null) {
      _showSnack('Select one SQL server and one saved query first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Running report query...';
    });

    try {
      final result = await _apiClient.runReport(
        serverId: serverId,
        queryId: queryId,
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

  Future<void> _handleSectionChange(int index) async {
    if (index == 0) {
      setState(() {
        _currentSection = _AppSection.reporting;
      });
      return;
    }

    if (_isAdminUnlocked) {
      setState(() {
        _currentSection = _AppSection.admin;
      });
      return;
    }

    final password = await _promptForPassword();
    if (password == null || password.isEmpty) {
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Verifying admin password...';
    });

    try {
      final result = await _apiClient.verifyAdminPassword(password);
      if (!mounted) {
        return;
      }

      if (!result.success) {
        setState(() {
          _isBusy = false;
          _statusMessage = result.message;
        });
        _showSnack(result.message);
        return;
      }

      setState(() {
        _adminPassword = password;
        _isAdminUnlocked = true;
        _currentSection = _AppSection.admin;
        _isBusy = false;
        _statusMessage = result.message;
      });

      _resetServerForm();
      _resetQueryForm();
      await _loadBootstrap();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isBusy = false;
        _statusMessage = 'Admin verification failed. Details: $error';
      });
    }
  }

  Future<String?> _promptForPassword() async {
    final controller = TextEditingController();
    bool isVisible = false;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Admin Access'),
              content: TextField(
                controller: controller,
                obscureText: !isVisible,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Admin password',
                  hintText: 'OneNet25Mar2026',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setDialogState(() {
                        isVisible = !isVisible;
                      });
                    },
                    icon: Icon(
                      isVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                onSubmitted: (_) {
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return password;
  }

  Future<void> _saveCompanyProfile() async {
    final adminPassword = _adminPassword;
    if (adminPassword == null) {
      return;
    }

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
        adminPassword,
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
    final adminPassword = _adminPassword;
    if (adminPassword == null) {
      return;
    }

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
        adminPassword,
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
    final adminPassword = _adminPassword;
    if (adminPassword == null || server.id == null) {
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
      final result = await _apiClient.deleteServer(server.id!, adminPassword);
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
    final adminPassword = _adminPassword;
    if (adminPassword == null) {
      return;
    }

    if (_queryNameController.text.trim().isEmpty ||
        _queryTextController.text.trim().isEmpty) {
      _showSnack('Query name and SQL query text are required.');
      return;
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
        ),
        adminPassword,
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
    final adminPassword = _adminPassword;
    if (adminPassword == null || query.id == null) {
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
      final result = await _apiClient.deleteQuery(query.id!, adminPassword);
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
    setState(() {
      _editingQueryId = query.id;
      _showQueryChartByDefault = query.showChartByDefault;
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
    setState(() {
      _editingQueryId = null;
      _showQueryChartByDefault = false;
    });
  }

  void _handleAdminFailure(String message) {
    if (!mounted) {
      return;
    }

    final clearSession = message.toLowerCase().contains('admin password');
    setState(() {
      _isBusy = false;
      _statusMessage = message;
      if (clearSession) {
        _isAdminUnlocked = false;
        _adminPassword = null;
        _currentSection = _AppSection.reporting;
      }
    });
    _showSnack(message);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
            pw.Table.fromTextArray(
              headers: report.columns,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
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

  @override
  Widget build(BuildContext context) {
    final title = _currentSection == _AppSection.reporting
        ? 'VitalPro Reporting'
        : 'Admin Panel';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _isLoading || _isBusy ? null : _loadBootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _currentSection == _AppSection.reporting
            ? _buildReportingSection()
            : _buildAdminSection(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentSection == _AppSection.reporting ? 0 : 1,
        onDestinationSelected: _handleSectionChange,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(
              _isAdminUnlocked ? Icons.admin_panel_settings : Icons.lock_outline,
            ),
            selectedIcon: const Icon(Icons.admin_panel_settings),
            label: 'Admin',
          ),
        ],
      ),
    );
  }

  Widget _buildReportingSection() {
    final chartData = _reportResult == null ? null : _deriveChartData(_reportResult!);

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
                  children: [
                    leftPanel,
                    const SizedBox(height: 20),
                    rightPanel,
                  ],
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
                  : const Icon(
                      Icons.business_outlined,
                      size: 34,
                      color: Color(0xFF355468),
                    ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
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
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
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
              ),
            ),
          ],
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4F6478),
              ),
            ),
            const SizedBox(height: 20),
            if (_servers.isEmpty)
              _buildEmptyMessage('No SQL servers saved yet.')
            else
              ..._servers.map((server) {
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
                    groupValue: _selectedServerId,
                    onChanged: (value) {
                      setState(() {
                        _selectedServerId = value;
                        _reportResult = null;
                      });
                    },
                    title: Text(
                      server.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${server.host}:${server.port}  -  ${server.databaseName}',
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedServer == null
                        ? 'Choose a server first.'
                        : 'Selected server: ${selectedServer.label}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: selectedServer == null ? null : _setDefaultServer,
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Set Default'),
                ),
              ],
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
            Row(
              children: [
                Expanded(
                  child: Column(
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
                  ),
                ),
                Wrap(
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
                ),
              ],
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
      child: ListView(
        children: [
          _buildAdminHeader(),
          const SizedBox(height: 20),
          _buildCompanyAdminCard(),
          const SizedBox(height: 20),
          _buildServerAdminCard(),
          const SizedBox(height: 20),
          _buildSavedServersCard(),
          const SizedBox(height: 20),
          _buildQueryAdminCard(),
          const SizedBox(height: 20),
          _buildSavedQueriesCard(),
        ],
      ),
    );
  }

  Widget _buildAdminHeader() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Workspace',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Save client branding, maintain multiple MSSQL servers, and store reusable report queries in MySQL.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4F6478),
              ),
            ),
          ],
        ),
      ),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                    _editingServerId == null ? 'Save SQL Server' : 'Update Server',
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
              hint: 'SELECT * FROM products',
              maxLines: 8,
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                    ],
                  ),
                ),
              ),
          ],
        ),
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
                          (column) =>
                              DataCell(Text(_formatCell(row[column]))),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Label: ${chartData.labelColumn}  -  Value: ${chartData.valueColumn}',
          ),
          if (chartData.truncated) ...[
            const SizedBox(height: 4),
            Text(
              'Showing the first ${chartData.points.length} rows for readability.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF4F6478),
              ),
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
    for (var index = 0; index < result.rows.length && points.length < limit; index++) {
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
