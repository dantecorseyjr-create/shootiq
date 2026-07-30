import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

const _analysisMetrics = [
  (emoji: '🏀', label: 'Form', percent: 91),
  (emoji: '🎯', label: 'Release', percent: 88),
  (emoji: '⚖️', label: 'Balance', percent: 86),
  (emoji: '📈', label: 'Consistency', percent: 93),
];

const _aiCoachMessage =
    'Your release is consistent, but your elbow drops slightly on faster shots. '
    'Focus on keeping your elbow under the ball throughout the shooting motion.';

class ConfidencePage extends StatefulWidget {
  const ConfidencePage({super.key});

  @override
  State<ConfidencePage> createState() => _ConfidencePageState();
}

class _ConfidencePageState extends State<ConfidencePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
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

  Future<void> _onLetsGo() async {
    await OnboardingService.completeOnboarding();
    if (!mounted) return;
    context.push(AppRoutes.improve);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  PremiumSpacing.horizontal,
                  8,
                  PremiumSpacing.horizontal,
                  0,
                ),
                child: CustomBackButton(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    PremiumSpacing.horizontal,
                    16,
                    PremiumSpacing.horizontal,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const OnboardingIllustration(
                        assetPath: 'assets/images/confidence.png',
                        fallbackIcon: Icons.analytics_outlined,
                        placeholderColor: PremiumColors.cardBackground,
                      ),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const OnboardingTitleSection(
                        title: 'Less Guessing.\nMore Confident Shots.',
                        subtitle:
                            'Understand your shooting mechanics and know exactly what to improve before your next shot.',
                      ),
                      const SizedBox(height: PremiumSpacing.section),
                      const _LatestAnalysisCard(),
                      const SizedBox(height: PremiumSpacing.cardGap),
                      const AiCoachTipCard(message: _aiCoachMessage),
                      const SizedBox(height: 28),
                      OnboardingPrimaryButton(
                        label: "Let's Go",
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed: _onLetsGo,
                      ),
                      const SizedBox(height: 24),
                      const OnboardingFootnote(
                        text:
                            'Your first analysis is only a few seconds away.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestAnalysisCard extends StatelessWidget {
  const _LatestAnalysisCard();

  @override
  Widget build(BuildContext context) {
    return OnboardingSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Latest AI Analysis',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: PremiumColors.title,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _analysisMetrics.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            AnalysisMetricRow(
              emoji: _analysisMetrics[i].emoji,
              label: _analysisMetrics[i].label,
              percent: _analysisMetrics[i].percent,
            ),
          ],
        ],
      ),
    );
  }
}
