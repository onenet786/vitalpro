import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_client.dart';
import 'report_models.dart';
import 'vitalpro_logo.dart';

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key, required this.onLogin});

  final ValueChanged<AuthSession> onLogin;

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isBusy = false;
  bool _isPasswordVisible = false;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';
  ApiClient get _apiClient => ApiClient(baseUrl: _apiBaseUrl);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password are required.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      final session = await _apiClient.login(
        username: username,
        password: password,
      );
      if (!mounted) {
        return;
      }
      widget.onLogin(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBusy = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = false;
    });
  }

  Future<void> _openResetPasswordDialog() async {
    final usernameController = TextEditingController(
      text: _usernameController.text.trim(),
    );
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? errorMessage;
    bool isSubmitting = false;
    bool showCurrentPassword = false;
    bool showNewPassword = false;
    bool showConfirmPassword = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final username = usernameController.text.trim();
              final currentPassword = currentPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirmPassword = confirmPasswordController.text;

              if (username.isEmpty ||
                  currentPassword.isEmpty ||
                  newPassword.isEmpty ||
                  confirmPassword.isEmpty) {
                setDialogState(() {
                  errorMessage = 'All fields are required.';
                });
                return;
              }

              if (newPassword != confirmPassword) {
                setDialogState(() {
                  errorMessage = 'New password and confirm password must match.';
                });
                return;
              }

              setDialogState(() {
                isSubmitting = true;
                errorMessage = null;
              });

              try {
                final result = await _apiClient.resetPassword(
                  username: username,
                  currentPassword: currentPassword,
                  newPassword: newPassword,
                );
                if (!mounted) {
                  return;
                }
                Navigator.of(context).pop();
                setState(() {
                  _usernameController.text = username;
                  _passwordController.clear();
                  _errorMessage = result.message;
                });
              } catch (error) {
                setDialogState(() {
                  isSubmitting = false;
                  errorMessage = error.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE7F1F7),
                                    Color(0xFFD7E7F1),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_reset_rounded,
                                color: Color(0xFF103B5C),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Reset Password',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0A2540),
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Confirm your current credentials, then choose a new password for secure access.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF5D7285),
                                          height: 1.45,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFD),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD8E4EE)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.verified_user_outlined,
                                  size: 18,
                                  color: Color(0xFF355468),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your current password is required before the password can be updated.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF516A7B),
                                        height: 1.4,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: usernameController,
                          enabled: !isSubmitting,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: currentPasswordController,
                          enabled: !isSubmitting,
                          obscureText: !showCurrentPassword,
                          decoration: InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: const Icon(Icons.key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  showCurrentPassword = !showCurrentPassword;
                                });
                              },
                              icon: Icon(
                                showCurrentPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: newPasswordController,
                          enabled: !isSubmitting,
                          obscureText: !showNewPassword,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  showNewPassword = !showNewPassword;
                                });
                              },
                              icon: Icon(
                                showNewPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: confirmPasswordController,
                          enabled: !isSubmitting,
                          obscureText: !showConfirmPassword,
                          onSubmitted: (_) => submit(),
                          decoration: InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: const Icon(Icons.verified_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  showConfirmPassword = !showConfirmPassword;
                                });
                              },
                              icon: Icon(
                                showConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF3C7C2)),
                            ),
                            child: Text(
                              errorMessage!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFFB42318),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isSubmitting ? null : submit,
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Update Password'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    usernameController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _openHowToUseDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return const _HowToUseVideoDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
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
                            const Center(
                              child: VitalProLogo(
                                size: 88,
                                subtitle: 'Secure Analytics',
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Sign In',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0A2540),
                                  ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _usernameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                hintText: 'Enter your username',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: 'Enter your password',
                                errorText: _errorMessage,
                                suffixIcon: IconButton(
                                  tooltip: _isPasswordVisible
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: _isBusy
                                      ? null
                                      : () {
                                          setState(() {
                                            _isPasswordVisible =
                                                !_isPasswordVisible;
                                          });
                                        },
                                  icon: Icon(
                                    _isPasswordVisible
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _openHowToUseDialog,
                                    icon: const Icon(Icons.help_outline_rounded),
                                    label: const Text('How to Use'),
                                  ),
                                  TextButton(
                                    onPressed: _isBusy
                                        ? null
                                        : _openResetPasswordDialog,
                                    child: const Text('Reset Password'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _isBusy ? null : _login,
                                child: _isBusy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Sign In'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HowToUseStep extends StatelessWidget {
  const _HowToUseStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E5EE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF103B5C),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: const Color(0xFF355468)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0A2540),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5D7285),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToUseVideoDialog extends StatefulWidget {
  const _HowToUseVideoDialog();

  @override
  State<_HowToUseVideoDialog> createState() => _HowToUseVideoDialogState();
}

class _HowToUseVideoDialogState extends State<_HowToUseVideoDialog> {
  static const _slides = [
    (
      title: 'Sign In',
      description:
          'Enter your reporting username and password on the login screen to access the reporting workspace.',
      icon: Icons.login_rounded,
      accent: Color(0xFF103B5C),
    ),
    (
      title: 'Choose Server',
      description:
          'Select the SQL server assigned for your reporting session before loading data.',
      icon: Icons.dns_rounded,
      accent: Color(0xFF1E5A73),
    ),
    (
      title: 'Select Saved Query',
      description:
          'Pick the report query you want to run from the prepared list of reusable reports.',
      icon: Icons.rule_folder_outlined,
      accent: Color(0xFF2B6F89),
    ),
    (
      title: 'Fill Filters',
      description:
          'Choose dates, codes, and dropdown values to narrow the report to the records you need.',
      icon: Icons.filter_alt_outlined,
      accent: Color(0xFF2F855A),
    ),
    (
      title: 'Run and View',
      description:
          'Tap Run Report to open the report viewer, inspect rows, zoom the table, and review results clearly.',
      icon: Icons.play_circle_outline_rounded,
      accent: Color(0xFFD97706),
    ),
    (
      title: 'Analyze and Export',
      description:
          'Use the chart preview for quick insight, open charts in a larger viewer, then print or export PDF.',
      icon: Icons.pie_chart_outline_rounded,
      accent: Color(0xFF7C3AED),
    ),
  ];

  late final PageController _pageController;
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        return;
      }
      final next = (_currentIndex + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8F3F8), Color(0xFFD7E8F2)],
                      ),
                    ),
                    child: const Icon(
                      Icons.ondemand_video_rounded,
                      color: Color(0xFF103B5C),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to Use',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0A2540),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Video-style walkthrough for a reporting user from login to viewing a report.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5D7285),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return _HowToUseSlideCard(
                      step: index + 1,
                      title: slide.title,
                      description: slide.description,
                      icon: slide.icon,
                      accent: slide.accent,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: index == _currentIndex ? 26 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: index == _currentIndex
                                ? const Color(0xFF103B5C)
                                : const Color(0xFFD2DDE6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got It'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowToUseSlideCard extends StatelessWidget {
  const _HowToUseSlideCard({
    required this.step,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final int step;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.88)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Step $step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFF4F8FB),
                height: 1.5,
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.smart_display_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This walkthrough auto-plays like a short demo and can be swiped manually too.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        height: 1.45,
                      ),
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
}
