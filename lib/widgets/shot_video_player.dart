import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/breakdown_item.dart';
import 'package:video_player/video_player.dart';

/// Network/file video player with play/pause, speed, replay, and fullscreen.
class ShotVideoPlayer extends StatefulWidget {
  const ShotVideoPlayer({
    super.key,
    this.networkUrl,
    this.fallbackUrls = const [],
    this.file,
    this.preferLocalFile = true,
    this.autoPlay = false,
    this.aspectRatio = 16 / 10,
    this.label,
    this.showControls = true,
    this.showOverlayBadge = false,
    this.markers = const [],
    this.segmentStart,
    this.segmentEnd,
    this.autoPlayOnMarkerSeek = false,
    this.onReady,
    this.onPositionChanged,
    this.onSegmentEnded,
  });

  final String? networkUrl;

  /// Tried in order if [networkUrl] fails to initialize.
  final List<String> fallbackUrls;
  final File? file;

  /// When true (default), play [file] first so Results works the instant
  /// the AI report returns — no wait on network / overlay render.
  final bool preferLocalFile;
  final bool autoPlay;
  final double aspectRatio;
  final String? label;
  final bool showControls;

  /// Shows a "Skeleton overlay" chip when playing the analysis video.
  final bool showOverlayBadge;

  /// Biomechanics problem markers drawn on the scrubber.
  final List<VideoTimelineMarker> markers;

  /// Optional mistake-segment bounds. When set, playback never continues
  /// past [segmentEnd] (used by MovementDetailPage).
  final Duration? segmentStart;
  final Duration? segmentEnd;

  /// When false (default), tapping a scrubber marker seeks and pauses.
  final bool autoPlayOnMarkerSeek;

  /// Fired once the active controller is initialized and ready.
  final VoidCallback? onReady;

  /// Fired on controller ticks with the current playback position (seconds).
  final ValueChanged<double>? onPositionChanged;

  /// Fired when playback is auto-paused at [segmentEnd].
  final VoidCallback? onSegmentEnded;

  @override
  State<ShotVideoPlayer> createState() => ShotVideoPlayerState();
}

class ShotVideoPlayerState extends State<ShotVideoPlayer> {
  static const _speeds = <double>[0.25, 0.5, 1.0, 1.5, 2.0];

  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;
  double _playbackSpeed = 1.0;
  VoidCallback? _positionListener;

  /// Active clip end enforced by the controller listener (never plays past).
  Duration? _activeClipStart;
  Duration? _activeClipEnd;
  bool _stoppingAtSegmentEnd = false;

  bool get isReady => _ready && _controller != null;
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  Duration get position => _controller?.value.position ?? Duration.zero;
  Duration get duration => _controller?.value.duration ?? Duration.zero;
  double get playbackSpeed => _playbackSpeed;

  Duration? get _effectiveClipStart =>
      _activeClipStart ?? widget.segmentStart;
  Duration? get _effectiveClipEnd => _activeClipEnd ?? widget.segmentEnd;

  /// Listen to underlying controller ticks (for synced compare scrubbers).
  void addPlaybackListener(VoidCallback listener) {
    _controller?.addListener(listener);
  }

  void removePlaybackListener(VoidCallback listener) {
    _controller?.removeListener(listener);
  }

  void _emitPosition() {
    final c = _controller;
    if (c == null || !_ready) return;
    widget.onPositionChanged?.call(c.value.position.inMilliseconds / 1000.0);
  }

  /// Pause and snap when playback reaches the active segment end.
  void _enforceSegmentBounds() {
    final c = _controller;
    final end = _effectiveClipEnd;
    if (c == null || !_ready || end == null || _stoppingAtSegmentEnd) return;

    if (c.value.isPlaying && c.value.position >= end) {
      _stoppingAtSegmentEnd = true;
      c.pause();
      c.seekTo(end);
      widget.onSegmentEnded?.call();
      if (mounted) setState(() {});
      _stoppingAtSegmentEnd = false;
    }
  }

