import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/widgets/auth/auth_widgets.dart';
import 'package:shootiq/widgets/shootiq_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  bool get _busy => _isLoading;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();

      final response = await AuthService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        firstName: firstName,
        lastName: lastName,
      );

      await OnboardingService.setUserName('$firstName $lastName'.trim());
      await OnboardingService.setHasCompletedPlayerSetup(false);
      await OnboardingService.setHasCompletedOnboarding(false);

      if (!mounted) return;

      // Email confirmation may be required — no session until confirmed.
      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created! Check your email to confirm, then log in.',
            ),
          ),
        );
        context.go(AppRoutes.login);
        return;
      }

      context.go(AppRoutes.playerSetup);
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = AuthService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const ShootIQLogo(size: 80),
            const SizedBox(height: 24),
            const Text(
              'Create Your Account',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Build your game with AI-powered coaching.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            AuthCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AuthTextField(
                          controller: _firstNameController,
                          label: 'First Name',
                          prefixIcon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          enabled: !_busy,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AuthTextField(
                          controller: _lastNameController,
                          label: 'Last Name',
                          textInputAction: TextInputAction.next,
                          enabled: !_busy,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'you@email.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enabled: !_busy,
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
                    textInputAction: TextInputAction.next,
                    enabled: !_busy,
                    suffix: IconButton(
                      onPressed: _busy
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
                        return 'Enter a password';
                      }
                      if (value.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    enabled: !_busy,
                    suffix: IconButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: ShootIQTheme.textSecondary,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    AuthErrorBanner(message: _errorMessage!),
                  ],
                  const SizedBox(height: 24),
                  AuthPrimaryButton(
                    label: 'Create Account',
                    isLoading: _isLoading,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 15,
                  ),
                ),
                TextButton(
                  onPressed:
                      _busy ? null : () => context.go(AppRoutes.login),
                  style: TextButton.styleFrom(
                    foregroundColor: ShootIQTheme.basketballOrange,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Log In',
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
