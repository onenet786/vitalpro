import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'launch_gate.dart';
import 'report_models.dart';
import 'reporting_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const VitalProApp());
}

class VitalProApp extends StatefulWidget {
  const VitalProApp({super.key});

  @override
  State<VitalProApp> createState() => _VitalProAppState();
}

class _VitalProAppState extends State<VitalProApp> {
  AuthSession? _session;

  void _setSession(AuthSession session) {
    setState(() {
      _session = session;
    });
  }

  void _clearSession() {
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5D7A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VitalPro Reporting',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
        useMaterial3: true,
      ),
      home: _session == null
          ? LaunchGatePage(onLogin: _setSession)
          : ReportingHomePage(
              session: _session!,
              onLogout: _clearSession,
            ),
    );
  }
}