  Duration _clampToDuration(Duration position) {
    final c = _controller;
    if (c == null) return position;
    final total = c.value.duration;
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  Future<void> play() async {
    final c = _controller;
    if (c == null || !_ready) return;

    final start = _effectiveClipStart;
    final end = _effectiveClipEnd;
    // If a segment is active and we're outside it, restart from start.
    if (start != null && end != null) {
      final pos = c.value.position;
      if (pos < start - const Duration(milliseconds: 40) ||
          pos >= end - const Duration(milliseconds: 40)) {
        await playClip(start: start, end: end);
        return;
      }
    }

    await c.play();
    if (mounted) setState(() {});
  }

  Future<void> pause() async {
    final c = _controller;
    if (c == null || !_ready) return;
    await c.pause();
    if (mounted) setState(() {});
  }

  Future<void> setSpeed(double speed) => _setPlaybackSpeed(speed);

  /// Seek the analyzed video to [position].
  ///
  /// Used by coaching cards: jump to the issue, optionally force 0.5x, then play.
  Future<void> seekTo(
    Duration position, {
    double? playbackSpeed,
    bool autoPlay = true,
  }) async {
    final c = _controller;
    if (c == null || !_ready) return;
    final clamped = _clampToDuration(position);

    if (playbackSpeed != null) {
      await _setPlaybackSpeed(playbackSpeed);
    }

    await c.seekTo(clamped);
    if (autoPlay) {
      await play();
    } else {
      await c.pause();
    }
    if (mounted) setState(() {});
  }

  /// Seek to [start], play, then pause when playback reaches [end].
  ///
  /// Used by MovementDetailPage for mistake-section clips. The controller
  /// listener enforces [end] on every tick so playback never continues.
  Future<void> playClip({
    required Duration start,
    required Duration end,
    double? playbackSpeed,
  }) async {
    final c = _controller;
    if (c == null || !_ready) return;

    final safeStart = _clampToDuration(start);
    var safeEnd = _clampToDuration(end);
    if (safeEnd <= safeStart) {
      safeEnd = _clampToDuration(
        safeStart + const Duration(milliseconds: 400),
      );
    }

    _activeClipStart = safeStart;
    _activeClipEnd = safeEnd;

    if (playbackSpeed != null) {
      await _setPlaybackSpeed(playbackSpeed);
    }

    await c.pause();
    await c.seekTo(safeStart);
    await c.play();
    if (mounted) setState(() {});
  }

  /// Clear an explicitly set playClip window (widget segment* still apply).
  void clearClipWindow() {
    _activeClipStart = null;
    _activeClipEnd = null;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ShotVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.file?.path != widget.file?.path ||
        oldWidget.preferLocalFile != widget.preferLocalFile ||
        oldWidget.fallbackUrls.join('|') != widget.fallbackUrls.join('|')) {
      _disposeController();
      _init();
      return;
    }
    if (oldWidget.segmentStart != widget.segmentStart ||
        oldWidget.segmentEnd != widget.segmentEnd) {
      _activeClipStart = widget.segmentStart;
      _activeClipEnd = widget.segmentEnd;
    }
    if (oldWidget.markers.length != widget.markers.length) {
      setState(() {});
    }
  }

  Future<void> _init() async {
    setState(() {
      _error = null;
      _ready = false;
    });

    final networkCandidates = <String>[
      if (widget.networkUrl != null && widget.networkUrl!.isNotEmpty)
        widget.networkUrl!,
      ...widget.fallbackUrls.where((u) => u.isNotEmpty),
    ];
    final candidates = <Object>[
      if (widget.preferLocalFile && widget.file != null) widget.file!,
      ...networkCandidates,
      if (!widget.preferLocalFile && widget.file != null) widget.file!,
    ];

    if (candidates.isEmpty) {
      setState(() => _error = 'No video available');
      return;
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final VideoPlayerController controller;
        if (candidate is File) {
          if (!await candidate.exists()) continue;
          // ignore: avoid_print
          print('ShotVideoPlayer trying file: ${candidate.path}');
          controller = VideoPlayerController.file(candidate);
        } else {
          final url = candidate.toString();
          final localFile = _localFileFromPath(url);
          if (localFile != null) {
            if (!await localFile.exists()) continue;
            // ignore: avoid_print
            print('ShotVideoPlayer trying local path: ${localFile.path}');
            controller = VideoPlayerController.file(localFile);
          } else {
            // ignore: avoid_print
            print('ShotVideoPlayer trying url: $url');
            controller = VideoPlayerController.networkUrl(Uri.parse(url));
          }
        }

        _controller = controller;
        await controller.initialize();
        controller.setLooping(false);
        await _applyPlaybackSpeed(controller, _playbackSpeed);
        if (widget.autoPlay) {
          await controller.play();
        }
        _positionListener = () {
          _enforceSegmentBounds();
          if (mounted) setState(() {});
          _emitPosition();
        };
        controller.addListener(_positionListener!);
        if (!mounted) return;
        _activeClipStart = widget.segmentStart;
        _activeClipEnd = widget.segmentEnd;
        setState(() => _ready = true);
        widget.onReady?.call();
        _emitPosition();
        return;
      } catch (e) {
        lastError = e;
        // ignore: avoid_print
        print('ShotVideoPlayer candidate failed: $e');
        _disposeController();
      }
    }

