import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/demo_analysis_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/subscription_service.dart';

/// Main entry point for analyzing a basketball shot.
class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key});

  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _staggerController;
  late final Animation<double> _fadeAnimation;

  static const _tips = [
    'Record your full body',
    'Use side angle view',
    'Keep camera steady',
    'Make sure lighting is good',
  ];

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

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _fadeController.forward();
    _staggerController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Animation<double> _cardFade(int index) {
    final start = 0.12 + (index * 0.1);
    final end = (start + 0.35).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  Animation<Offset> _cardSlide(int index) {
    final start = 0.12 + (index * 0.1);
    final end = (start + 0.35).clamp(0.0, 1.0);
    return Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  Future<void> _onRecord() async {
    await SubscriptionService.openAnalysisOrPaywall(
      context,
      destination: AppRoutes.cameraCapture,
    );
  }

  Future<void> _onUpload() async {
    await SubscriptionService.openAnalysisOrPaywall(
      context,
      destination: AppRoutes.videoUpload,
    );
  }

  /// Demo path — plays a bundled sample shot with its real analysis, so
  /// every user sees an actual result here (not a placeholder).
  Future<void> _onStartDemo() async {
    final results = await DemoAnalysisService.loadResults();
    if (!mounted) return;
    context.push(AppRoutes.results, extra: results);
  }

  void _onViewResults() {
    context.push(AppRoutes.results);
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastScore = OnboardingService.lastScore;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalyzeAppBar(onBack: _onBack),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeTransition(
                        opacity: _cardFade(0),
                        child: SlideTransition(
                          position: _cardSlide(0),
                          child: const _HeaderSection(),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: _cardFade(1),
                        child: SlideTransition(
                          position: _cardSlide(1),
                          child: _ActionCard(
                            icon: Icons.videocam_rounded,
                            title: 'Record New Shot',
                            description:
                                'Use your camera to capture your shooting form.',
                            buttonLabel: 'Record',
                            onPressed: _onRecord,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _cardFade(2),
                        child: SlideTransition(
                          position: _cardSlide(2),
                          child: _ActionCard(
                            icon: Icons.upload_file_rounded,
                            title: 'Upload Video',
                            description:
                                'Analyze an existing shooting video.',
                            buttonLabel: 'Choose Video',
                            onPressed: _onUpload,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _cardFade(3),
                        child: SlideTransition(
                          position: _cardSlide(3),
                          child: _ActionCard(
                            icon: Icons.sports_basketball_rounded,
                            title: 'Try Demo Analysis',
                            description:
                                'See how ShootIQ works with sample footage.',
                            buttonLabel: 'Start Demo',
                            onPressed: _onStartDemo,
                            accent: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: _cardFade(4),
                        child: SlideTransition(
                          position: _cardSlide(4),
                          child: _RecentAnalysisCard(
                            score: lastScore,
                            dateLabel: 'Today',
                            onViewResults: _onViewResults,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _cardFade(5),
                        child: SlideTransition(
                          position: _cardSlide(5),
                          child: const _TipsCard(tips: _tips),
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

class _AnalyzeAppBar extends StatelessWidget {
  const _AnalyzeAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: ShootIQTheme.textPrimary,
              size: 20,
            ),
          ),
          const Expanded(
            child: Text(
              'Analyze Shot',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 168,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ShootIQTheme.surfaceElevated,
                ShootIQTheme.cardBackground,
                ShootIQTheme.basketballOrange.withValues(alpha: 0.22),
              ],
            ),
            border: Border.all(color: ShootIQTheme.cardBorder),
            boxShadow: [
              BoxShadow(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: -20,
                bottom: -24,
                child: Icon(
                  Icons.sports_basketball_rounded,
                  size: 140,
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.12),
                ),
              ),
              Container(
                width: 88,
                height: 88,
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
                      color:
                          ShootIQTheme.basketballOrange.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Analyze Your Shot',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Record or upload a video and let AI analyze your shooting mechanics.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.35)
              : ShootIQTheme.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: accent
                        ? const [
                            ShootIQTheme.basketballOrange,
                            ShootIQTheme.basketballOrangeLight,
                          ]
                        : [
                            ShootIQTheme.surfaceElevated,
                            ShootIQTheme.surfaceElevated
                                .withValues(alpha: 0.7),
                          ],
                  ),
                  border: accent
                      ? null
                      : Border.all(
                          color: ShootIQTheme.cardBorder,
                        ),
                ),
                child: Icon(
                  icon,
                  color: accent
                      ? Colors.white
                      : ShootIQTheme.basketballOrange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ScaleTapButton(
            label: buttonLabel,
            onPressed: onPressed,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _RecentAnalysisCard extends StatelessWidget {
  const _RecentAnalysisCard({
    required this.score,
    required this.dateLabel,
    required this.onViewResults,
  });

  final int score;
  final String dateLabel;
  final VoidCallback onViewResults;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShootIQTheme.surfaceElevated,
            ShootIQTheme.cardBackground,
          ],
        ),
        border: Border.all(color: ShootIQTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: ShootIQTheme.basketballOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Last Shot',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                dateLabel,
                style: const TextStyle(
                  color: ShootIQTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  color: ShootIQTheme.basketballOrange,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Score',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ScaleTapButton(
            label: 'View Results',
            onPressed: onViewResults,
            filled: false,
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Better Analysis Tips',
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: ShootIQTheme.courtGreenLight
                          .withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Color(0xFF95D5B2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft scale-down on press for premium button feel.
class _ScaleTapButton extends StatefulWidget {
  const _ScaleTapButton({
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  State<_ScaleTapButton> createState() => _ScaleTapButtonState();
}

class _ScaleTapButtonState extends State<_ScaleTapButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 140),
      lowerBound: 0.96,
      upperBound: 1,
      value: 1,
    );
    _scale = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: double.infinity,
      height: 48,
      child: widget.filled
          ? FilledButton(
              onPressed: widget.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: ShootIQTheme.buttonBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(widget.label),
            )
          : OutlinedButton(
              onPressed: widget.onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: ShootIQTheme.textPrimary,
                side: BorderSide(
                  color: ShootIQTheme.surfaceElevated,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(widget.label),
            ),
    );

    return Listener(
      onPointerDown: (_) => _controller.reverse(),
      onPointerUp: (_) => _controller.forward(),
      onPointerCancel: (_) => _controller.forward(),
      child: ScaleTransition(scale: _scale, child: child),
    );
  }
}
