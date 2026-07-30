// Ties the backend's `improvements` list (with start_time_sec/end_time_sec
// per issue) to video playback: tapping a mistake seeks the video to the
// start of that segment, plays it, and auto-pauses at the end so the user
// watches exactly the relevant clip instead of scrubbing manually.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shootiq/widgets/skeleton_overlay_painter.dart';
import 'package:video_player/video_player.dart';

/// One entry from the backend's `improvements` list.
class Mistake {
  Mistake({
    required this.id,
    required this.section,
    required this.issue,
    required this.frame,
    this.timeSec,
    required this.startFrame,
    this.startTimeSec,
    required this.endFrame,
    this.endTimeSec,
    required this.severity,
    required this.explanation,
    required this.fix,
  });

  /// Stable backend id (e.g. `elbow_alignment_01`).
  final String id;
  final String section;
  final String issue;
  final int frame;
  final double? timeSec;
  final int startFrame;
  final double? startTimeSec;
  final int endFrame;
  final double? endTimeSec;
  final String severity; // "high" | "medium" | "low"
  final String explanation;
  final String fix;

  factory Mistake.fromJson(Map<String, dynamic> json) {
    final section = json['section'] as String? ?? '';
    final issue = json['issue'] as String? ?? '';
    final frame = (json['frame'] as num?)?.toInt() ?? 0;
    // Prefer backend id; fall back to a deterministic local key for older JSON.
    final rawId = (json['id'] as String?)?.trim();
    final id = (rawId != null && rawId.isNotEmpty)
        ? rawId
        : '${section.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_$frame';

    return Mistake(
      id: id,
      section: section,
      issue: issue,
      frame: frame,
      timeSec: (json['time_sec'] as num?)?.toDouble(),
      startFrame: (json['start_frame'] as num?)?.toInt() ?? 0,
      startTimeSec: (json['start_time_sec'] as num?)?.toDouble(),
      endFrame: (json['end_frame'] as num?)?.toInt() ?? 0,
      endTimeSec: (json['end_time_sec'] as num?)?.toDouble(),
      severity: json['severity'] as String? ?? 'low',
      explanation: json['explanation'] as String? ?? '',
      fix: json['fix'] as String? ?? '',
    );
  }

  Color get severityColor {
    switch (severity) {
      case 'high':
        return const Color(0xFFE63946);
      case 'medium':
        return const Color(0xFFF4A261);
      default:
        return const Color(0xFFE9C46A);
    }
  }
}

class MistakeClipPlayer extends StatefulWidget {
  const MistakeClipPlayer({
    super.key,
    required this.videoUrl,
    required this.improvements,
    required this.overlayFrames,
    this.pauseAtEnd = true,
    this.height = 420,
  });

  final String videoUrl;
  final List<Mistake> improvements;
  final List<OverlayFrame> overlayFrames;

  /// If true, playback pauses at end_time_sec (default).
  final bool pauseAtEnd;

  /// Fixed height when embedded in a scroll view (avoids Expanded conflicts).
  final double height;

  @override
  State<MistakeClipPlayer> createState() => _MistakeClipPlayerState();
}

class _MistakeClipPlayerState extends State<MistakeClipPlayer> {
  static const _speeds = <double>[0.25, 0.5, 0.75, 1.0];

