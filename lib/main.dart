import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'launch_gate.dart';
import 'report_models.dart';
import 'reporting_home_page.dart';
import 'vitalpro_logo.dart';

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
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 15), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showIntro = false;
      });
    });
  }

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
      home: _showIntro
          ? _AppIntroSplash(
              onComplete: () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _showIntro = false;
                });
              },
            )
          : _session == null
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

class _AppIntroSplash extends StatefulWidget {
  const _AppIntroSplash({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_AppIntroSplash> createState() => _AppIntroSplashState();
}

class _AppIntroSplashState extends State<_AppIntroSplash> {
  static const _slides = [
    (
      title: 'VitalPro Reporting',
      description:
          'A professional reporting workspace for operational insight, fast analysis, and cleaner decision-making.',
      icon: Icons.insights_rounded,
    ),
    (
      title: 'Run Smart Reports',
      description:
          'Launch reusable SQL-based reports with flexible filters, guided inputs, and dynamic selections.',
      icon: Icons.play_circle_outline_rounded,
    ),
    (
      title: 'Visualize Results',
      description:
          'Review data with chart previews, pie and bar views, expandable chart windows, and focused report viewers.',
      icon: Icons.pie_chart_outline_rounded,
    ),
    (
      title: 'Export With Confidence',
      description:
          'Print reports, export PDF outputs, and inspect large tables in a dedicated zoomable viewer.',
      icon: Icons.picture_as_pdf_outlined,
    ),
    (
      title: 'Built For Teams',
      description:
          'Manage SQL connections, saved queries, companies, and user access from one secure admin workspace.',
      icon: Icons.admin_panel_settings_outlined,
    ),
  ];

  Timer? _slideTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _slideTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentIndex = (_currentIndex + 1).clamp(0, _slides.length - 1);
      });
      if (_currentIndex == _slides.length - 1) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentIndex];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D314E), Color(0xFF184F68), Color(0xFF26738A)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -60,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              left: -80,
              bottom: -120,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7BE0D6).withValues(alpha: 0.10),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: widget.onComplete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const VitalProLogo(
                                size: 118,
                                subtitle: 'Enterprise Reporting Platform',
                              ),
                              const SizedBox(height: 28),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                child: Container(
                                  key: ValueKey(_currentIndex),
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(32),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.16),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                        child: Icon(
                                          slide.icon,
                                          size: 34,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        slide.title,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        slide.description,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: const Color(0xFFE4F0F8),
                                              height: 1.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  _slides.length,
                                  (index) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: index == _currentIndex ? 28 : 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: index == _currentIndex
                                          ? const Color(0xFF7BE0D6)
                                          : Colors.white.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        FilledButton(
                          onPressed: widget.onComplete,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF103B5C),
                          ),
                          child: const Text('Continue'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Powered by OneNet Solutions',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Serving for secure business reporting and analytics solutions.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFFD6E6F0),
                                fontSize: 10,
                                height: 1.2,
                              ),
                        ),
                      ],
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
}
