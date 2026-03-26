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
    const primary = Color(0xFF103B5C);
    const secondary = Color(0xFF2F6B7A);
    const surface = Color(0xFFFFFFFF);
    const canvas = Color(0xFFF4F7FB);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: surface,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VitalPro Reporting',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: canvas,
        canvasColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: Color(0xFF102A43),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF0F2740),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFD9E2EC)),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFBFCFE),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFC7D2E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFC7D2E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: primary, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(color: Color(0xFFB8C7D9)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF243B53),
          displayColor: const Color(0xFF102A43),
        ),
        useMaterial3: true,
      ),
      home: _session == null
          ? LaunchGatePage(onLogin: _setSession)
          : ReportingHomePage(
              session: _session!,
              onLogout: _clearSession,
              homeMode: _session!.user.isAdmin
                  ? HomeMode.admin
                  : HomeMode.reporting,
            ),
    );
  }
}
