import 'package:flutter/material.dart';

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLaunchPasswordVisible = false;

  String get _expectedPassword => buildExpectedPassword();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_passwordController.text.trim() != _expectedPassword) {
      setState(() {
        _errorMessage = 'Invalid launch password for today.';
      });
      return;
    }

    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Launch Security',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A2540),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter today\'s password in the format `OneNetDDMMMyyyy` to open the reporting app.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF4F6478),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isLaunchPasswordVisible,
                        onSubmitted: (_) => _unlock(),
                        decoration: InputDecoration(
                          labelText: 'Launch password',
                          hintText: 'OneNet25Mar2026',
                          errorText: _errorMessage,
                          suffixIcon: IconButton(
                            tooltip: _isLaunchPasswordVisible
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () {
                              setState(() {
                                _isLaunchPasswordVisible =
                                    !_isLaunchPasswordVisible;
                              });
                            },
                            icon: Icon(
                              _isLaunchPasswordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _unlock,
                          child: const Text('Unlock'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String buildExpectedPassword() {
  final now = DateTime.now();
  const months = <String>[
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

  final day = now.day.toString().padLeft(2, '0');
  final month = months[now.month - 1];
  final year = now.year.toString();
  return 'OneNet$day$month$year';
}
