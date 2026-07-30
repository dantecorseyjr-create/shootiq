import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';

class RecordVideoPage extends StatefulWidget {
  const RecordVideoPage({super.key});

  @override
  State<RecordVideoPage> createState() => _RecordVideoPageState();
}

class _RecordVideoPageState extends State<RecordVideoPage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  String? _errorMessage;
  String? _lastRecordingPath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(
          () => _errorMessage =
              'No cameras found. Allow camera access in System Settings → Privacy & Security → Camera.',
        );
        return;
      }

      final selected = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        ),
      );

      CameraController? controller;
      Object? lastError;
      for (final withAudio in const [true, false]) {
        try {
          controller = CameraController(
            selected,
            ResolutionPreset.high,
            enableAudio: withAudio,
          );
          await controller.initialize();
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          await controller?.dispose();
          controller = null;
        }
      }

      if (controller == null || !controller.value.isInitialized) {
        throw lastError ?? Exception('Camera failed to initialize');
      }

      _controller = controller;
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Camera unavailable. Check System Settings → Privacy & Security → Camera.\n\n$e',
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      final file = await _controller!.stopVideoRecording();
      final dir = await getApplicationDocumentsDirectory();
      final savePath = p.join(
        dir.path,
        'shootiq_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await File(file.path).copy(savePath);

      setState(() {
        _isRecording = false;
        _lastRecordingPath = savePath;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording saved!')),
        );
      }
    } else {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Shot')),
      body: Column(
        children: [
          Expanded(child: _buildPreview()),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off, size: 64, color: ShootIQTheme.textSecondary),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ShootIQTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: ShootIQTheme.basketballOrange),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        const IgnorePointer(child: _StickOutlineGuide()),
        if (_isRecording)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: ShootIQTheme.errorRed.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                    SizedBox(width: 8),
                    Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Position yourself at the free-throw line and record your shot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isInitialized ? _toggleRecording : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isRecording
                          ? ShootIQTheme.errorRed
                          : ShootIQTheme.basketballOrange,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isRecording ? 28 : 56,
                      height: _isRecording ? 28 : 56,
                      decoration: BoxDecoration(
                        color: _isRecording
                            ? ShootIQTheme.errorRed
                            : ShootIQTheme.basketballOrange,
                        borderRadius: BorderRadius.circular(_isRecording ? 6 : 28),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_lastRecordingPath != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.results),
              icon: const Icon(Icons.analytics),
              label: const Text('View Analysis'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StickOutlineGuide extends StatelessWidget {
  const _StickOutlineGuide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: CustomPaint(
          size: const Size(140, 260),
          painter: _StickOutlinePainter(
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
      ),
    );
  }
}

class _StickOutlinePainter extends CustomPainter {
  const _StickOutlinePainter({required this.color});

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

    canvas.drawCircle(Offset(w * 0.5, h * 0.1), w * 0.11, paint);

    path.moveTo(w * 0.5, h * 0.21);
    path.lineTo(w * 0.5, h * 0.48);

    path.moveTo(w * 0.5, h * 0.28);
    path.lineTo(w * 0.22, h * 0.38);
    path.moveTo(w * 0.5, h * 0.28);
    path.lineTo(w * 0.78, h * 0.18);
    path.lineTo(w * 0.86, h * 0.08);

    canvas.drawCircle(Offset(w * 0.9, h * 0.05), w * 0.07, paint);

    path.moveTo(w * 0.5, h * 0.48);
    path.lineTo(w * 0.34, h * 0.78);
    path.lineTo(w * 0.3, h * 0.96);
    path.moveTo(w * 0.5, h * 0.48);
    path.lineTo(w * 0.66, h * 0.78);
    path.lineTo(w * 0.7, h * 0.96);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StickOutlinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
