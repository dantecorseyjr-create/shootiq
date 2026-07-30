import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/onboarding_service.dart';

/// Welcome Back screen for returning players after onboarding is complete.
class WelcomeBackPage extends StatefulWidget {
  const WelcomeBackPage({super.key});

  @override
  State<WelcomeBackPage> createState() => _WelcomeBackPageState();
}

class _WelcomeBackPageState extends State<WelcomeBackPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = OnboardingService.userName;
    final lastScore = OnboardingService.lastScore;
    final streak = OnboardingService.currentStreakDays;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        ShootIQTheme.basketballOrange,
                        ShootIQTheme.basketballOrangeLight,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ShootIQTheme.basketballOrange
                            .withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.sports_basketball_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Welcome back,\n$name',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                    height: 1.15,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ready to keep improving your shot?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: ShootIQTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'Last Score',
                        value: '$lastScore',
                        icon: Icons.analytics_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatChip(
                        label: 'Current Streak',
                        value: '$streak Days',
                        icon: Icons.local_fire_department_outlined,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: () => context.go(AppRoutes.analyze),
                    style: FilledButton.styleFrom(
                      backgroundColor: ShootIQTheme.buttonBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Analyze New Shot'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(AppRoutes.dashboard),
                  style: TextButton.styleFrom(
                    foregroundColor: ShootIQTheme.textSecondary,
                  ),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ShootIQTheme.basketballOrange, size: 22),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: ShootIQTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: ShootIQTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
