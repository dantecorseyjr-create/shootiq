import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/video_prep_service.dart';
import 'package:shootiq/widgets/error_state.dart';
import 'package:video_player/video_player.dart';

/// Review a recorded/uploaded shot before sending it to AI analysis.
class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({super.key, this.videoPath});

  final String? videoPath;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  VideoPlayerController? _controller;
  VideoValidationResult? _validation;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  String? get _path {
    final fromWidget = widget.videoPath;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    final extra = GoRouterState.of(context).extra;
    if (extra is String && extra.isNotEmpty) return extra;
    if (extra is File) return extra.path;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = _path;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = 'No video selected. Retake or upload a clip.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final file = File(path);
    final validation = await VideoPrepService.validate(file);
    if (!mounted) return;

    if (!validation.isValid) {
      setState(() {
        _loading = false;
        _validation = validation;
        _error = validation.message;
      });
      return;
    }

    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _validation = validation;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Video is not readable. Retake or pick another clip.\n$e';
      });
    }
  }

  void _retake() {
    context.go(AppRoutes.cameraCapture);
  }

  Future<void> _useVideo() async {
    if (_submitting) return;
    final path = _path;
    if (path == null) return;

    setState(() => _submitting = true);
    try {
      final prepared = await VideoPrepService.prepareForUpload(File(path));
      if (!mounted) return;
      PendingAnalysisStore.setVideo(prepared);
      context.push(AppRoutes.processing, extra: prepared);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final duration = _validation?.duration ?? controller?.value.duration;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.camera);
                        }
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: ShootIQTheme.textPrimary,
                        size: 20,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Video Preview',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ShootIQTheme.basketballOrange,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: controller?.value.isInitialized ==
                                      true
                                  ? controller!.value.aspectRatio
                                  : 9 / 14,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: controller?.value.isInitialized == true
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          VideoPlayer(controller!),
                                          Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.all(12),
                                              color: Colors.black
                                                  .withValues(alpha: 0.45),
                                              child: Text(
                                                duration == null
                                                    ? ''
                                                    : 'Duration ${_format(duration)} / 00:15 max',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.videocam_off_rounded,
                                          color: Colors.white
                                              .withValues(alpha: 0.35),
                                          size: 48,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _ValidationCard(
                              validation: _validation,
                              error: _error,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              ErrorState(
                                type: AppErrorInfo.classify(_error!),
                                detail: _error,
                                onRetry: _load,
                                onReturn: () => context.go(AppRoutes.dashboard),
                                returnLabel: 'Return Home',
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: (_error == null &&
                                        (_validation?.isValid ?? false) &&
                                        !_submitting)
                                    ? _useVideo
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: ShootIQTheme.buttonBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: ShootIQTheme
                                      .buttonBlue
                                      .withValues(alpha: 0.35),
                                  side: const BorderSide(
                                    color: ShootIQTheme.redBorder,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Use Video'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                onPressed: _retake,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ShootIQTheme.textPrimary,
                                  side: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: 0.16),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                child: const Text('Retake'),
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

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({
    required this.validation,
    required this.error,
  });

  final VideoValidationResult? validation;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ok = error == null && (validation?.isValid ?? false);
    final accent =
        ok ? const Color(0xFF22C55E) : ShootIQTheme.basketballOrange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? 'Ready for analysis' : 'Fix before continuing',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          _CheckLine(
            ok: validation != null,
            label: 'Video exists',
          ),
          _CheckLine(
            ok: validation?.duration != null &&
                (validation?.isValid ?? false),
            label: 'Duration is acceptable (≤ 15s)',
          ),
          _CheckLine(
            ok: ok,
            label: 'File is readable',
          ),
          if (validation?.hint != null) ...[
            const SizedBox(height: 8),
            Text(
              validation!.hint!,
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.ok, required this.label});
  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: ok ? const Color(0xFF22C55E) : ShootIQTheme.errorRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
