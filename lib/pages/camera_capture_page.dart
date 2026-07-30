import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';

enum _CapturePhase { ready, recording, review }

/// Full-screen shooting recording experience with live camera + stick guide.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with TickerProviderStateMixin {
  static const _maxRecordSeconds = 15;
  static const _tips = [
    'Stand 10-15 feet away',
    'Keep your entire body in frame',
    'Use a side angle view',
    'Make sure lighting is good',
  ];

  _CapturePhase _phase = _CapturePhase.ready;
  bool _flashOn = false;
  bool _cameraReady = false;
  bool _isToggling = false;
  bool _isStopping = false;
  bool _isSwitchingCamera = false;
  int _elapsedSeconds = 0;
  int _tipIndex = 0;
  String? _cameraError;
  String? _recordedPath;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  CameraController? _controller;
  Timer? _recordTimer;
  Timer? _tipTimer;

  late final AnimationController _pulseController;
  late final AnimationController _tipFadeController;
  late final AnimationController _reviewController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _tipFadeAnimation;
  late final Animation<double> _reviewFadeAnimation;
  late final Animation<Offset> _reviewSlideAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulseAnimation = Tween<double>(begin: 1, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tipFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
    _tipFadeAnimation = CurvedAnimation(
      parent: _tipFadeController,
      curve: Curves.easeInOut,
    );

    _reviewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _reviewFadeAnimation = CurvedAnimation(
      parent: _reviewController,
      curve: Curves.easeOut,
    );
    _reviewSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _reviewController, curve: Curves.easeOutCubic),
    );

    _pulseController.repeat(reverse: true);
    _startTipRotation();
    _initCamera();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _tipTimer?.cancel();
    _pulseController.dispose();
    _tipFadeController.dispose();
    _reviewController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera({int? preferIndex}) async {
    setState(() {
      _cameraReady = false;
      _cameraError = null;
    });

    try {
      // ignore: avoid_print
      print('CameraCapture: requesting cameras…');
      final cameras = await availableCameras();
      if (!mounted) return;

      // ignore: avoid_print
      print('CameraCapture: found ${cameras.length} camera(s)');
      if (cameras.isEmpty) {
        setState(
          () => _cameraError =
              'Camera permission denied or no cameras found. Enable camera access in Settings, then retry.',
        );
        return;
      }

      _cameras = cameras;
      // Prefer back camera on phones; Macs usually only have a front webcam.
      var index = preferIndex;
      if (index == null || index < 0 || index >= cameras.length) {
        index = cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (index < 0) {
          index = cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
          );
        }
        if (index < 0) index = 0;
      }
      final selected = cameras[index];

      final previous = _controller;
      CameraController? controller;
      Object? lastError;

      // Medium preset keeps uploads lighter while staying sharp enough for pose.
      for (final withAudio in const [true, false]) {
        try {
          controller = CameraController(
            selected,
            ResolutionPreset.medium,
            enableAudio: withAudio,
          );
          await controller.initialize();
          lastError = null;
          // ignore: avoid_print
          print(
            'CameraCapture: initialized ${selected.name} audio=$withAudio',
          );
          break;
        } catch (e) {
          lastError = e;
          // ignore: avoid_print
          print('CameraCapture: init failed audio=$withAudio → $e');
          await controller?.dispose();
          controller = null;
        }
      }

      if (controller == null || !controller.value.isInitialized) {
        throw lastError ??
            Exception('CameraController failed to initialize');
      }

      await previous?.dispose();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _cameraIndex = index!;
        _cameraReady = true;
        _cameraError = null;
        _flashOn = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('CameraCapture: fatal init error → $e');
      if (!mounted) return;
      final denied = e.toString().toLowerCase().contains('permission');
      setState(() {
        _cameraReady = false;
        _cameraError = denied
            ? 'Camera permission denied. Enable camera access in Settings, then retry.'
            : 'Camera unavailable. Check System Settings → Privacy & Security → Camera for ShootIQ.\n\n$e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera ||
        _phase == _CapturePhase.recording ||
        _cameras.length < 2) {
      return;
    }
    setState(() => _isSwitchingCamera = true);
    final next = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(preferIndex: next);
    if (mounted) setState(() => _isSwitchingCamera = false);
  }

  void _startTipRotation() {
    _tipTimer?.cancel();
    _tipTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _phase != _CapturePhase.ready) return;
      await _tipFadeController.reverse();
      if (!mounted) return;
      setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
      await _tipFadeController.forward();
    });
  }

  String get _timerLabel {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final next = !_flashOn;
    try {
      await controller.setFlashMode(
        next ? FlashMode.torch : FlashMode.off,
      );
      if (!mounted) return;
      setState(() => _flashOn = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flash is not available on this camera.')),
      );
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.analyze);
    }
  }

  Future<void> _toggleRecording() async {
    if (_phase == _CapturePhase.review || _isToggling) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is still starting up.')),
      );
      return;
    }

    _isToggling = true;
    try {
      if (_phase == _CapturePhase.ready) {
        await controller.startVideoRecording();
        if (!mounted) return;

        setState(() {
          _phase = _CapturePhase.recording;
          _elapsedSeconds = 0;
          _recordedPath = null;
        });
        _pulseController.stop();
        _pulseController.value = 1;
        _tipTimer?.cancel();

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || _isStopping) return;
          final next = _elapsedSeconds + 1;
          setState(() => _elapsedSeconds = next);
          if (next >= _maxRecordSeconds) {
            // ignore: unawaited_futures
            _stopRecording(toReview: true);
          }
        });
        return;
      }

      await _stopRecording(toReview: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not record video. Try again.')),
      );
    } finally {
      _isToggling = false;
    }
  }

  Future<void> _stopRecording({required bool toReview}) async {
    if (_isStopping) return;
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      _recordTimer?.cancel();
      return;
    }

    _isStopping = true;
    _recordTimer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      if (!toReview) {
        try {
          await File(file.path).delete();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _phase = _CapturePhase.ready;
          _elapsedSeconds = 0;
          _recordedPath = null;
        });
        _pulseController.repeat(reverse: true);
        _startTipRotation();
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final savePath = p.join(
        dir.path,
        'shootiq_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await File(file.path).copy(savePath);

      if (!mounted) return;
      setState(() {
        _phase = _CapturePhase.review;
        _recordedPath = savePath;
      });
      _reviewController.forward(from: 0);
    } catch (_) {
      _recordTimer?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save recording. Try again.')),
      );
      setState(() {
        _phase = _CapturePhase.ready;
        _elapsedSeconds = 0;
      });
      _pulseController.repeat(reverse: true);
      _startTipRotation();
    } finally {
      _isStopping = false;
    }
  }

  Future<void> _cancelRecording() async {
    if (_phase != _CapturePhase.recording || _isToggling) return;
    _isToggling = true;
    try {
      await _stopRecording(toReview: false);
    } finally {
      _isToggling = false;
    }
  }

  void _retake() {
    _recordTimer?.cancel();
    setState(() {
      _phase = _CapturePhase.ready;
      _elapsedSeconds = 0;
      _recordedPath = null;
    });
    _reviewController.reset();
    _pulseController.repeat(reverse: true);
    _startTipRotation();
  }

  void _useVideo() {
    final path = _recordedPath;
    if (path == null || path.isEmpty) return;
    context.push(AppRoutes.videoPreview, extra: path);
  }

  Widget _buildCameraLayer() {
    if (_cameraError != null) {
      return _CameraStatusLayer(
        message: _cameraError!,
        onRetry: _initCamera,
      );
    }

    if (!_cameraReady || _controller == null) {
      return const _CameraStatusLayer(
        message: 'Turning camera on…',
        showSpinner: true,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showGuide = _phase != _CapturePhase.review;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(),
          if (showGuide) const _CornerFrameGuides(),
          // Stick outline stays on top of the live camera while framing/recording.
          if (showGuide) const _PlayerSilhouetteOverlay(),
          _TopBar(
            flashOn: _flashOn,
            canFlip: _cameras.length > 1 && _phase != _CapturePhase.recording,
            onClose: _phase == _CapturePhase.recording ? _cancelRecording : _close,
            closeIcon: _phase == _CapturePhase.recording
                ? Icons.close_rounded
                : Icons.close_rounded,
            closeTooltip:
                _phase == _CapturePhase.recording ? 'Cancel' : 'Close',
            onToggleFlash: _toggleFlash,
            onFlipCamera: _switchCamera,
          ),
          if (_phase == _CapturePhase.recording)
            _RecordingTimer(
              label: _timerLabel,
              remainingLabel: '${_maxRecordSeconds - _elapsedSeconds}s left',
            ),
          if (_phase == _CapturePhase.ready)
            _InstructionCard(
              tip: _tips[_tipIndex],
              fade: _tipFadeAnimation,
            ),
          if (_phase == _CapturePhase.review)
            FadeTransition(
              opacity: _reviewFadeAnimation,
              child: SlideTransition(
                position: _reviewSlideAnimation,
                child: _ReviewControls(
                  onRetake: _retake,
                  onUseVideo: _useVideo,
                ),
              ),
            ),
          if (_phase != _CapturePhase.review)
            _RecordControls(
              isRecording: _phase == _CapturePhase.recording,
              enabled: _cameraReady && !_isToggling && !_isSwitchingCamera,
              pulse: _pulseAnimation,
              onToggle: _toggleRecording,
              onCancel: _phase == _CapturePhase.recording ? _cancelRecording : null,
            ),
        ],
      ),
    );
  }
}

