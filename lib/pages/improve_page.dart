import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/improve/improve_widgets.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class ImprovePage extends StatefulWidget {
  const ImprovePage({super.key});

  @override
  State<ImprovePage> createState() => _ImprovePageState();
}

class _ImprovePageState extends State<ImprovePage>
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

  void _openAnalyzer() => context.push(AppRoutes.analyzer);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
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
                      const ImproveHeader(),
                      const SizedBox(height: 24),
                      const ShotScoreCard(),
                      const SizedBox(height: 16),
                      ImproveFeatureCard(
                        icon: Icons.psychology_outlined,
                        title: 'AI Shot Analyzer',
                        description:
                            'Find your shooting mistakes and get drills designed to fix them.',
                        actionLabel: 'Analyze My Shot →',
                        onAction: _openAnalyzer,
                      ),
                      const SizedBox(height: 16),
                      const ImproveFeatureCard(
                        icon: Icons.play_circle_outline,
                        title: 'Instant Replay',
                        description:
                            'Review your shots in slow motion and make adjustments while practicing.',
                        actionLabel: 'Review My Shots →',
                      ),
                      const SizedBox(height: 28),
                      const ImproveSectionTitle(title: 'Your Training'),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Expanded(
                            child: TrainingMiniCard(
                              emoji: '🔥',
                              label: 'Daily Challenge',
                              title: '50 Shot Challenge',
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: TrainingMiniCard(
                              emoji: '📈',
                              label: 'Progress',
                              title: 'View History',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const ImproveBottomNav(),
          ],
        ),
      ),
    );
  }
}
