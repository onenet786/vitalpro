import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _localePreferenceKey = 'app_locale_code';

  AuthSession? _session;
  bool _showIntro = true;
  Locale _locale = const Locale('en', 'US');

  bool get _isUrdu => _locale.languageCode == 'ur';

  @override
  void initState() {
    super.initState();
    _loadLocalePreference();
    Timer(const Duration(seconds: 15), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showIntro = false;
      });
    });
  }

  Future<void> _loadLocalePreference() async {
    final preferences = await SharedPreferences.getInstance();
    final localeCode = preferences.getString(_localePreferenceKey) ?? 'en';
    if (!mounted) {
      return;
    }

    setState(() {
      _locale = localeCode == 'ur'
          ? const Locale('ur', 'PK')
          : const Locale('en', 'US');
    });
  }

  Future<void> _setLocale(Locale locale) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_localePreferenceKey, locale.languageCode);
    if (!mounted) {
      return;
    }

    setState(() {
      _locale = locale;
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
      title: _isUrdu ? 'وائٹل پرو رپورٹنگ' : 'VitalPro Reporting',
      locale: _locale,
      supportedLocales: const [Locale('en', 'US'), Locale('ur', 'PK')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: _isUrdu ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: canvas,
        canvasColor: canvas,
        fontFamilyFallback: const [
          'Noto Nastaliq Urdu',
          'Noto Naskh Arabic',
          'Segoe UI',
          'Tahoma',
          'Arial Unicode MS',
        ],
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
              locale: _locale,
              onLocaleChanged: _setLocale,
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
          ? LaunchGatePage(
              onLogin: _setSession,
              locale: _locale,
              onLocaleChanged: _setLocale,
            )
          : ReportingHomePage(
              session: _session!,
              onLogout: _clearSession,
              homeMode: _session!.user.isAdmin
                  ? HomeMode.admin
                  : HomeMode.reporting,
              locale: _locale,
              onLocaleChanged: _setLocale,
            ),
    );
  }
}

class _AppIntroSplash extends StatefulWidget {
  const _AppIntroSplash({
    required this.locale,
    required this.onLocaleChanged,
    required this.onComplete,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onComplete;

  @override
  State<_AppIntroSplash> createState() => _AppIntroSplashState();
}

class _AppIntroSplashState extends State<_AppIntroSplash> {
  Timer? _slideTimer;
  int _currentIndex = 0;

  bool get _isUrdu => widget.locale.languageCode == 'ur';

  List<({String title, String description, IconData icon})> get _slides => [
    (
      title: _isUrdu ? 'وائٹل پرو رپورٹنگ' : 'VitalPro Reporting',
      description: _isUrdu
          ? 'روزمرہ کاروباری بصیرت، تیز تجزیہ، اور بہتر فیصلوں کے لیے ایک پیشہ ور رپورٹنگ پلیٹ فارم۔'
          : 'A professional reporting workspace for operational insight, fast analysis, and cleaner decision-making.',
      icon: Icons.insights_rounded,
    ),
    (
      title: _isUrdu ? 'اسمارٹ رپورٹس چلائیں' : 'Run Smart Reports',
      description: _isUrdu
          ? 'لچکدار فلٹرز، رہنمائی والے ان پٹس، اور متحرک انتخاب کے ساتھ دوبارہ قابل استعمال SQL رپورٹس چلائیں۔'
          : 'Launch reusable SQL-based reports with flexible filters, guided inputs, and dynamic selections.',
      icon: Icons.play_circle_outline_rounded,
    ),
    (
      title: _isUrdu ? 'نتائج کو بصری انداز میں دیکھیں' : 'Visualize Results',
      description: _isUrdu
          ? 'چارٹ پریویو، پائی اور بار ویوز، بڑی چارٹ ونڈوز، اور فوکسڈ رپورٹ ویور کے ساتھ ڈیٹا کا جائزہ لیں۔'
          : 'Review data with chart previews, pie and bar views, expandable chart windows, and focused report viewers.',
      icon: Icons.pie_chart_outline_rounded,
    ),
    (
      title: _isUrdu ? 'اعتماد کے ساتھ ایکسپورٹ کریں' : 'Export With Confidence',
      description: _isUrdu
          ? 'رپورٹس پرنٹ کریں، PDF ایکسپورٹ کریں، اور بڑی ٹیبلز کو الگ زوم ایبل ویور میں دیکھیں۔'
          : 'Print reports, export PDF outputs, and inspect large tables in a dedicated zoomable viewer.',
      icon: Icons.picture_as_pdf_outlined,
    ),
    (
      title: _isUrdu ? 'ٹیموں کے لیے تیار' : 'Built For Teams',
      description: _isUrdu
          ? 'ایک محفوظ ایڈمن ورک اسپیس سے SQL کنکشنز، محفوظ کوئریز، کمپنیز، اور یوزر ایکسس کو منظم کریں۔'
          : 'Manage SQL connections, saved queries, companies, and user access from one secure admin workspace.',
      icon: Icons.admin_panel_settings_outlined,
    ),
  ];

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: _isUrdu
                              ? 'زبان تبدیل کریں'
                              : 'Change language',
                          onSelected: (value) {
                            widget.onLocaleChanged(
                              value == 'ur'
                                  ? const Locale('ur', 'PK')
                                  : const Locale('en', 'US'),
                            );
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'en',
                              child: Text('English'),
                            ),
                            PopupMenuItem(value: 'ur', child: Text('اردو')),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            child: Text(
                              _isUrdu ? 'اردو' : 'English',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: widget.onComplete,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_isUrdu ? 'اسکپ' : 'Skip'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const VitalProLogo(size: 118, subtitle: ''),
                              const SizedBox(height: 8),
                              Text(
                                _isUrdu
                                    ? 'انٹرپرائز رپورٹنگ پلیٹ فارم'
                                    : 'Enterprise Reporting Platform',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: const Color(0xFFD6E6F0),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 28),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                child: Container(
                                  key: ValueKey('${widget.locale.languageCode}-$_currentIndex'),
                                  width: double.infinity,
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
                          child: Text(_isUrdu ? 'جاری رکھیں' : 'Continue'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isUrdu
                              ? 'نے اسے بنایا ہے  Vital Solutions'
                              : 'Powered by Vital Solutions',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _isUrdu
                              ? 'محفوظ کاروباری رپورٹنگ اور تجزیاتی حل کے لیے'
                              : 'For secure business reporting and analytics solutions.',
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
