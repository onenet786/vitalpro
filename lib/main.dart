import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'launch_gate.dart';
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
  bool _isUnlocked = false;

  void _unlockSession() {
    if (!_isUnlocked) {
      setState(() {
        _isUnlocked = true;
      });
    }
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
      home: _isUnlocked
          ? const ReportingHomePage()
          : LaunchGatePage(onUnlock: _unlockSession),
    );
  }
}
