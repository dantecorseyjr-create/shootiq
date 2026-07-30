import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class ShotCapturePage extends StatefulWidget {
  const ShotCapturePage({super.key, this.openGalleryOnLoad = false});

  final bool openGalleryOnLoad;

  @override
  State<ShotCapturePage> createState() => _ShotCapturePageState();
}

class _ShotCapturePageState extends State<ShotCapturePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  final _picker = ImagePicker();
  bool _isRecording = false;
  bool _isBusy = false;
  String? _selectedVideoName;

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
    _fadeController.forward();

    if (widget.openGalleryOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _uploadVideo();
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _goToProcessing(File video) {
    if (!mounted) return;
    PendingAnalysisStore.setVideo(video);
    context.push(AppRoutes.processing, extra: video);
  }

  Future<void> _toggleRecording() async {
    if (_isBusy) return;

    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isBusy = false;
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _isRecording = true;
    });

    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isBusy = false;
        _selectedVideoName = video?.name;
      });
      if (video != null) {
        _goToProcessing(File(video.path));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera unavailable. Try uploading a video.')),
      );
    }
  }

  Future<void> _uploadVideo() async {
    if (_isBusy || _isRecording) return;
    setState(() => _isBusy = true);

    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _selectedVideoName = video?.name;
      });
      if (video != null) {
        _goToProcessing(File(video.path));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  PremiumSpacing.horizontal,
                  8,
                  PremiumSpacing.horizontal,
                  0,
                ),
                child: CustomBackButton(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    PremiumSpacing.horizontal,
                    16,
                    PremiumSpacing.horizontal,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _TitleSection(),
                      const SizedBox(height: PremiumSpacing.section),
                      _CameraPreviewArea(isRecording: _isRecording),
                      const SizedBox(height: 28),
                      _RecordButton(
                        isRecording: _isRecording,
                        isBusy: _isBusy && !_isRecording,
                        onPressed: _toggleRecording,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: (_isBusy || _isRecording) ? null : _uploadVideo,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PremiumColors.accentOrange,
                            side: const BorderSide(
                              color: PremiumColors.accentOrange,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Upload Video Instead'),
                        ),
                      ),
                      if (_selectedVideoName != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Selected: $_selectedVideoName',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: PremiumColors.subtitle,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const _TipsCard(),
                      const SizedBox(height: 20),
                      const OnboardingFootnote(
                        text:
                            'ShotIQ AI analyzes your movement frame by frame.',
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

class _TitleSection extends StatelessWidget {
  const _TitleSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Capture Your Shot',
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: const Text(
            'Position your phone correctly so ShotIQ can analyze your shooting mechanics.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: PremiumColors.subtitle,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraPreviewArea extends StatelessWidget {
  const _CameraPreviewArea({required this.isRecording});

  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isRecording
              ? PremiumColors.accentOrange
              : PremiumColors.cardBorder,
          width: isRecording ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF1F2937)),
          CustomPaint(painter: _GuideOverlayPainter()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRecording ? Icons.fiber_manual_record : Icons.videocam_outlined,
                  color: isRecording
                      ? PremiumColors.accentOrange
                      : Colors.white.withValues(alpha: 0.85),
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  isRecording ? 'Recording...' : 'Camera Preview',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Text(
              'Keep your full body in frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (isRecording)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: PremiumColors.accentOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'REC',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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

class _GuideOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final standingArea = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.18,
        size.width * 0.44,
        size.height * 0.62,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(standingArea, paint);

    final shootingZone = Path()
      ..moveTo(size.width * 0.38, size.height * 0.22)
      ..lineTo(size.width * 0.62, size.height * 0.22)
      ..lineTo(size.width * 0.58, size.height * 0.42)
      ..lineTo(size.width * 0.42, size.height * 0.42)
      ..close();
    canvas.drawPath(shootingZone, paint);

    final dashed = Paint()
      ..color = PremiumColors.accentOrange.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.78),
      Offset(size.width * 0.82, size.height * 0.78),
      dashed,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.isRecording,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isRecording;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isBusy ? null : onPressed,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PremiumColors.accentOrange,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: PremiumColors.accentOrange.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                isRecording ? Icons.stop_rounded : Icons.camera_alt_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isRecording ? 'Stop Recording' : 'Record Shot',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PremiumColors.title,
          ),
        ),
      ],
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  static const _tips = [
    'Record from the side angle',
    'Keep your full body visible',
    'Make sure lighting is good',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For Best Results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PremiumColors.title,
            ),
          ),
          const SizedBox(height: 12),
          for (final tip in _tips) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: PremiumColors.checkGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: PremiumColors.subtitle,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
