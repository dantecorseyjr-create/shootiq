import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/widgets/auth/auth_widgets.dart';
import 'package:shootiq/widgets/shootiq_logo.dart';

const _skillLevels = [
  'Beginner',
  'Intermediate',
  'Advanced',
  'Competitive',
];

const _positions = [
  'Point Guard',
  'Shooting Guard',
  'Small Forward',
  'Power Forward',
  'Center',
];

const _dominantHands = ['Right', 'Left', 'Ambidextrous'];

class PlayerSetupPage extends StatefulWidget {
  const PlayerSetupPage({super.key});

  @override
  State<PlayerSetupPage> createState() => _PlayerSetupPageState();
}

class _PlayerSetupPageState extends State<PlayerSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _ageController = TextEditingController();

  String? _position;
  String? _dominantHand;
  String? _skillLevel;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (_position == null || _dominantHand == null || _skillLevel == null) {
      setState(() {
        _errorMessage = 'Select position, dominant hand, and skill level.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await OnboardingService.savePlayerSetup(
        height: _heightController.text,
        weight: _weightController.text,
        age: _ageController.text,
        position: _position!,
        dominantHand: _dominantHand!,
        skillLevel: _skillLevel!,
      );

      if (!mounted) return;
      // Continue first-time onboarding for new users only.
      context.go(AppRoutes.goal);
    } catch (_) {
      setState(() => _errorMessage = 'Could not save your profile. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ShootIQLogo(size: 72),
            const SizedBox(height: 22),
            const Text(
              'Player Setup',
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
              'Tell us about your game so we can personalize coaching.',
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
                  AuthTextField(
                    controller: _heightController,
                    label: 'Height',
                    hint: "e.g. 6'2\" or 188 cm",
                    prefixIcon: Icons.height_rounded,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your height';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _weightController,
                    label: 'Weight',
                    hint: 'e.g. 180 lbs',
                    prefixIcon: Icons.monitor_weight_outlined,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your weight';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _ageController,
                    label: 'Age',
                    hint: 'e.g. 17',
                    prefixIcon: Icons.cake_outlined,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    enabled: !_isLoading,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your age';
                      }
                      final age = int.tryParse(value.trim());
                      if (age == null || age < 5 || age > 100) {
                        return 'Enter a valid age';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Playing Position',
                    style: TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AuthOptionChips(
                    options: _positions,
                    selected: _position,
                    onSelected: (value) => setState(() => _position = value),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Dominant Hand',
                    style: TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AuthOptionChips(
                    options: _dominantHands,
                    selected: _dominantHand,
                    onSelected: (value) =>
                        setState(() => _dominantHand = value),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Skill Level',
                    style: TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AuthOptionChips(
                    options: _skillLevels,
                    selected: _skillLevel,
                    onSelected: (value) => setState(() => _skillLevel = value),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    AuthErrorBanner(message: _errorMessage!),
                  ],
                  const SizedBox(height: 28),
                  AuthPrimaryButton(
                    label: 'Continue',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _continue,
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
