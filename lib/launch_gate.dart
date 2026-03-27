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
  final _usernameController = TextEditingController(text: 'admin');
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

            return AlertDialog(
              title: const Text('Reset Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: currentPasswordController,
                      enabled: !isSubmitting,
                      obscureText: !showCurrentPassword,
                      decoration: InputDecoration(
                        labelText: 'Current password',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      enabled: !isSubmitting,
                      obscureText: !showNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New password',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      enabled: !isSubmitting,
                      obscureText: !showConfirmPassword,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        border: const OutlineInputBorder(),
                        errorText: errorMessage,
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset'),
                ),
              ],
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
                                hintText: 'admin',
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
                                hintText: 'Admin786',
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
                              child: TextButton(
                                onPressed: _isBusy
                                    ? null
                                    : _openResetPasswordDialog,
                                child: const Text('Reset Password'),
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