  late VideoPlayerController _controller;
  Mistake? _activeMistake;
  int _activeIndex = -1;
  bool _initialized = false;
  String? _error;
  double _playbackSpeed = 0.5;
  bool _flashHighlight = false;
  int _playGeneration = 0;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) async {
        if (!mounted) return;
        await _controller.setPlaybackSpeed(_playbackSpeed);
        setState(() => _initialized = true);
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      });
    _controller.addListener(_onTick);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    // Rebuild overlay each tick (cheap with binary-search lookup).
    setState(() {});

    if (_activeMistake == null || !widget.pauseAtEnd) return;
    final endSec = _activeMistake!.endTimeSec;
    if (endSec == null) return;

    final position = _controller.value.position.inMilliseconds / 1000.0;
    if (position >= endSec) {
      _controller.pause();
      _controller.seekTo(Duration(milliseconds: (endSec * 1000).round()));
    }
  }

  Future<void> _setSpeed(double speed) async {
    _playbackSpeed = speed;
    await _controller.setPlaybackSpeed(speed);
    if (mounted) setState(() {});
  }

  Future<void> _playMistakeClip(
    Mistake mistake, {
    required int index,
    bool flash = false,
  }) async {
    final generation = ++_playGeneration;
    _flashTimer?.cancel();

    // Stop current playback immediately for seamless transitions.
    await _controller.pause();

    final startSec = mistake.startTimeSec ?? 0.0;
    final start = Duration(milliseconds: (startSec * 1000).round());

    if (!mounted || generation != _playGeneration) return;

    setState(() {
      _activeMistake = mistake;
      _activeIndex = index;
      _flashHighlight = flash;
    });

    // Seek + wait so the first frame is preloaded before play (no black flash).
    await _controller.seekTo(start);
    if (!mounted || generation != _playGeneration) return;

    // Give the decoder a beat to present the seeked frame.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || generation != _playGeneration) return;

    if (flash) {
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || generation != _playGeneration) return;
        setState(() => _flashHighlight = false);
      });
      // Hold on the first frame while joints flash yellow.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted || generation != _playGeneration) return;
      if (_flashHighlight) {
        setState(() => _flashHighlight = false);
      }
    }

    await _controller.setPlaybackSpeed(_playbackSpeed);
    if (!mounted || generation != _playGeneration) return;
    await _controller.play();
  }

  Future<void> _replayActiveClip() async {
    if (_activeMistake == null || _activeIndex < 0) return;
    await _playMistakeClip(
      _activeMistake!,
      index: _activeIndex,
      flash: true,
    );
  }

  Future<void> _playPrevious() async {
    if (widget.improvements.isEmpty) return;
    final nextIndex = _activeIndex <= 0
        ? widget.improvements.length - 1
        : _activeIndex - 1;
    await _playMistakeClip(
      widget.improvements[nextIndex],
      index: nextIndex,
    );
  }

  Future<void> _playNext() async {
    if (widget.improvements.isEmpty) return;
    final nextIndex = (_activeIndex + 1) % widget.improvements.length;
    await _playMistakeClip(
      widget.improvements[nextIndex],
      index: nextIndex,
    );
  }

  Future<void> _playFullVideo() async {
    _playGeneration++;
    _flashTimer?.cancel();
    setState(() {
      _activeMistake = null;
      _activeIndex = -1;
      _flashHighlight = false;
    });
    await _controller.pause();
    await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  OverlayFrame? _currentOverlayFrame() {
    if (widget.overlayFrames.isEmpty || !_initialized) return null;
    final currentSec = _controller.value.position.inMilliseconds / 1000.0;
    return OverlayFrame.findClosest(widget.overlayFrames, currentSec);
  }

  Set<String> get _highlightTokens {
    final section = _activeMistake?.section;
    if (section == null || section.isEmpty) return const {};
    return SkeletonHighlightSets.forSection(section);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Could not load clip video',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    if (!_initialized) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final overlayFrame = _currentOverlayFrame();
    final aspect = _controller.value.aspectRatio == 0
        ? 9 / 16
        : _controller.value.aspectRatio;

    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(_controller),
                if (overlayFrame != null)
                  CustomPaint(
                    painter: SkeletonOverlayPainter(
                      landmarks: overlayFrame.landmarks,
                      jointStatus: overlayFrame.jointStatus,
                      highlightTokens: _highlightTokens,
                      flashHighlight: _flashHighlight,
                    ),
                  ),
                if (_activeMistake != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _activeMistake!.severityColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _activeMistake!.issue,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                            onPressed: _playFullVideo,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _PlaybackControls(
            canNavigate: widget.improvements.length > 1,
            hasActive: _activeMistake != null,
            playbackSpeed: _playbackSpeed,
            speeds: _speeds,
            onPrevious: _playPrevious,
            onNext: _playNext,
            onReplay: _replayActiveClip,
            onSpeedChanged: _setSpeed,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: widget.improvements.length,
              itemBuilder: (context, index) {
                final mistake = widget.improvements[index];
                final isActive = _activeMistake?.id == mistake.id;
                return Card(
                  color: isActive
                      ? mistake.severityColor.withValues(alpha: 0.12)
                      : null,
                  child: ListTile(
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: mistake.severityColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(mistake.issue),
                    subtitle: Text(mistake.fix),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () => _playMistakeClip(mistake, index: index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.canNavigate,
    required this.hasActive,
    required this.playbackSpeed,
    required this.speeds,
    required this.onPrevious,
    required this.onNext,
    required this.onReplay,
    required this.onSpeedChanged,
  });

  final bool canNavigate;
  final bool hasActive;
  final double playbackSpeed;
  final List<double> speeds;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous mistake',
            onPressed: canNavigate ? onPrevious : null,
            icon: const Icon(Icons.skip_previous, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Replay clip',
            onPressed: hasActive ? onReplay : null,
            icon: const Icon(Icons.replay, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Next mistake',
            onPressed: canNavigate ? onNext : null,
            icon: const Icon(Icons.skip_next, color: Colors.white),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double>(
                value: playbackSpeed,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                iconEnabledColor: Colors.white70,
                items: [
                  for (final speed in speeds)
                    DropdownMenuItem(
                      value: speed,
                      child: Text('${speed.toStringAsFixed(2)}x'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSpeedChanged(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