class _CameraStatusLayer extends StatelessWidget {
  const _CameraStatusLayer({
    required this.message,
    this.onRetry,
    this.showSpinner = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0F),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const CircularProgressIndicator(
              color: ShootIQTheme.basketballOrange,
            )
          else
            Icon(
              Icons.videocam_off_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.flashOn,
    required this.canFlip,
    required this.onClose,
    required this.closeIcon,
    required this.closeTooltip,
    required this.onToggleFlash,
    required this.onFlipCamera,
  });

  final bool flashOn;
  final bool canFlip;
  final VoidCallback onClose;
  final IconData closeIcon;
  final String closeTooltip;
  final VoidCallback onToggleFlash;
  final VoidCallback onFlipCamera;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(
          children: [
            Tooltip(
              message: closeTooltip,
              child: _OverlayIconButton(
                icon: closeIcon,
                onPressed: onClose,
              ),
            ),
            const Expanded(
              child: Text(
                'Record Your Shot',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            if (canFlip)
              _OverlayIconButton(
                icon: Icons.cameraswitch_rounded,
                onPressed: onFlipCamera,
              )
            else
              const SizedBox(width: 44),
            _OverlayIconButton(
              icon: flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              active: flashOn,
              onPressed: onToggleFlash,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: active ? ShootIQTheme.basketballOrange : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _CornerFrameGuides extends StatelessWidget {
  const _CornerFrameGuides();

  @override
  Widget build(BuildContext context) {
    const inset = 28.0;
    const length = 34.0;
    const thickness = 3.0;
    final color = ShootIQTheme.basketballOrange.withValues(alpha: 0.85);

    Widget corner({
      required Alignment alignment,
      required bool top,
      required bool left,
    }) {
      return Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(inset),
          child: SizedBox(
            width: length,
            height: length,
            child: CustomPaint(
              painter: _CornerPainter(
                color: color,
                thickness: thickness,
                top: top,
                left: left,
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          corner(alignment: Alignment.topLeft, top: true, left: true),
          corner(alignment: Alignment.topRight, top: true, left: false),
          corner(alignment: Alignment.bottomLeft, top: false, left: true),
          corner(alignment: Alignment.bottomRight, top: false, left: false),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  final Color color;
  final double thickness;
  final bool top;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final y = top ? 0.0 : size.height;
    final x = left ? 0.0 : size.width;

    canvas.drawLine(Offset(x, y), Offset(left ? size.width : 0, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, top ? size.height : 0), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.thickness != thickness ||
        oldDelegate.top != top ||
        oldDelegate.left != left;
  }
}

class _PlayerSilhouetteOverlay extends StatelessWidget {
  const _PlayerSilhouetteOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(140, 260),
                painter: _SilhouettePainter(
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Text(
                  'Keep your full body visible',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path();

    // Head
    canvas.drawCircle(Offset(w * 0.5, h * 0.1), w * 0.11, paint);

    // Torso
    path.moveTo(w * 0.5, h * 0.21);
    path.lineTo(w * 0.5, h * 0.48);

    // Arms (shooting pose)
    path.moveTo(w * 0.5, h * 0.28);
    path.lineTo(w * 0.22, h * 0.38);
    path.moveTo(w * 0.5, h * 0.28);
    path.lineTo(w * 0.78, h * 0.18);
    path.lineTo(w * 0.86, h * 0.08);

    // Ball near raised hand
    canvas.drawCircle(Offset(w * 0.9, h * 0.05), w * 0.07, paint);

    // Legs
    path.moveTo(w * 0.5, h * 0.48);
    path.lineTo(w * 0.34, h * 0.78);
    path.lineTo(w * 0.3, h * 0.96);
    path.moveTo(w * 0.5, h * 0.48);
    path.lineTo(w * 0.66, h * 0.78);
    path.lineTo(w * 0.7, h * 0.96);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    required this.tip,
    required this.fade,
  });

  final String tip;
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 150),
          child: FadeTransition(
            opacity: fade,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: ShootIQTheme.cardBackground.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: ShootIQTheme.basketballOrange
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: ShootIQTheme.basketballOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingTimer extends StatelessWidget {
  const _RecordingTimer({
    required this.label,
    required this.remainingLabel,
  });

  final String label;
  final String remainingLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey(label),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: ShootIQTheme.errorRed.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: ShootIQTheme.errorRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    remainingLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordControls extends StatelessWidget {
  const _RecordControls({
    required this.isRecording,
    required this.enabled,
    required this.pulse,
    required this.onToggle,
    this.onCancel,
  });

  final bool isRecording;
  final bool enabled;
  final Animation<double> pulse;
  final VoidCallback onToggle;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                !enabled
                    ? 'Starting camera…'
                    : isRecording
                        ? 'Tap to stop · max 15s'
                        : 'Tap to record · max 15s',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onCancel != null) ...[
                    TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  Opacity(
                    opacity: enabled ? 1 : 0.45,
                    child: ScaleTransition(
                      scale: isRecording
                          ? const AlwaysStoppedAnimation(1)
                          : pulse,
                      child: GestureDetector(
                        onTap: enabled ? onToggle : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          width: 84,
                          height: 84,
                          padding: EdgeInsets.all(isRecording ? 22 : 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ShootIQTheme.basketballOrange
                                    .withValues(
                                      alpha: isRecording ? 0.25 : 0.45,
                                    ),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              color: isRecording
                                  ? ShootIQTheme.errorRed
                                  : ShootIQTheme.basketballOrange,
                              borderRadius: BorderRadius.circular(
                                isRecording ? 8 : 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onCancel != null) const SizedBox(width: 86),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewControls extends StatelessWidget {
  const _ReviewControls({
    required this.onRetake,
    required this.onUseVideo,
  });

  final VoidCallback onRetake;
  final VoidCallback onUseVideo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ShootIQTheme.cardBackground.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Looking good?',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Retake or use this clip for AI analysis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onRetake,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ShootIQTheme.textPrimary,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Retake Video',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onUseVideo,
                        style: FilledButton.styleFrom(
                          backgroundColor: ShootIQTheme.buttonBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(
                            color: ShootIQTheme.redBorder,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Use Video',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