    if (!mounted) return;
    setState(() => _error = 'Could not play video');
    // ignore: avoid_print
    print('ShotVideoPlayer error: $lastError');
  }

  /// Local on-device paths are often passed as [networkUrl] (compare/history).
  static File? _localFileFromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return null;
    }
    if (path.startsWith('file://')) {
      try {
        return File(Uri.parse(path).toFilePath());
      } catch (_) {
        return null;
      }
    }
    // Absolute / relative filesystem paths.
    if (path.startsWith('/') ||
        path.contains(Platform.pathSeparator) ||
        path.contains('\\')) {
      return File(path);
    }
    return null;
  }

  Future<void> _applyPlaybackSpeed(
    VideoPlayerController controller,
    double speed,
  ) async {
    await controller.setPlaybackSpeed(speed);
    // Slow-mo analysis is clearer without audio pitch artifacts.
    await controller.setVolume(speed < 1.0 ? 0.0 : 1.0);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => _playbackSpeed = speed);
    await _applyPlaybackSpeed(c, speed);
    if (mounted) setState(() {});
  }

  Future<void> _showSpeedMenu() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Playback speed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ..._speeds.map((speed) {
                  final active = speed == _playbackSpeed;
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(speed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      _speedLabel(speed),
                      style: TextStyle(
                        color: active
                            ? ShootIQTheme.basketballOrange
                            : ShootIQTheme.textPrimary,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    trailing: active
                        ? const Icon(
                            Icons.check_rounded,
                            color: ShootIQTheme.basketballOrange,
                          )
                        : null,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _setPlaybackSpeed(selected);
    }
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      c.pause();
      if (mounted) setState(() {});
      return;
    }
    // Route through play() so segment bounds / playClip restart are honored.
    unawaited(play());
  }

  Future<void> _replay() async {
    final c = _controller;
    if (c == null || !_ready) return;
    final start = _effectiveClipStart ?? Duration.zero;
    final end = _effectiveClipEnd;
    if (end != null) {
      await playClip(start: start, end: end);
      return;
    }
    await c.seekTo(Duration.zero);
    await c.play();
  }

  /// Step one frame at ~30fps while paused (or pause then step).
  Future<void> _stepFrame(int direction) async {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      await c.pause();
    }
    const frame = Duration(milliseconds: 33);
    final next = c.value.position + (frame * direction);
    final duration = c.value.duration;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > duration ? duration : next);
    await c.seekTo(clamped);
    if (mounted) setState(() {});
  }

  Future<void> _openFullscreen() async {
    final url = widget.networkUrl;
    final file = widget.file ?? ShotVideoPlayerState._localFileFromPath(url);
    if (url == null && file == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenShotPlayer(
          networkUrl: url,
          file: file,
          initialSpeed: _playbackSpeed,
        ),
      ),
    );
  }

  void _disposeController() {
    final listener = _positionListener;
    if (listener != null) {
      _controller?.removeListener(listener);
    }
    _positionListener = null;
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  static String _speedLabel(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toStringAsFixed(1)}x';
    }
    return '${speed}x';
  }

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds.clamp(0, 99999);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: ShootIQTheme.surfaceElevated,
              child: _buildBody(),
            ),
          ),
        ),
        if (widget.showControls && _ready) ...[
          const SizedBox(height: 12),
          _AnalysisControls(
            controller: _controller!,
            playbackSpeed: _playbackSpeed,
            markers: widget.markers,
            onTogglePlay: _togglePlay,
            onReplay: _replay,
            onStepBack: () => _stepFrame(-1),
            onStepForward: () => _stepFrame(1),
            onOpenFullscreen: _openFullscreen,
            onShowSpeedMenu: _showSpeedMenu,
            onSeek: (value) async {
              final c = _controller;
              if (c == null) return;
              final duration = c.value.duration;
              // Scrubbing pauses so the user can inspect the frame.
              await c.pause();
              await c.seekTo(duration * value);
              if (mounted) setState(() {});
            },
            onMarkerTap: (marker) {
              seekTo(
                Duration(milliseconds: (marker.seconds * 1000).round()),
                playbackSpeed: 0.5,
                autoPlay: widget.autoPlayOnMarkerSeek,
              );
            },
            formatDuration: _formatDuration,
            speedLabel: _speedLabel,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ShootIQTheme.textSecondary),
          ),
        ),
      );
    }
    final c = _controller;
    if (!_ready || c == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: ShootIQTheme.basketballOrange,
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (widget.showOverlayBadge)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ShootIQTheme.basketballOrange.withValues(alpha: 0.55),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.accessibility_new_rounded,
                      size: 14,
                      color: ShootIQTheme.basketballOrange,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Skeleton overlay',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!c.value.isPlaying)
            Container(
              color: Colors.black.withValues(alpha: 0.28),
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalysisControls extends StatelessWidget {
  const _AnalysisControls({
    required this.controller,
    required this.playbackSpeed,
    required this.markers,
    required this.onTogglePlay,
    required this.onReplay,
    required this.onStepBack,
    required this.onStepForward,
    required this.onOpenFullscreen,
    required this.onShowSpeedMenu,
    required this.onSeek,
    required this.onMarkerTap,
    required this.formatDuration,
    required this.speedLabel,
  });

  final VideoPlayerController controller;
  final double playbackSpeed;
  final List<VideoTimelineMarker> markers;
  final VoidCallback onTogglePlay;
  final VoidCallback onReplay;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final VoidCallback onOpenFullscreen;
  final VoidCallback onShowSpeedMenu;
  final ValueChanged<double> onSeek;
  final ValueChanged<VideoTimelineMarker> onMarkerTap;
  final String Function(Duration) formatDuration;
  final String Function(double) speedLabel;

  Color _markerColor(VideoTimelineMarker marker) {
    final hex = marker.hexColor;
    if (hex != null && hex.isNotEmpty) {
      final cleaned = hex.replaceFirst('#', '');
      if (cleaned.length == 6) {
        final value = int.tryParse(cleaned, radix: 16);
        if (value != null) return Color(0xFF000000 | value);
      }
    }
    return switch (marker.color.toUpperCase()) {
      'GREEN' => const Color(0xFF22C55E),
      'RED' => const Color(0xFFEF4444),
      'BLUE' => const Color(0xFF60A5FA),
      'PURPLE' => const Color(0xFFC084FC),
      'ORANGE' => const Color(0xFFFB923C),
      'GRAY' || 'GREY' => const Color(0xFF94A3B8),
      _ => const Color(0xFFEAB308),
    };
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final position = value.position;
    final duration = value.duration;
    final durationMs = duration.inMilliseconds;
    final progress = durationMs == 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ControlIconButton(
                icon: value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: onTogglePlay,
                emphasized: true,
              ),
              Expanded(
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return SizedBox(
                          height: 18,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape:
                                        const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                    activeTrackColor:
                                        ShootIQTheme.basketballOrange,
                                    inactiveTrackColor:
                                        Colors.white.withValues(alpha: 0.14),
                                    thumbColor: Colors.white,
                                    overlayColor: ShootIQTheme.basketballOrange
                                        .withValues(alpha: 0.2),
                                  ),
                                  child: Slider(
                                    value: progress,
                                    onChanged: onSeek,
                                  ),
                                ),
                              ),
                              if (durationMs > 0)
                                ...markers.map((marker) {
                                  final t = (marker.seconds * 1000)
                                          .clamp(0, durationMs) /
                                      durationMs;
                                  final left = (width * t).clamp(0.0, width);
                                  return Positioned(
                                    left: left - 6,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () => onMarkerTap(marker),
                                      behavior: HitTestBehavior.opaque,
                                      child: Tooltip(
                                        message: marker.label ??
                                            formatDuration(
                                              Duration(
                                                milliseconds:
                                                    (marker.seconds * 1000)
                                                        .round(),
                                              ),
                                            ),
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _markerColor(marker),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.black87,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              _SpeedChip(
                label: speedLabel(playbackSpeed),
                onTap: onShowSpeedMenu,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '${formatDuration(position)} / ${formatDuration(duration)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _ControlIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous frame',
                onPressed: onStepBack,
                compact: true,
              ),
              _ControlIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: 'Next frame',
                onPressed: onStepForward,
                compact: true,
              ),
              _ControlIconButton(
                icon: Icons.replay_rounded,
                tooltip: 'Replay',
                onPressed: onReplay,
                compact: true,
              ),
              _ControlIconButton(
                icon: Icons.fullscreen_rounded,
                tooltip: 'Fullscreen',
                onPressed: onOpenFullscreen,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: ShootIQTheme.basketballOrange,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.emphasized = false,
    this.compact = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      padding: EdgeInsets.all(compact ? 6 : 8),
      constraints: BoxConstraints(
        minWidth: compact ? 36 : 44,
        minHeight: compact ? 36 : 44,
      ),
      icon: Icon(
        icon,
        color: emphasized
            ? ShootIQTheme.basketballOrange
            : ShootIQTheme.textPrimary,
        size: emphasized ? 30 : 22,
      ),
    );
    return button;
  }
}

class _FullscreenShotPlayer extends StatefulWidget {
  const _FullscreenShotPlayer({
    this.networkUrl,
    this.file,
    this.initialSpeed = 1.0,
  });

  final String? networkUrl;
  final File? file;
  final double initialSpeed;

  @override
  State<_FullscreenShotPlayer> createState() => _FullscreenShotPlayerState();
}

class _FullscreenShotPlayerState extends State<_FullscreenShotPlayer> {
  static const _speeds = <double>[0.25, 0.5, 1.0, 1.5, 2.0];

  VideoPlayerController? _controller;
  bool _ready = false;
  late double _playbackSpeed;

  @override
  void initState() {
    super.initState();
    _playbackSpeed = widget.initialSpeed;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
  }

  Future<void> _init() async {
    final localFromUrl =
        ShotVideoPlayerState._localFileFromPath(widget.networkUrl);
    final file = widget.file ?? localFromUrl;
    final controller = file != null
        ? VideoPlayerController.file(file)
        : VideoPlayerController.networkUrl(Uri.parse(widget.networkUrl!));
    _controller = controller;
    await controller.initialize();
    await controller.setPlaybackSpeed(_playbackSpeed);
    await controller.setVolume(_playbackSpeed < 1.0 ? 0.0 : 1.0);
    await controller.play();
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _setSpeed(double speed) async {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => _playbackSpeed = speed);
    await c.setPlaybackSpeed(speed);
    await c.setVolume(speed < 1.0 ? 0.0 : 1.0);
    if (mounted) setState(() {});
  }

  Future<void> _showSpeedMenu() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF1A1A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Playback speed',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              ..._speeds.map(
                (speed) => ListTile(
                  onTap: () => Navigator.of(context).pop(speed),
                  title: Text(
                    ShotVideoPlayerState._speedLabel(speed),
                    style: TextStyle(
                      color: speed == _playbackSpeed
                          ? ShootIQTheme.basketballOrange
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) await _setSpeed(selected);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('AI Analyzed Shot'),
      ),
      body: Center(
        child: !_ready || c == null
            ? const CircularProgressIndicator(
                color: ShootIQTheme.basketballOrange,
              )
            : AspectRatio(
                aspectRatio: c.value.aspectRatio == 0
                    ? 16 / 9
                    : c.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(c),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    if (c.value.isPlaying) {
                                      c.pause();
                                    } else {
                                      c.play();
                                    }
                                  },
                                  icon: Icon(
                                    c.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    c,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor:
                                          ShootIQTheme.basketballOrange,
                                      bufferedColor: Colors.white24,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _SpeedChip(
                                  label: ShotVideoPlayerState._speedLabel(
                                    _playbackSpeed,
                                  ),
                                  onTap: _showSpeedMenu,
                                ),
                              ],
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${ShotVideoPlayerState._formatDuration(c.value.position)} / ${ShotVideoPlayerState._formatDuration(c.value.duration)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
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

/// Full-screen modal preview for a local shot video.
Future<void> showShotVideoPreview(BuildContext context, File file) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShootIQTheme.darkBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Preview Your Shot',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              ShotVideoPlayer(
                file: file,
                autoPlay: true,
                aspectRatio: 9 / 14,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: ShootIQTheme.buttonBlue,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
