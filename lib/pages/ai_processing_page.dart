import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class AiProcessingPage extends StatefulWidget {
  const AiProcessingPage({super.key});

  @override
  State<AiProcessingPage> createState() => _AiProcessingPageState();
}

class _AiProcessingPageState extends State<AiProcessingPage>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _pulseAnimation;

  int _completedSteps = 0;
  Timer? _stepTimer;
  Timer? _navTimer;

  static const _steps = [
    'Uploading Video',
    'Detecting Body Movement',
    'Measuring Shooting Form',
    'Creating Feedback',
  ];

  static const _metrics = [
    (emoji: '🏀', title: 'Body Tracking', statuses: ['Active', 'Active', 'Locked', 'Complete']),
    (emoji: '🎯', title: 'Release Detection', statuses: ['Scanning', 'Scanning', 'Active', 'Complete']),
    (emoji: '📐', title: 'Form Analysis', statuses: ['Waiting', 'Processing', 'Processing', 'Complete']),
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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();

    _fadeController.forward();
    _startStepSequence();

    _navTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      context.go(AppRoutes.results);
    });
  }

  void _startStepSequence() {
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_completedSteps >= _steps.length) {
        timer.cancel();
        return;
      }
      setState(() => _completedSteps += 1);
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _navTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  int get _metricStatusIndex {
    if (_completedSteps <= 0) return 0;
    if (_completedSteps >= _steps.length) return 3;
    return (_completedSteps - 1).clamp(0, 3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              PremiumSpacing.horizontal,
              24,
              PremiumSpacing.horizontal,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ProcessingHero(),
                const SizedBox(height: PremiumSpacing.heroToTitle),
                Text(
                  'Analyzing Your Shot...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        height: 1.15,
                        letterSpacing: -0.8,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ShotIQ AI is reviewing your mechanics frame by frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: PremiumColors.subtitle,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: PremiumSpacing.section),
                _ProgressCard(
                  progress: _progressController,
                  completedSteps: _completedSteps,
                  steps: _steps,
                ),
                const SizedBox(height: PremiumSpacing.section),
                _LiveMetrics(
                  metrics: _metrics,
                  statusIndex: _metricStatusIndex,
                  pulse: _pulseAnimation,
                ),
                const SizedBox(height: 28),
                const OnboardingFootnote(
                  text: 'This usually takes a few seconds.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessingHero extends StatefulWidget {
  const _ProcessingHero();

  @override
  State<_ProcessingHero> createState() => _ProcessingHeroState();
}

class _ProcessingHeroState extends State<_ProcessingHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        'assets/images/ai_processing.png',
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              color: PremiumColors.cardBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.05).animate(
                CurvedAnimation(
                  parent: _iconController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 72,
                color: PremiumColors.accentOrange,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.completedSteps,
    required this.steps,
  });

  final AnimationController progress;
  final int completedSteps;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.value,
                  minHeight: 8,
                  backgroundColor: PremiumColors.cardBorder,
                  color: PremiumColors.accentOrange,
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _StepRow(
              label: steps[i],
              isComplete: i < completedSteps,
              isActive: i == completedSteps,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.isComplete,
    required this.isActive,
  });

  final String label;
  final bool isComplete;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isComplete || isActive
        ? PremiumColors.title
        : PremiumColors.disclaimer;

    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            isComplete
                ? Icons.check_circle_rounded
                : isActive
                    ? Icons.radio_button_checked
                    : Icons.circle_outlined,
            key: ValueKey('$label-$isComplete-$isActive'),
            size: 20,
            color: isComplete
                ? PremiumColors.checkGreen
                : isActive
                    ? PremiumColors.accentOrange
                    : PremiumColors.disclaimer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isActive || isComplete ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveMetrics extends StatelessWidget {
  const _LiveMetrics({
    required this.metrics,
    required this.statusIndex,
    required this.pulse,
  });

  final List<({String emoji, String title, List<String> statuses})> metrics;
  final int statusIndex;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Detection',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: PremiumColors.title,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          ScaleTransition(
            scale: i == 0 ? pulse : const AlwaysStoppedAnimation(1),
            child: _MetricCard(
              emoji: metrics[i].emoji,
              title: metrics[i].title,
              status: metrics[i].statuses[statusIndex],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.emoji,
    required this.title,
    required this.status,
  });

  final String emoji;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PremiumColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PremiumColors.cardBorder),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PremiumColors.title,
              ),
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: status == 'Complete'
                  ? PremiumColors.checkGreen
                  : PremiumColors.accentOrange,
            ),
          ),
        ],
      ),
    );
  }
}
