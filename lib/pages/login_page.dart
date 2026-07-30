import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/widgets/auth/auth_widgets.dart';
import 'package:shootiq/widgets/shootiq_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _navigateAfterAuth() async {
    if (!mounted) return;

    if (OnboardingService.hasCompletedOnboarding) {
      context.go(AppRoutes.dashboard);
      return;
    }

    if (!OnboardingService.hasCompletedPlayerSetup) {
      context.go(AppRoutes.playerSetup);
      return;
    }

    context.go(AppRoutes.goal);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await _navigateAfterAuth();
    } on AuthException catch (e) {
      setState(() => _errorMessage = AuthService.friendlyAuthError(e));
    } catch (e) {
      setState(() => _errorMessage = AuthService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading;

    return AuthScaffold(
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const ShootIQLogo(size: 88),
            const SizedBox(height: 28),
            const Text(
              'Welcome Back',
              style: TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Continue your shooting journey.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            AuthCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@email.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enabled: !busy,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    enabled: !busy,
                    suffix: IconButton(
                      onPressed: busy
                          ? null
                          : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: ShootIQTheme.textSecondary,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy
                          ? null
                          : () => context.push(AppRoutes.forgotPassword),
                      style: TextButton.styleFrom(
                        foregroundColor: ShootIQTheme.basketballOrange,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    AuthErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  AuthPrimaryButton(
                    label: 'Log In',
                    isLoading: _isLoading,
                    onPressed: busy ? null : _submit,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 15,
                  ),
                ),
                TextButton(
                  onPressed:
                      busy ? null : () => context.push(AppRoutes.signup),
                  style: TextButton.styleFrom(
                    foregroundColor: ShootIQTheme.basketballOrange,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
