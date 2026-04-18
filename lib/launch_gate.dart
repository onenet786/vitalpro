import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_client.dart';
import 'report_models.dart';
import 'vitalpro_logo.dart';

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({
    super.key,
    required this.onLogin,
    required this.locale,
    required this.onLocaleChanged,
  });

  final ValueChanged<AuthSession> onLogin;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

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
  bool get _isUrdu => widget.locale.languageCode == 'ur';
  String _tr(String en, String ur) => _isUrdu ? ur : en;

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
        _errorMessage = _tr(
          'Username and password are required.',
          'صارف نام اور پاس ورڈ درج کرنا ضروری ہے۔',
        );
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
                  errorMessage = _tr(
                    'All fields are required.',
                    'تمام خانے بھرنا ضروری ہیں۔',
                  );
                });
                return;
              }

              if (newPassword != confirmPassword) {
                setDialogState(() {
                  errorMessage = _tr(
                    'New password and confirm password must match.',
                    'نیا پاس ورڈ اور تصدیقی پاس ورڈ ایک جیسے ہونے چاہئیں۔',
                  );
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
                                    _tr(
                                      'Reset Password',
                                      'پاس ورڈ ری سیٹ کریں',
                                    ),
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
                                    _tr(
                                      'Confirm your current credentials, then choose a new password for secure access.',
                                      'پہلے اپنی موجودہ اسناد کی تصدیق کریں، پھر محفوظ رسائی کے لیے نیا پاس ورڈ منتخب کریں۔',
                                    ),
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
                              tooltip: _tr('Close', 'بند کریں'),
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
                                  _tr(
                                    'Your current password is required before the password can be updated.',
                                    'پاس ورڈ اپڈیٹ کرنے سے پہلے موجودہ پاس ورڈ درج کرنا ضروری ہے۔',
                                  ),
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
                          decoration: InputDecoration(
                            labelText: _tr('Username', 'صارف نام'),
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: currentPasswordController,
                          enabled: !isSubmitting,
                          obscureText: !showCurrentPassword,
                          decoration: InputDecoration(
                            labelText: _tr(
                              'Current password',
                              'موجودہ پاس ورڈ',
                            ),
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
                            labelText: _tr('New password', 'نیا پاس ورڈ'),
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
                            labelText: _tr(
                              'Confirm new password',
                              'نئے پاس ورڈ کی تصدیق کریں',
                            ),
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
                                child: Text(_tr('Cancel', 'منسوخ کریں')),
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
                                    : Text(
                                        _tr(
                                          'Update Password',
                                          'پاس ورڈ اپڈیٹ کریں',
                                        ),
                                      ),
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
        return _HowToUseVideoDialog(locale: widget.locale);
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: PopupMenuButton<String>(
                                tooltip: _tr(
                                  'Change language',
                                  'زبان تبدیل کریں',
                                ),
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
                                  PopupMenuItem(
                                    value: 'ur',
                                    child: Text('اردو'),
                                  ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: const Color(0xFFEAF2F7),
                                  ),
                                  child: Text(
                                    _isUrdu ? 'اردو' : 'English',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: const Color(0xFF103B5C),
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: VitalProLogo(
                                size: 88,
                                subtitle: _tr(
                                  'Secure Analytics',
                                  'محفوظ تجزیات',
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              _tr('Sign In', 'سائن اِن'),
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
                                labelText: _tr('Username', 'صارف نام'),
                                hintText: _tr(
                                  'Enter your username',
                                  'اپنا صارف نام درج کریں',
                                ),
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
                                labelText: _tr('Password', 'پاس ورڈ'),
                                hintText: _tr(
                                  'Enter your password',
                                  'اپنا پاس ورڈ درج کریں',
                                ),
                                errorText: _errorMessage,
                                suffixIcon: IconButton(
                                  tooltip: _isPasswordVisible
                                      ? _tr(
                                          'Hide password',
                                          'پاس ورڈ چھپائیں',
                                        )
                                      : _tr(
                                          'Show password',
                                          'پاس ورڈ دکھائیں',
                                        ),
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
                                    label: Text(
                                      _tr('How to Use', 'استعمال کا طریقہ'),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _isBusy
                                        ? null
                                        : _openResetPasswordDialog,
                                    child: Text(
                                      _tr(
                                        'Reset Password',
                                        'پاس ورڈ ری سیٹ کریں',
                                      ),
                                    ),
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
                                    : Text(_tr('Sign In', 'سائن اِن')),
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
class _HowToUseVideoDialog extends StatefulWidget {
  const _HowToUseVideoDialog({required this.locale});

  final Locale locale;

  @override
  State<_HowToUseVideoDialog> createState() => _HowToUseVideoDialogState();
}

class _HowToUseVideoDialogState extends State<_HowToUseVideoDialog> {
  bool get _isUrdu => widget.locale.languageCode == 'ur';
  String _tr(String en, String ur) => _isUrdu ? ur : en;

  List<({String title, String description, IconData icon, Color accent})>
  get _slides => [
    (
      title: _tr('Sign In', 'سائن اِن'),
      description: _tr(
        'Enter your reporting username and password on the login screen to access the reporting workspace.',
        'رپورٹنگ ورک اسپیس تک رسائی کے لیے لاگ اِن اسکرین پر اپنا صارف نام اور پاس ورڈ درج کریں۔',
      ),
      icon: Icons.login_rounded,
      accent: const Color(0xFF103B5C),
    ),
    (
      title: _tr('Choose Server', 'سرور منتخب کریں'),
      description: _tr(
        'Select the SQL server assigned for your reporting session before loading data.',
        'ڈیٹا لوڈ کرنے سے پہلے اپنی رپورٹنگ سیشن کے لیے مقرر کردہ SQL سرور منتخب کریں۔',
      ),
      icon: Icons.dns_rounded,
      accent: const Color(0xFF1E5A73),
    ),
    (
      title: _tr('Select Saved Query', 'محفوظ کوئری منتخب کریں'),
      description: _tr(
        'Pick the report query you want to run from the prepared list of reusable reports.',
        'دوبارہ استعمال کے قابل رپورٹس کی تیار فہرست میں سے وہ کوئری منتخب کریں جسے آپ چلانا چاہتے ہیں۔',
      ),
      icon: Icons.rule_folder_outlined,
      accent: const Color(0xFF2B6F89),
    ),
    (
      title: _tr('Fill Filters', 'فلٹرز بھریں'),
      description: _tr(
        'Choose dates, codes, and dropdown values to narrow the report to the records you need.',
        'اپنی مطلوبہ ریکارڈز تک رپورٹ محدود کرنے کے لیے تاریخیں، کوڈز، اور ڈراپ ڈاؤن ویلیوز منتخب کریں۔',
      ),
      icon: Icons.filter_alt_outlined,
      accent: const Color(0xFF2F855A),
    ),
    (
      title: _tr('Run and View', 'چلائیں اور دیکھیں'),
      description: _tr(
        'Tap Run Report to open the report viewer, inspect rows, zoom the table, and review results clearly.',
        'رپورٹ ویور کھولنے، قطاریں دیکھنے، جدول کو زوم کرنے، اور نتائج واضح طور پر جانچنے کے لیے Run Report دبائیں۔',
      ),
      icon: Icons.play_circle_outline_rounded,
      accent: const Color(0xFFD97706),
    ),
    (
      title: _tr('Analyze and Export', 'تجزیہ کریں اور ایکسپورٹ کریں'),
      description: _tr(
        'Use the chart preview for quick insight, open charts in a larger viewer, then print or export PDF.',
        'فوری سمجھ کے لیے چارٹ پری ویو استعمال کریں، چارٹس کو بڑے ویور میں کھولیں، پھر پرنٹ کریں یا PDF ایکسپورٹ کریں۔',
      ),
      icon: Icons.pie_chart_outline_rounded,
      accent: const Color(0xFF7C3AED),
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
                          _tr('How to Use', 'استعمال کا طریقہ'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0A2540),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Video-style walkthrough for a reporting user from login to viewing a report.',
                            'لاگ اِن سے رپورٹ دیکھنے تک رپورٹنگ صارف کے لیے ویڈیو طرز کی رہنمائی۔',
                          ),
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
                    tooltip: _tr('Close', 'بند کریں'),
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
                    child: Text(_tr('Got It', 'سمجھ گیا')),
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
    final isUrdu = Directionality.of(context) == TextDirection.rtl;
    String tr(String en, String ur) => isUrdu ? ur : en;

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
                    tr('Step $step', 'مرحلہ $step'),
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
                      tr(
                        'This walkthrough auto-plays like a short demo and can be swiped manually too.',
                        'یہ رہنمائی مختصر ڈیمو کی طرح خود بخود چلتی ہے اور آپ اسے ہاتھ سے بھی سلائیڈ کر سکتے ہیں۔',
                      ),
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
