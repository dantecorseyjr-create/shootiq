import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/biomechanics_result.dart';
import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/frame_metric.dart';
import 'package:shootiq/models/movement_issue.dart';
import 'package:shootiq/models/shot_analysis.dart';
import 'package:shootiq/models/shot_coach_context.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/api_service.dart';
import 'package:shootiq/services/coaching_report_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/shot_history_service.dart';
import 'package:shootiq/widgets/biomechanics_timeline.dart';
import 'package:shootiq/widgets/mistake_clip_player.dart';
import 'package:shootiq/widgets/shot_video_player.dart';
import 'package:shootiq/widgets/skeleton_overlay_painter.dart';

/// 18Birdies-style AI shot analysis coaching report.
class ResultsPage extends StatefulWidget {
  const ResultsPage({
    super.key,
    this.analysis,
    this.results,
  });

  final ShotAnalysis? analysis;

  /// Raw FastAPI `/analyze` JSON (or history `toResultsMap()`).
  final Map<String, dynamic>? results;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage>
    with TickerProviderStateMixin {
  static const _overlayPollInterval = Duration(seconds: 2);
  static const _maxOverlayPollAttempts = 90; // ~3 minutes

  final GlobalKey<ShotVideoPlayerState> _playerKey =
      GlobalKey<ShotVideoPlayerState>();

  late final ShotAnalysis _analysis;
  late final int _targetScore;
  late final List<BreakdownItem> _breakdown;
  late final List<MovementIssue> _movements;
  late final List<Mistake> _mistakes;
  late final List<OverlayFrame> _overlayFrames;
  late final List<TimelineItem> _timeline;
  late final FrameMetricSeries _frameMetrics;
  late CoachingReport _coachingReport;
  Map<String, dynamic>? _enrichedResults;
  BiomechanicsResult? _selectedCategory;
  MovementIssue? _selectedMovement;
  String? _selectedPhaseKey;
  double _positionSeconds = 0;
  double _durationSeconds = 0;
  FrameMetric? _activeFrame;

  String? _analysisVideoUrl;
  List<String> _fallbackVideoUrls = const [];
  File? _localVideoFile;
  String? _skeletonVideoUrl;
  bool _preferLocalFile = true;
  bool _overlayReady = false;
  bool _overlayLoading = false;
  int _overlayPollAttempts = 0;
  Timer? _overlayPollTimer;

  late final AnimationController _fadeController;
  late final AnimationController _scoreController;
  late final AnimationController _staggerController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scoreAnimation;
  late final Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();

    final raw = widget.results;
    if (raw != null) {
      // ignore: avoid_print
      print(
        'ResultsPage AI payload score=${raw['overall_score']} '
        'biomechanics=${(raw['biomechanics'] as List?)?.length ?? (raw['breakdown'] as List?)?.length} '
        'video=${raw['analysis_video_url'] ?? raw['analysis_video']}',
      );
      _analysis = ShotAnalysis.fromAiResponse(
        raw,
        videoUrl: raw['local_video_path'] as String? ??
            raw['video_url'] as String?,
      );
      final overlayReady = raw['overlay_ready'] == true;
      // Ready-now URL only (standardized vertical). Skeleton swaps in when ready.
      final ready = ApiService.resolveMediaUrl(
        raw['analysis_video_url'] as String? ??
            raw['original_video_url'] as String? ??
            raw['analysis_video'] as String?,
      );
      final skeleton = ApiService.resolveMediaUrl(
        raw['skeleton_video_url'] as String?,
      );
      final slow = overlayReady
          ? ApiService.resolveMediaUrl(raw['slow_motion_video_url'] as String?)
          : null;
      _skeletonVideoUrl = skeleton;
      _overlayReady = overlayReady && skeleton != null;

      if (_overlayReady) {
        _analysisVideoUrl = skeleton;
        // Prefer skeleton URL first (HTTP or on-device path via _localFileFromPath).
        _preferLocalFile = false;
        _fallbackVideoUrls = <String>[
          if (ready != null) ready,
          if (slow != null) slow,
        ].where((url) => url != _analysisVideoUrl).toSet().toList();
      } else {
        _analysisVideoUrl = ready ?? slow;
        _fallbackVideoUrls = <String>[
          if (ready != null) ready,
          if (slow != null) slow,
        ].where((url) => url != _analysisVideoUrl).toSet().toList();
      }

      final localPath = raw['local_video_path'] as String? ??
          raw['video_url'] as String? ??
          _analysis.videoUrl;
      _localVideoFile = (localPath != null &&
              localPath.isNotEmpty &&
              !localPath.startsWith('http') &&
              File(localPath).existsSync())
          ? File(localPath)
          : null;
      // ignore: avoid_print
      print(
        'ResultsPage playback local=${_localVideoFile?.path} '
        'network=$_analysisVideoUrl skeleton=$skeleton overlayReady=$overlayReady',
      );
      _breakdown = _parseBreakdown(raw);
      _timeline = _parseTimeline(raw, _breakdown);
      _frameMetrics = _parseFrameMetrics(raw);
      _mistakes = _parseMistakes(raw);
      _overlayFrames = _parseOverlayFrames(raw);
      final metrics = raw['metrics'];
      _movements = MovementIssue.fromAnalysis(
        breakdown: _breakdown,
        timeline: _timeline,
        metrics: metrics is Map
            ? Map<String, dynamic>.from(metrics)
            : null,
        frameMetrics: _frameMetrics,
        improvements: _mistakes
            .map(
              (m) => <String, dynamic>{
                'id': m.id,
                'section': m.section,
                'issue': m.issue,
                'frame': m.frame,
                'time_sec': m.timeSec,
                'start_frame': m.startFrame,
                'start_time_sec': m.startTimeSec,
                'end_frame': m.endFrame,
                'end_time_sec': m.endTimeSec,
                'severity': m.severity,
                'explanation': m.explanation,
                'fix': m.fix,
              },
            )
            .toList(),
      );

      if (!_overlayReady && skeleton != null) {
        _startOverlayPolling();
      }
    } else {
      _analysis = widget.analysis ?? ShotAnalysis.placeholder();
      _analysisVideoUrl = ApiService.resolveMediaUrl(_analysis.analysisVideoUrl);
      _fallbackVideoUrls = const [];
      final localPath = _analysis.videoUrl;
      _localVideoFile = (localPath != null &&
              localPath.isNotEmpty &&
              !localPath.startsWith('http') &&
              File(localPath).existsSync())
          ? File(localPath)
          : null;
      _breakdown = _breakdownFromAnalysis(_analysis);
      _timeline = _timelineFromBreakdown(_breakdown);
      _frameMetrics = const FrameMetricSeries([]);
      _mistakes = const [];
      _overlayFrames = const [];
      _movements = MovementIssue.fromAnalysis(
        breakdown: _breakdown,
        timeline: _timeline,
        frameMetrics: _frameMetrics,
      );
    }

    _coachingReport = CoachingReportService.build(
      breakdown: _breakdown,
      metrics: Map<String, dynamic>.from(
        (widget.results?['metrics'] as Map?) ?? const {},
      ),
      profile: ProfileService.current,
      serverOverall: (widget.results?['overall_score'] as num?)?.toInt() ??
          _analysis.overallScore,
    );
    if (widget.results != null) {
      _enrichedResults = CoachingReportService.enrichResults(
        widget.results!,
        profile: ProfileService.current,
      );
    }
    _activeFrame = _frameMetrics.atSeconds(0);

    // Display score must match FastAPI overall_score when available.
    final serverScore = (widget.results?['overall_score'] as num?)?.toInt();
    _targetScore = serverScore ??
        (_coachingReport.overallScore > 0
            ? _coachingReport.overallScore
            : _analysis.overallScore);

    // Refresh coaching with full profile + history after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCoachingPersonalization();
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scoreAnimation = Tween<double>(begin: 0, end: _targetScore.toDouble())
        .animate(
      CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic),
    );
    _ringAnimation = CurvedAnimation(
      parent: _scoreController,
      curve: Curves.easeOutCubic,
    );

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeController.forward();
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _scoreController.forward();
      _staggerController.forward();
    });
  }

  void _startOverlayPolling() {
    _overlayLoading = true;
    // Probe immediately, then keep checking until the background render finishes.
    unawaited(_pollSkeletonOverlay());
    _overlayPollTimer?.cancel();
    _overlayPollTimer = Timer.periodic(_overlayPollInterval, (_) {
      unawaited(_pollSkeletonOverlay());
    });
  }

  Future<void> _pollSkeletonOverlay() async {
    final skeletonUrl = _skeletonVideoUrl;
    if (!mounted || skeletonUrl == null || _overlayReady) return;

    _overlayPollAttempts += 1;
    if (_overlayPollAttempts > _maxOverlayPollAttempts) {
      _overlayPollTimer?.cancel();
      if (mounted) setState(() => _overlayLoading = false);
      return;
    }

    final ready = await ApiService.isMediaReady(skeletonUrl);
    if (!mounted || !ready || _overlayReady) return;

    _overlayPollTimer?.cancel();
    // ignore: avoid_print
    print('ResultsPage skeleton overlay ready → $skeletonUrl');
    setState(() {
      _overlayReady = true;
      _overlayLoading = false;
      _preferLocalFile = false;
      final previous = _analysisVideoUrl;
      _analysisVideoUrl = skeletonUrl;
      _fallbackVideoUrls = <String>[
        if (previous != null) previous,
        ..._fallbackVideoUrls,
      ].where((url) => url != skeletonUrl).toSet().toList();
    });
  }

  List<BreakdownItem> _parseBreakdown(Map<String, dynamic> raw) {
    final list = raw['biomechanics'] ?? raw['breakdown'];
    if (list is List && list.isNotEmpty) {
      return list
          .whereType<Map>()
          .map((item) => BreakdownItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return _breakdownFromAnalysis(ShotAnalysis.fromAiResponse(raw));
  }

  List<TimelineItem> _parseTimeline(
    Map<String, dynamic> raw,
    List<BreakdownItem> breakdown,
  ) {
    final list = raw['timeline'];
    if (list is List && list.isNotEmpty) {
      return list
          .whereType<Map>()
          .map((item) => TimelineItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return _timelineFromBreakdown(breakdown);
  }

  FrameMetricSeries _parseFrameMetrics(Map<String, dynamic> raw) {
    final direct = raw['frame_metrics'];
    if (direct is List && direct.isNotEmpty) {
      return FrameMetricSeries.fromJson(direct);
    }
    final nested = raw['metrics_json'];
    if (nested is Map && nested['frame_metrics'] is List) {
      return FrameMetricSeries.fromJson(nested['frame_metrics']);
    }
    return const FrameMetricSeries([]);
  }

  List<Mistake> _parseMistakes(Map<String, dynamic> raw) {
    final list = raw['improvements'];
    if (list is! List || list.isEmpty) return const [];
    return list
        .whereType<Map>()
        .map((item) => Mistake.fromJson(Map<String, dynamic>.from(item)))
        .where((m) => m.startTimeSec != null || m.endTimeSec != null)
        .toList();
  }

  List<OverlayFrame> _parseOverlayFrames(Map<String, dynamic> raw) {
    final list = raw['overlay_frames'];
    if (list is! List || list.isEmpty) return const [];
    return list
        .whereType<Map>()
        .map((item) => OverlayFrame.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  void _onPlaybackPosition(double seconds) {
    final player = _playerKey.currentState;
    final durationMs = player?.duration.inMilliseconds ?? 0;
    final nextFrame = _frameMetrics.atSeconds(seconds);
    final sampleChanged = nextFrame?.sampleIndex != _activeFrame?.sampleIndex ||
        nextFrame?.t != _activeFrame?.t;
    final posChanged = (seconds - _positionSeconds).abs() >= 0.04;
    if (!sampleChanged && !posChanged) return;
    if (!mounted) return;

    String? selectedPhase = _selectedPhaseKey;
    if (selectedPhase != null && nextFrame != null) {
      TimelineItem? selected;
      for (final item in _timeline) {
        if ((item.phaseKey ?? item.phase) == selectedPhase) {
          selected = item;
          break;
        }
      }
      final end = selected?.endSeconds;
      if (end != null && seconds > end + 0.05) {
        selectedPhase = null;
      }
    }

    setState(() {
      _positionSeconds = seconds;
      if (durationMs > 0) {
        _durationSeconds = durationMs / 1000.0;
      } else if (_frameMetrics.isNotEmpty) {
        _durationSeconds = _frameMetrics.frames.last.t;
      }
      _activeFrame = nextFrame;
      _selectedPhaseKey = selectedPhase;
    });
  }

  Future<void> _scrubToSeconds(double seconds) async {
    final player = _playerKey.currentState;
    if (player == null || !player.isReady) {
      setState(() {
        _positionSeconds = seconds;
        _activeFrame = _frameMetrics.atSeconds(seconds);
      });
      return;
    }
    // Scrub updates frame/skeleton/measurements from saved data only.
    await player.seekTo(
      Duration(milliseconds: (seconds * 1000).round()),
      autoPlay: false,
    );
    setState(() {
      _positionSeconds = seconds;
      _activeFrame = _frameMetrics.atSeconds(seconds);
      _selectedPhaseKey = _activeFrame?.phase;
    });
  }

  List<BreakdownItem> _breakdownFromAnalysis(ShotAnalysis analysis) {
    return [
      BreakdownItem(
        category: 'Stance',
        score: analysis.balanceScore,
        status: analysis.balanceScore >= 80
            ? 'PASS'
            : analysis.balanceScore >= 65
                ? 'NEEDS_WORK'
                : 'FAIL',
        timestamp: '00:00',
        seconds: 0,
        phase: 'Stance',
        phaseKey: 'setup',
        issue: 'Stance check',
        correction: 'Set a balanced shoulder-width base',
      ),
      BreakdownItem(
        category: 'Load',
        score: analysis.arcScore,
        status: analysis.arcScore >= 80
            ? 'PASS'
            : analysis.arcScore >= 65
                ? 'NEEDS_WORK'
                : 'FAIL',
        timestamp: '00:02',
        seconds: 2,
        phase: 'Load',
        phaseKey: 'knee_load',
        issue: 'Load check',
        correction: 'Load your legs before rising',
      ),
      BreakdownItem(
        category: 'Set Point',
        score: analysis.elbowScore,
        status: analysis.elbowScore >= 80
            ? 'PASS'
            : analysis.elbowScore >= 65
                ? 'NEEDS_WORK'
                : 'FAIL',
        timestamp: '00:03',
        seconds: 3,
        phase: 'Set Point',
        phaseKey: 'set_point',
        issue: analysis.issues.isNotEmpty
            ? analysis.issues.first
            : 'Review set point',
        correction: analysis.recommendations.isNotEmpty
            ? analysis.recommendations.first
            : 'Set elbow near 90° under the ball',
      ),
      BreakdownItem(
        category: 'Release',
        score: analysis.elbowScore,
        status: analysis.elbowScore >= 80
            ? 'PASS'
            : analysis.elbowScore >= 65
                ? 'NEEDS_WORK'
                : 'FAIL',
        timestamp: '00:03',
        seconds: 3,
        phase: 'Release',
        phaseKey: 'release',
        issue: 'Release check',
        correction: 'Extend through the ball and snap the wrist',
      ),
      BreakdownItem(
        category: 'Follow Through',
        score: analysis.followThroughScore,
        status: analysis.followThroughScore >= 80
            ? 'PASS'
            : analysis.followThroughScore >= 65
                ? 'NEEDS_WORK'
                : 'FAIL',
        timestamp: '00:05',
        seconds: 5,
        phase: 'Follow Through',
        phaseKey: 'follow_through',
        issue: 'Follow through check',
        correction: 'Hold a high goose-neck finish',
      ),
    ];
  }

  List<TimelineItem> _timelineFromBreakdown(List<BreakdownItem> breakdown) {
    String statusFor(String category, String fallback) {
      for (final item in breakdown) {
        if (item.category.toLowerCase().contains(category)) {
          return item.status;
        }
      }
      return fallback;
    }

    return [
      TimelineItem(
        phase: 'Stance',
        timestamp: '00:00',
        status: statusFor('knee', 'PASS'),
        seconds: 0,
        phaseKey: 'setup',
      ),
      TimelineItem(
        phase: 'Release',
        timestamp: '00:03',
        status: statusFor('elbow', 'PASS'),
        seconds: 3,
        phaseKey: 'release',
      ),
      TimelineItem(
        phase: 'Follow Through',
        timestamp: '00:05',
        status: statusFor('follow', 'PASS'),
        seconds: 5,
        phaseKey: 'follow_through',
      ),
    ];
  }

  /// Coaching card tap: open interactive movement detail with clipped review.
  Future<void> _openMovement(MovementIssue issue) async {
    BiomechanicsResult? matched;
    for (final item in _breakdown) {
      if (item.category == issue.sourceCategory ||
          item.category == issue.title) {
        matched = item;
        break;
      }
    }

    setState(() {
      _selectedMovement = issue;
      _selectedPhaseKey = issue.phaseKey;
      _activeFrame = _frameMetrics.atSeconds(issue.peakTime);
      _selectedCategory = matched;
    });

    // Cue the results player to the mistake peak (skeleton when ready).
    await _playerKey.currentState?.seekTo(
      issue.peakPosition,
      playbackSpeed: issue.playbackSpeed,
      autoPlay: false,
    );

    if (!mounted) return;
    context.push(
      AppRoutes.movementDetail,
      extra: MovementDetailArgs(
        issue: issue,
        networkUrl: _analysisVideoUrl,
        fallbackUrls: _fallbackVideoUrls,
        file: _localVideoFile,
        // Prefer skeleton/analysis network URL when overlay is ready.
        preferLocalFile: !_overlayReady,
      ).toExtra(),
    );
  }

  Future<void> _jumpToPhase(TimelineItem item) async {
    final phaseKey = item.phaseKey ?? item.phase;
    final start = item.startSeconds ?? item.seconds;
    final end = item.endSeconds ?? (start + 1.2);
    setState(() {
      _selectedCategory = null;
      _selectedPhaseKey = phaseKey;
      _activeFrame = _frameMetrics.atSeconds(start);
    });

    final player = _playerKey.currentState;
    if (player == null) return;

    // Auto-play the phase window for non-pass phases; pause on clean ones.
    final shouldPlay = item.status.toUpperCase() != 'PASS';
    if (shouldPlay) {
      await player.playClip(
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
        playbackSpeed: 0.5,
      );
    } else {
      await player.seekTo(
        item.seekPosition,
        playbackSpeed: 0.5,
        autoPlay: false,
      );
    }
  }

  List<VideoTimelineMarker> get _videoMarkers {
    // Prefer full phase timeline markers (colored). Fall back to issue markers.
    if (_timeline.isNotEmpty) {
      return _timeline
          .map(
            (item) => VideoTimelineMarker(
              seconds: item.keySeconds ?? item.seconds,
              color: 'PHASE',
              hexColor: item.color,
              label: '${item.phase} · ${item.timestamp}',
            ),
          )
          .toList();
    }
    return _breakdown
        .where((item) => !item.isPass)
        .map(
          (item) => VideoTimelineMarker(
            seconds: item.seconds,
            color: item.displayColor,
            label: '${item.category} · ${item.timestamp}',
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _overlayPollTimer?.cancel();
    _fadeController.dispose();
    _scoreController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _share() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share coming soon')),
    );
  }

  void _analyzeAnother() => context.go(AppRoutes.analyze);

  void _viewProgress() => context.go(AppRoutes.progress);

  List<String> get _improvements {
    if (_coachingReport.recommendations.isNotEmpty) {
      return _coachingReport.recommendations;
    }
    if (_analysis.recommendations.isNotEmpty) {
      return _analysis.recommendations;
    }
    return _breakdown
        .where((item) => item.status.toUpperCase() != 'PASS')
        .map((item) => item.correction)
        .where((text) => text.trim().isNotEmpty)
        .toList();
  }

  String? get _improvementSummary {
    if (_coachingReport.specificFeedback.trim().isNotEmpty) {
      return _coachingReport.specificFeedback;
    }
    final raw = (_enrichedResults ?? widget.results)?['improvement_summary']
        as String?;
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    if (_analysis.issues.isNotEmpty) return _analysis.issues.first;
    return null;
  }

  Future<void> _refreshCoachingPersonalization() async {
    try {
      await ProfileService.loadProfile();
    } catch (_) {}
    List<ShotRecord> history = const [];
    try {
      history = await ShotHistoryService.getUserShots(limit: 10);
    } catch (_) {}
    if (!mounted) return;
    final report = CoachingReportService.build(
      breakdown: _breakdown,
      metrics: Map<String, dynamic>.from(
        (widget.results?['metrics'] as Map?) ?? const {},
      ),
      profile: ProfileService.current,
      history: history,
      serverOverall: _targetScore,
    );
    setState(() {
      _coachingReport = report;
      if (widget.results != null) {
        _enrichedResults = CoachingReportService.enrichResults(
          widget.results!,
          profile: ProfileService.current,
          history: history,
        );
      }
    });
  }

  Future<void> _openShotAiChat() async {
    try {
      await ProfileService.loadProfile();
    } catch (_) {}

    List<ShotRecord> history = const [];
    try {
      history = await ShotHistoryService.getUserShots(limit: 8);
    } catch (_) {}

    if (!mounted) return;

    final coachContext = ShotCoachContext.fromAnalysis(
      analysis: _analysis.copyWith(overallScore: _targetScore),
      breakdown: _breakdown,
      timeline: _timeline,
      rawResults: _enrichedResults ?? widget.results,
      profile: ProfileService.current,
      history: history,
    );

    context.push(AppRoutes.shotAiChat, extra: coachContext.toExtra());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ResultsAppBar(onShare: _share),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_analysisVideoUrl != null || _localVideoFile != null)
                        ShotVideoPlayer(
                          key: _playerKey,
                          networkUrl: _analysisVideoUrl,
                          fallbackUrls: _fallbackVideoUrls,
                          file: _localVideoFile,
                          preferLocalFile:
                              _overlayReady ? false : _preferLocalFile,
                          autoPlay: true,
                          label: _overlayReady
                              ? 'Skeleton analysis overlay'
                              : 'Your shot',
                          showOverlayBadge: _overlayReady,
                          aspectRatio: 9 / 16,
                          markers: _videoMarkers,
                          onReady: () {
                            final player = _playerKey.currentState;
                            if (player == null || !mounted) return;
                            setState(() {
                              _durationSeconds =
                                  player.duration.inMilliseconds / 1000.0;
                              _positionSeconds =
                                  player.position.inMilliseconds / 1000.0;
                              _activeFrame =
                                  _frameMetrics.atSeconds(_positionSeconds);
                            });
                          },
                          onPositionChanged: _onPlaybackPosition,
                        )
                      else
                        Container(
                          height: 180,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ShootIQTheme.cardBackground,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Analyzed video unavailable',
                            style: TextStyle(color: ShootIQTheme.textSecondary),
                          ),
                        ),
                      if (_overlayLoading && !_overlayReady) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ShootIQTheme.basketballOrange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Adding skeleton overlay…',
                              style: TextStyle(
                                color: ShootIQTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_timeline.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        BiomechanicsTimeline(
                          phases: _timeline,
                          positionSeconds: _positionSeconds,
                          durationSeconds: _durationSeconds > 0
                              ? _durationSeconds
                              : (_frameMetrics.isNotEmpty
                                  ? _frameMetrics.frames.last.t
                                  : 1),
                          selectedPhaseKey: _selectedPhaseKey,
                          activeFrame: _activeFrame,
                          onPhaseSelected: _jumpToPhase,
                          onScrub: _scrubToSeconds,
                        ),
                      ],
                      if (_frameMetrics.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DynamicAnalysisPanel(frame: _activeFrame),
                      ],
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: _scoreController,
                        builder: (context, _) {
                          return _ScoreHero(
                            score: _scoreAnimation.value.round(),
                            ringProgress:
                                _ringAnimation.value * (_targetScore / 100),
                          );
                        },
                      ),
                      if (_selectedCategory != null) ...[
                        const SizedBox(height: 12),
                        _FocusBanner(item: _selectedCategory!),
                      ],
                      if (_movements.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('Movement Breakdown'),
                        const SizedBox(height: 6),
                        Text(
                          'Tap Feet, Knees, Elbow, Release, or Follow Through to open the skeleton clip at that mistake.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._movements.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _MovementCard(
                              item: item,
                              selected: _selectedMovement?.title == item.title,
                              onTap: () {
                                _openMovement(item);
                              },
                            ),
                          ),
                        ),
                      ],
                      if (_timeline.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const _SectionTitle('Shot Phases'),
                        const SizedBox(height: 6),
                        Text(
                          'Tap any phase to jump there on the video.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _TimelineCard(
                          items: _timeline,
                          onTap: _jumpToPhase,
                        ),
                      ],
                      if (_coachingReport.pointLosses.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('Why You Lost Points'),
                        const SizedBox(height: 6),
                        Text(
                          'Where this shot dropped below ideal form.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _WhyLostPointsCard(items: _coachingReport.pointLosses),
                      ],
                      if (_mistakes.isNotEmpty &&
                          (_analysisVideoUrl != null ||
                              _skeletonVideoUrl != null)) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('Mistake Clips'),
                        const SizedBox(height: 6),
                        Text(
                          'Tap an issue to play just that segment with skeleton overlay.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: MistakeClipPlayer(
                            videoUrl: ApiService.resolveMediaUrl(
                                  _skeletonVideoUrl ?? _analysisVideoUrl,
                                ) ??
                                _analysisVideoUrl!,
                            improvements: _mistakes,
                            overlayFrames: _overlayFrames,
                            height: 520,
                          ),
                        ),
                      ],
                      if (_coachingReport.priorities.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('Your Biggest Improvements'),
                        const SizedBox(height: 6),
                        Text(
                          'Top 3 priorities — fix these first.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _PriorityImprovementsCard(
                          priorities: _coachingReport.priorities,
                        ),
                      ],
                      if (_improvements.isNotEmpty ||
                          _improvementSummary != null) ...[
                        const SizedBox(height: 20),
                        const _SectionTitle('Coach Notes'),
                        const SizedBox(height: 6),
                        Text(
                          'Specific cues from this analysis.',
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ImprovementsCard(
                          summary: _improvementSummary,
                          improvements: _improvements,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _AskAiAboutShotCard(onTap: _openShotAiChat),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: _analyzeAnother,
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
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Analyze Another Shot'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _viewProgress,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ShootIQTheme.textPrimary,
                            side: BorderSide(
                              color: ShootIQTheme.surfaceElevated,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('View Progress'),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ShootIQTheme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }
}

class _ResultsAppBar extends StatelessWidget {
  const _ResultsAppBar({required this.onShare});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          const SizedBox(width: 48),
          const Expanded(
            child: Text(
              'Your Shot Analysis',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          IconButton(
            onPressed: onShare,
            icon: const Icon(
              Icons.ios_share_rounded,
              color: ShootIQTheme.textPrimary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreHero extends StatelessWidget {
  const _ScoreHero({
    required this.score,
    required this.ringProgress,
  });

  final int score;
  final double ringProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: CircularProgressIndicator(
                    value: ringProgress.clamp(0.0, 1.0),
                    strokeWidth: 8,
                    backgroundColor: ShootIQTheme.cardBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ShootIQTheme.basketballOrange,
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$score',
                        style: const TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const TextSpan(
                        text: '/100',
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ShootIQ Score',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your form score from MediaPipe biomechanics.',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.item});
  final BiomechanicsResult item;

  @override
  Widget build(BuildContext context) {
    final accent = switch (item.displayColor) {
      'GREEN' => const Color(0xFF22C55E),
      'RED' => ShootIQTheme.redAccent,
      _ => ShootIQTheme.primaryBlue,
    };
    final labels = item.highlightLabels;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focusing: ${item.category}'
            '${item.phase != null ? ' · ${item.phase}' : ''}',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: labels
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  final MovementIssue item;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Color accent = switch (item.displayColor) {
      'GREEN' => const Color(0xFF22C55E),
      'RED' => ShootIQTheme.redAccent,
      _ => ShootIQTheme.primaryBlue,
    };
    final statusIcon = item.isPass
        ? Icons.check_circle_rounded
        : item.isFail
            ? Icons.cancel_rounded
            : Icons.error_rounded;
    final statusLabel = item.isPass
        ? 'PASS'
        : item.isFail
            ? 'FAIL'
            : 'WARN';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: selected ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.75 : 0.35),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${item.score}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: ShootIQTheme.textSecondary,
                    size: 22,
                  ),
                ],
              ),
              if (item.phase != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Phase: ${item.phase}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _CardMetaRow(
                label: 'Mistake',
                value: item.mistake,
                accent: accent,
              ),
              const SizedBox(height: 8),
              _CardMetaRow(
                label: 'Timestamp',
                value: item.timestampLabel,
                accent: ShootIQTheme.basketballOrange,
              ),
              if (item.correction.isNotEmpty) ...[
                const SizedBox(height: 8),
                _CardMetaRow(
                  label: 'Correction',
                  value: item.correction,
                  accent: const Color(0xFF22C55E),
                ),
              ],
              if (item.affectedBodyParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: item.affectedBodyParts
                      .take(4)
                      .map(
                        (part) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            part,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 16,
                    color: ShootIQTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tap to open video at ${item.timestampLabel} · ${item.playbackSpeed}x',
                      style: TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMetaRow extends StatelessWidget {
  const _CardMetaRow({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: accent.withValues(alpha: 0.95),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.items,
    required this.onTap,
  });

  final List<TimelineItem> items;
  final ValueChanged<TimelineItem> onTap;

  Color _phaseColor(TimelineItem item) {
    final hex = item.color;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      final value = int.tryParse(hex.substring(1), radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return switch (item.status) {
      'PASS' => const Color(0xFF22C55E),
      'FAIL' => const Color(0xFFEF4444),
      _ => const Color(0xFFEAB308),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: items.map((item) {
          final color = _phaseColor(item);
          return InkWell(
            onTap: () => onTap(item),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      item.timestamp,
                      style: const TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.phase,
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    item.statusEmoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WhyLostPointsCard extends StatelessWidget {
  const _WhyLostPointsCard({required this.items});

  final List<PointLossItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].category,
                        style: const TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${items[i].reason}',
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '-${items[i].pointsLost}',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriorityImprovementsCard extends StatelessWidget {
  const _PriorityImprovementsCard({required this.priorities});

  final List<CoachingPriority> priorities;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
        ),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < priorities.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${priorities[i].rank}',
                    style: const TextStyle(
                      color: ShootIQTheme.basketballOrange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        priorities[i].category,
                        style: const TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        priorities[i].observation,
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fix: ${priorities[i].fix}',
                        style: const TextStyle(
                          color: ShootIQTheme.basketballOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImprovementsCard extends StatelessWidget {
  const _ImprovementsCard({
    required this.improvements,
    this.summary,
  });

  final List<String> improvements;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary != null && summary!.trim().isNotEmpty) ...[
            Text(
              summary!,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (improvements.isNotEmpty) const SizedBox(height: 14),
          ],
          for (var i = 0; i < improvements.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: ShootIQTheme.basketballOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    improvements[i],
                    style: const TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AskAiAboutShotCard extends StatefulWidget {
  const _AskAiAboutShotCard({required this.onTap});

  final Future<void> Function() onTap;

  @override
  State<_AskAiAboutShotCard> createState() => _AskAiAboutShotCardState();
}

class _AskAiAboutShotCardState extends State<_AskAiAboutShotCard> {
  bool _pressed = false;
  bool _loading = false;

  Future<void> _handleTap() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ShootIQTheme.cardBackground,
                ShootIQTheme.surfaceElevated,
                ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
              ],
            ),
            border: Border.all(
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: ShootIQTheme.basketballOrange,
                        ),
                      )
                    : const Icon(
                        Icons.psychology_rounded,
                        color: ShootIQTheme.basketballOrange,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💬 Ask AI About This Shot',
                      style: TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Get personalized feedback about this analysis.',
                      style: TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: ShootIQTheme.basketballOrange,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
