import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/movement_issue.dart';
import 'package:shootiq/widgets/shot_video_player.dart';

/// Full-screen review of one movement issue with clipped playback.
class MovementDetailPage extends StatefulWidget {
  const MovementDetailPage({
    super.key,
    required this.issue,
    this.networkUrl,
    this.fallbackUrls = const [],
    this.file,
    this.preferLocalFile = true,
  });

  final MovementIssue issue;
  final String? networkUrl;
  final List<String> fallbackUrls;
  final File? file;
  final bool preferLocalFile;

  @override
  State<MovementDetailPage> createState() => _MovementDetailPageState();
}

class _MovementDetailPageState extends State<MovementDetailPage> {
  final GlobalKey<ShotVideoPlayerState> _playerKey =
      GlobalKey<ShotVideoPlayerState>();

  bool _ready = false;
  bool _autoPlayed = false;
  bool _segmentFinished = false;

  MovementIssue get issue => widget.issue;

  Color get _accent => switch (issue.displayColor) {
        'GREEN' => const Color(0xFF22C55E),
        'RED' => const Color(0xFFEF4444),
        _ => const Color(0xFFEAB308),
      };

  bool get _useSkeletonNetwork {
    final url = widget.networkUrl?.toLowerCase() ?? '';
    return url.contains('analysis') ||
        url.contains('skeleton') ||
        url.contains('overlay');
  }

  Future<void> _onPlayerReady() async {
    setState(() => _ready = true);
    if (_autoPlayed) return;
    _autoPlayed = true;

    // Jump to the mistake window and auto-play until the correction end.
    await _playerKey.currentState?.playClip(
      start: issue.startPosition,
      end: issue.endPosition,
      playbackSpeed: issue.playbackSpeed,
    );
    if (mounted) setState(() => _segmentFinished = false);
  }

  void _onPositionChanged(double seconds) {
    if (mounted) setState(() {});
  }

  void _onSegmentEnded() {
    if (mounted) {
      setState(() => _segmentFinished = true);
    }
  }

  Future<void> _togglePlay() async {
    final player = _playerKey.currentState;
    if (player == null || !_ready) return;

    if (player.isPlaying) {
      await player.pause();
      if (mounted) setState(() {});
      return;
    }

    await player.playClip(
      start: issue.startPosition,
      end: issue.endPosition,
      playbackSpeed: issue.playbackSpeed,
    );
    if (mounted) {
      setState(() => _segmentFinished = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerKey.currentState?.isPlaying ?? false;
    final preferLocal = widget.preferLocalFile && !_useSkeletonNetwork;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailAppBar(
              title: issue.title,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ShotVideoPlayer(
                        key: _playerKey,
                        networkUrl: widget.networkUrl,
                        fallbackUrls: widget.fallbackUrls,
                        file: widget.file,
                        preferLocalFile: preferLocal,
                        autoPlay: false,
                        showControls: false,
                        aspectRatio: 9 / 16,
                        label: _useSkeletonNetwork
                            ? 'Skeleton analysis overlay'
                            : 'Shot review',
                        showOverlayBadge: _useSkeletonNetwork,
                        segmentStart: issue.startPosition,
                        segmentEnd: issue.endPosition,
                        onReady: _onPlayerReady,
                        onPositionChanged: _onPositionChanged,
                        onSegmentEnded: _onSegmentEnded,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PlayControls(
                      ready: _ready,
                      isPlaying: isPlaying,
                      segmentFinished: _segmentFinished,
                      accent: _accent,
                      startLabel: _formatTime(issue.startTime),
                      peakLabel: issue.timestampLabel,
                      endLabel: _formatTime(issue.endTime),
                      speed: issue.playbackSpeed,
                      onToggle: _togglePlay,
                    ),
                    const SizedBox(height: 18),
                    _ScoreHeader(
                      title: issue.title,
                      score: issue.score,
                      status: issue.status,
                      accent: _accent,
                      phase: issue.phase,
                    ),
                    const SizedBox(height: 14),
                    _InfoBlock(
                      label: 'Mistake',
                      text: issue.mistake.isNotEmpty
                          ? issue.mistake
                          : 'No specific mistake flagged.',
                      accent: _accent,
                    ),
                    const SizedBox(height: 12),
                    _InfoBlock(
                      label: 'Timestamp',
                      text:
                          '${issue.timestampLabel}  ·  ${_formatTime(issue.startTime)} → ${_formatTime(issue.endTime)}',
                      accent: ShootIQTheme.basketballOrange,
                    ),
                    if (issue.explanation.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoBlock(
                        label: 'Explanation',
                        text: issue.explanation,
                        accent: ShootIQTheme.textPrimary,
                      ),
                    ],
                    if (issue.correction.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InfoBlock(
                        label: 'Correction',
                        text: issue.correction,
                        accent: const Color(0xFF22C55E),
                      ),
                    ],
                    if (issue.measurement != null &&
                        issue.measurement!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        issue.measurement!,
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Affected body parts',
                      style: TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BodyPartHighlightReady(
                      labels: issue.affectedBodyParts,
                      poseLandmarkKeys: issue.poseLandmarkKeys,
                      accent: _accent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    final totalMs = (seconds * 1000).round().clamp(0, 99999999);
    final totalSec = totalMs ~/ 1000;
    final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
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
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 17,
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

class _PlayControls extends StatelessWidget {
  const _PlayControls({
    required this.ready,
    required this.isPlaying,
    required this.segmentFinished,
    required this.accent,
    required this.startLabel,
    required this.peakLabel,
    required this.endLabel,
    required this.speed,
    required this.onToggle,
  });

  final bool ready;
  final bool isPlaying;
  final bool segmentFinished;
  final Color accent;
  final String startLabel;
  final String peakLabel;
  final String endLabel;
  final double speed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final status = !ready
        ? 'Loading clip…'
        : isPlaying
            ? 'Playing mistake segment'
            : segmentFinished
                ? 'Stopped at correction end'
                : 'Paused — tap to replay';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Row(
        children: [
          Material(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: ready ? onToggle : null,
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: accent,
                  size: 30,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$startLabel → $endLabel · peak $peakLabel · ${speed}x',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.title,
    required this.score,
    required this.status,
    required this.accent,
    this.phase,
  });

  final String title;
  final int score;
  final String status;
  final Color accent;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (phase != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Phase: $phase',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          '$score',
          style: TextStyle(
            color: accent,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.text,
    required this.accent,
  });

  final String label;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chips for affected joints + reserved pose landmark keys for overlay work.
class _BodyPartHighlightReady extends StatelessWidget {
  const _BodyPartHighlightReady({
    required this.labels,
    required this.poseLandmarkKeys,
    required this.accent,
  });

  final List<String> labels;
  final List<String> poseLandmarkKeys;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: labels
              .map(
                (label) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (poseLandmarkKeys.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Skeleton joints tracked: ${poseLandmarkKeys.length}',
            style: TextStyle(
              color: ShootIQTheme.surfaceElevated,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
