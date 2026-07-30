import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/analysis_loading_config.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_analysis.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/api_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/review_prompt_service.dart';
import 'package:shootiq/services/shot_history_service.dart';
import 'package:shootiq/services/video_prep_service.dart';
import 'package:shootiq/widgets/error_state.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({
    super.key,
    this.videoFile,
    this.analysis,
  });

  /// Local video to send to the FastAPI AI backend.
  final File? videoFile;

  /// Optional pre-built analysis (demo / offline fallback).
  final ShotAnalysis? analysis;

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage>
    with TickerProviderStateMixin {
  /// Staged loading copy — sourced from [AnalysisLoadingConfig] so the
  /// simulated 15s timer can later be swapped for real MediaPipe timing.
  static final _steps = AnalysisLoadingConfig.stepLabels;

  late final AnimationController _fadeController;
  late final AnimationController _progressController;
  late final AnimationController _scanRotationController;
  late final AnimationController _scanLineController;
  late final AnimationController _pulseController;
  late final AnimationController _completeController;
  late final AnimationController _buttonScaleController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _progressAnimation;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _completeFade;
  late final Animation<Offset> _completeSlide;
  late final Animation<double> _buttonScale;

  late final Animation<double> _elbowAnimation;
  late final Animation<double> _releaseAnimation;

  int _completedSteps = 0;
  bool _isComplete = false;
  bool _hasFailed = false;
  String _status = AnalysisLoadingConfig.stages.first.message;
  String? _errorMessage;
  ShotAnalysis? _resultAnalysis;
  Map<String, dynamic>? _rawResults;
  bool _autoNavigated = false;

  bool get _useLiveAi => widget.videoFile != null;

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

    // Optimistic progress up to 90% while AI runs; snaps to 100% on completion.
    _progressController = AnimationController(
      vsync: this,
      duration: AnalysisLoadingConfig.maxOptimisticDuration,
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    );

    _scanRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.55, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _completeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _completeFade = CurvedAnimation(
      parent: _completeController,
      curve: Curves.easeOut,
    );
    _completeSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _completeController, curve: Curves.easeOutCubic),
    );

    _buttonScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 140),
      lowerBound: 0.97,
      upperBound: 1,
      value: 1,
    );
    _buttonScale = _buttonScaleController;

    _elbowAnimation = Tween<double>(begin: 0, end: 72).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: const Interval(0.25, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _releaseAnimation = Tween<double>(begin: 0, end: 0.45).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _progressController.addListener(_onProgressTick);

    _fadeController.forward();
    // Cap optimistic fill at 90% until real AI finishes.
    _progressController.animateTo(0.9);

    if (_useLiveAi) {
      // ignore: unawaited_futures
      _startBackgroundAnalysis();
    } else {
      // Offline / demo path — finish shortly.
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted || _autoNavigated) return;
        _rawResults = widget.analysis != null
            ? null
            : AnalysisLoadingConfig.placeholderResults();
        _resultAnalysis =
            widget.analysis ?? ShotAnalysis.fromAiResponse(_rawResults!);
        _completeAndNavigate();
      });
    }
  }

  /// Real FastAPI call — Results navigate as soon as JSON returns.
  /// History save runs in the background so it does not block the report.
  Future<void> _startBackgroundAnalysis() async {
    final video = widget.videoFile;
    if (video == null) return;

    try {
      final prepared = await VideoPrepService.prepareForUpload(video);
      final videoSize = await prepared.length();
      // ignore: avoid_print
      print('Video path: ${prepared.path}');
      // ignore: avoid_print
      print('Video size: $videoSize bytes');

      final results = await ApiService.analyzeShot(prepared);
      if (!mounted) return;

      PendingAnalysisStore.clear();
      _rawResults = results;
      _resultAnalysis = ShotAnalysis.fromAiResponse(
        results,
        videoUrl: prepared.path,
      );

      // Show Results immediately — do not wait on history or video render.
      await _completeAndNavigate();

      // Persist history on-device only (fire-and-forget).
      // Scores/feedback + local video paths — never Supabase Storage.
      Future<void>(() async {
        try {
          await ShotHistoryService.saveAnalyzedShot(
            localVideo: prepared,
            aiResults: results,
          );
          try {
            await ReviewPromptService.recordAnalysisCompleted();
          } catch (_) {}
        } catch (e) {
          // ignore: avoid_print
          print('Shot history save skipped: $e');
        }
      });
    } catch (error) {
      // ignore: avoid_print
      print('Background AI analysis error: $error');
      if (!mounted) return;
      setState(() {
        _hasFailed = true;
        _errorMessage = error.toString();
        _status = 'Analysis failed';
      });
      _scanRotationController.stop();
      _scanLineController.stop();
      _pulseController.stop();
    }
  }

  Future<void> _completeAndNavigate() async {
    if (_isComplete || _hasFailed || _autoNavigated) return;
    if (_useLiveAi && _rawResults == null) return;

    await _progressController.animateTo(
      1,
      duration: const Duration(milliseconds: 280),
    );
    if (!mounted || _autoNavigated) return;

    _finishAnalysis();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || _autoNavigated) return;
    await _viewResults();
  }

  void _onProgressTick() {
    // While AI runs, keep the ring under 90% even if animation overshoots.
    final raw = _progressAnimation.value;
    final progress = _rawResults == null ? raw.clamp(0.0, 0.9) : raw;
    final nextCompleted = (progress * _steps.length).floor().clamp(
      0,
      _steps.length,
    );
    final stagedStatus = AnalysisLoadingConfig.statusForProgress(progress);

    if (nextCompleted != _completedSteps ||
        (!_isComplete && !_hasFailed && stagedStatus != _status)) {
      setState(() {
        _completedSteps = nextCompleted;
        if (!_isComplete && !_hasFailed) {
          _status = stagedStatus;
        }
      });
    } else {
      setState(() {});
    }
  }

  void _finishAnalysis() {
    if (_isComplete) return;
    setState(() {
      _isComplete = true;
      _completedSteps = _steps.length;
      _status = 'Analysis complete!';
    });
    _scanRotationController.stop();
    _scanLineController.stop();
    _pulseController.stop();
    _completeController.forward();
  }

  @override
  void dispose() {
    _progressController.removeListener(_onProgressTick);
    _fadeController.dispose();
    _progressController.dispose();
    _scanRotationController.dispose();
    _scanLineController.dispose();
    _pulseController.dispose();
    _completeController.dispose();
    _buttonScaleController.dispose();
    super.dispose();
  }

  Future<void> _viewResults() async {
    final analysis =
        _resultAnalysis ?? widget.analysis ?? ShotAnalysis.placeholder();
    await OnboardingService.setLastScore(analysis.overallScore);
    if (!mounted) return;
    _autoNavigated = true;

    // Embed local path so Results can play immediately (no wait on network/overlay).
    final payload = _rawResults != null
        ? Map<String, dynamic>.from(_rawResults!)
        : <String, dynamic>{
            'overall_score': analysis.overallScore,
            'analysis_video_url': analysis.analysisVideoUrl,
          };
    final localPath = widget.videoFile?.path ?? analysis.videoUrl;
    if (localPath != null && localPath.isNotEmpty) {
      payload['local_video_path'] = localPath;
      payload['video_url'] = localPath;
    }
    // Never send slow-mo as the primary URL unless the server marked it ready.
    // Keep skeleton_video_url so Results can swap to the overlay when it finishes.
    if (payload['overlay_ready'] != true) {
      payload.remove('slow_motion_video_url');
    }

    context.go(AppRoutes.results, extra: payload);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progressAnimation.value;
    final percent = (progress * 100).round().clamp(0, 100);

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF12121C),
              ShootIQTheme.darkBackground,
              Color(0xFF0B0B12),
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                children: [
                  const Text(
                    'Analyzing Your Shot',
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
                  Text(
                    _hasFailed
                        ? (_errorMessage ?? 'Analysis failed')
                        : _isComplete
                            ? 'Your AI coaching report is ready'
                            : _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _hasFailed
                          ? ShootIQTheme.errorRed
                          : ShootIQTheme.textSecondary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _AiScanningVisual(
                    rotation: _scanRotationController,
                    scanLine: _scanLineController,
                    pulse: _pulseAnimation,
                    isComplete: _isComplete,
                  ),
                  const SizedBox(height: 28),
                  _CircularProgressBadge(
                    progress: progress,
                    percent: percent,
                    isComplete: _isComplete,
                  ),
                  const SizedBox(height: 24),
                  _AnalysisTimeline(
                    steps: _steps,
                    completedSteps: _completedSteps,
                    isComplete: _isComplete,
                    activeIndex: _isComplete
                        ? -1
                        : _completedSteps.clamp(0, _steps.length - 1),
                  ),
                  const SizedBox(height: 16),
                  _LiveMetricsCard(
                    elbowDegrees: _elbowAnimation.value,
                    releaseSeconds: _releaseAnimation.value,
                    showArcValue: progress >= 0.72 || _isComplete,
                    isComplete: _isComplete,
                  ),
                  if (_hasFailed) ...[
                    const SizedBox(height: 24),
                    ErrorState(
                      type: AppErrorInfo.classify(
                        _errorMessage ?? 'Analysis failed',
                      ),
                      detail: _errorMessage,
                      onRetry: () {
                        setState(() {
                          _hasFailed = false;
                          _isComplete = false;
                          _errorMessage = null;
                          _rawResults = null;
                          _resultAnalysis = null;
                          _status =
                              AnalysisLoadingConfig.stages.first.message;
                          _completedSteps = 0;
                        });
                        _progressController
                          ..reset()
                          ..animateTo(0.9);
                        _scanRotationController.repeat();
                        _scanLineController.repeat(reverse: true);
                        _pulseController.repeat(reverse: true);
                        if (_useLiveAi) {
                          // ignore: unawaited_futures
                          _startBackgroundAnalysis();
                        }
                      },
                      onReturn: () => context.go(AppRoutes.dashboard),
                      returnLabel: 'Return Home',
                    ),
                  ],
                  if (_isComplete) ...[
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _completeFade,
                      child: SlideTransition(
                        position: _completeSlide,
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF22C55E),
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Analysis Complete ✓',
                                    style: TextStyle(
                                      color: Color(0xFF95D5B2),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ScaleTransition(
                              scale: _buttonScale,
                              child: Listener(
                                onPointerDown: (_) =>
                                    _buttonScaleController.reverse(),
                                onPointerUp: (_) =>
                                    _buttonScaleController.forward(),
                                onPointerCancel: (_) =>
                                    _buttonScaleController.forward(),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: FilledButton(
                                    onPressed: _viewResults,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: ShootIQTheme.buttonBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: const Text('View Results'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiScanningVisual extends StatelessWidget {
  const _AiScanningVisual({
    required this.rotation,
    required this.scanLine,
    required this.pulse,
    required this.isComplete,
  });

  final Animation<double> rotation;
  final Animation<double> scanLine;
  final Animation<double> pulse;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: AnimatedBuilder(
        animation: Listenable.merge([rotation, scanLine, pulse]),
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing glow
              Container(
                width: 170 + (pulse.value * 18),
                height: 170 + (pulse.value * 18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isComplete
                              ? const Color(0xFF22C55E)
                              : ShootIQTheme.basketballOrange)
                          .withValues(alpha: 0.18 * pulse.value),
                      blurRadius: 42,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
              // Rotating scan ring
              Transform.rotate(
                angle: rotation.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(188, 188),
                  painter: _ScanRingPainter(
                    color: isComplete
                        ? const Color(0xFF22C55E)
                        : ShootIQTheme.basketballOrange,
                  ),
                ),
              ),
              // Inner dashed ring
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ShootIQTheme.cardBorder,
                    width: 1.5,
                  ),
                ),
              ),
              // Basketball core
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isComplete
                        ? const [
                            Color(0xFF22C55E),
                            Color(0xFF16A34A),
                          ]
                        : const [
                            ShootIQTheme.basketballOrange,
                            ShootIQTheme.basketballOrangeLight,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isComplete
                              ? const Color(0xFF22C55E)
                              : ShootIQTheme.basketballOrange)
                          .withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  isComplete
                      ? Icons.check_rounded
                      : Icons.sports_basketball_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              // Moving scan line
              if (!isComplete)
                ClipOval(
                  child: SizedBox(
                    width: 148,
                    height: 148,
                    child: CustomPaint(
                      painter: _ScanLinePainter(
                        progress: scanLine.value,
                        color: ShootIQTheme.basketballOrangeLight
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanRingPainter extends CustomPainter {
  const _ScanRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.15),
          color,
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.35, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.45,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanRingPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          color.withValues(alpha: 0),
          color,
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2));

    canvas.drawRect(Rect.fromLTWH(0, y - 1.2, size.width, 2.4), paint);

    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
    canvas.drawRect(Rect.fromLTWH(0, y - 18, size.width, 36), glow);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _CircularProgressBadge extends StatelessWidget {
  const _CircularProgressBadge({
    required this.progress,
    required this.percent,
    required this.isComplete,
  });

  final double progress;
  final int percent;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final accent = isComplete
        ? const Color(0xFF22C55E)
        : ShootIQTheme.basketballOrange;

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 6,
              backgroundColor: ShootIQTheme.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              strokeCap: StrokeCap.round,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              '$percent%',
              key: ValueKey(percent),
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTimeline extends StatelessWidget {
  const _AnalysisTimeline({
    required this.steps,
    required this.completedSteps,
    required this.isComplete,
    required this.activeIndex,
  });

  final List<String> steps;
  final int completedSteps;
  final bool isComplete;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: List.generate(steps.length, (index) {
          final done = index < completedSteps || isComplete;
          final active = !done && index == activeIndex;
          return _TimelineStep(
            label: steps[index],
            done: done,
            active: active,
            isLast: index == steps.length - 1,
          );
        }),
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.done,
    required this.active,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF22C55E)
        : active
            ? ShootIQTheme.basketballOrange
            : ShootIQTheme.textSecondary.withValues(alpha: 0.55);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: done || active ? 1 : 0.75),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.45 + (0.55 * value),
          child: child,
        );
      },
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                          : active
                              ? ShootIQTheme.basketballOrange
                                  .withValues(alpha: 0.18)
                              : ShootIQTheme.surfaceElevated,
                      border: Border.all(color: color, width: 1.5),
                    ),
                    child: done
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Color(0xFF22C55E),
                          )
                        : active
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ShootIQTheme.basketballOrange,
                                ),
                              )
                            : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: done
                            ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                            : ShootIQTheme.cardBorder,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 8 : 16, top: 2),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: done
                        ? ShootIQTheme.textPrimary
                        : active
                            ? ShootIQTheme.basketballOrangeLight
                            : ShootIQTheme.textSecondary,
                    fontSize: 14,
                    fontWeight:
                        active || done ? FontWeight.w600 : FontWeight.w500,
                    height: 1.3,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMetricsCard extends StatelessWidget {
  const _LiveMetricsCard({
    required this.elbowDegrees,
    required this.releaseSeconds,
    required this.showArcValue,
    required this.isComplete,
  });

  final double elbowDegrees;
  final double releaseSeconds;
  final bool showArcValue;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShootIQTheme.surfaceElevated,
            ShootIQTheme.cardBackground,
            ShootIQTheme.basketballOrange.withValues(alpha: 0.1),
          ],
        ),
        border: Border.all(color: ShootIQTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: ShootIQTheme.basketballOrange,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Live Analysis',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            label: 'Elbow Angle',
            value: '${elbowDegrees.round()}°',
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: 'Release Timing',
            value: '${releaseSeconds.toStringAsFixed(2)} seconds',
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: 'Shot Arc',
            value: showArcValue || isComplete ? '47°' : 'Analyzing...',
            analyzing: !(showArcValue || isComplete),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.analyzing = false,
  });

  final String label;
  final String value;
  final bool analyzing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                color: analyzing
                    ? ShootIQTheme.basketballOrangeLight
                    : ShootIQTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
