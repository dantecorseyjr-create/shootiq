import 'package:flutter/material.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/analyzer/analyzer_widgets.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

const _analyzerSteps = [
  (
    emoji: '🎥',
    title: 'Record',
    description: 'Capture your shooting motion from the correct angle.',
  ),
  (
    emoji: '🤖',
    title: 'Analyze',
    description: 'AI detects your mechanics, release, and balance.',
  ),
  (
    emoji: '📈',
    title: 'Improve',
    description: 'Receive feedback and drills designed for you.',
  ),
];

class AiAnalyzerPage extends StatefulWidget {
  const AiAnalyzerPage({super.key});

  @override
  State<AiAnalyzerPage> createState() => _AiAnalyzerPageState();
}

class _AiAnalyzerPageState extends State<AiAnalyzerPage>
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

  Future<void> _onAnalyze() async {
    await SubscriptionService.openAnalysisOrPaywall(
      context,
      destination: AppRoutes.camera,
    );
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
                        assetPath: 'assets/images/analyzer.png',
                        fallbackIcon: Icons.track_changes_outlined,
                        placeholderColor: PremiumColors.cardBackground,
                      ),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const AnalyzerIntroTitle(
                        title: 'Getting Started With\nAI Shot Analyzer',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Text(
                            'Too busy for a trainer?\nRecord or upload your shot and start improving your form anywhere.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w400,
                                  color: PremiumColors.subtitle,
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      OnboardingPrimaryButton(
                        label: 'Analyze My Shot',
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed: _onAnalyze,
                      ),
                      const SizedBox(height: 36),
                      const AnalyzerSectionTitle(
                        title: 'How Does AI Shot Analyzer Work?',
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _analyzerSteps.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        AnalyzerStepCard(
                          emoji: _analyzerSteps[i].emoji,
                          title: _analyzerSteps[i].title,
                          description: _analyzerSteps[i].description,
                        ),
                      ],
                      const SizedBox(height: 28),
                      const Center(
                        child: Text(
                          'Your personal AI shooting coach.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: PremiumColors.disclaimer,
                          ),
                        ),
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
