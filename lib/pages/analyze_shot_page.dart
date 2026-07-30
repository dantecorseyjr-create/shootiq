import 'dart:io';
import 'package:shootiq/config/theme.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/services/video_prep_service.dart';
import 'package:shootiq/widgets/analyze_shot/analyze_shot_widgets.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';
import 'package:shootiq/widgets/shot_upload/shot_upload_widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class AnalyzeShotPage extends StatefulWidget {
  const AnalyzeShotPage({super.key});

  @override
  State<AnalyzeShotPage> createState() => _AnalyzeShotPageState();
}

class _AnalyzeShotPageState extends State<AnalyzeShotPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  File? _selectedVideo;
  String? _thumbnailPath;
  bool _isBusy = false;
  bool _isGeneratingThumb = false;
  VideoPlayerController? _frameController;

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
  }

  @override
  void dispose() {
    _frameController?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _setSelectedVideo(File video) async {
    setState(() {
      _isBusy = true;
      _isGeneratingThumb = true;
      _thumbnailPath = null;
    });

    await _frameController?.dispose();
    _frameController = null;

    // ignore: avoid_print
    print('Selected video: ${video.path}');

    try {
      // Cache immediately while the picker path is still accessible (macOS).
      final prepared = await VideoPrepService.prepareForUpload(video);
      if (!mounted) return;
      setState(() {
        _selectedVideo = prepared;
        _isBusy = false;
        _isGeneratingThumb = false;
      });
      // ignore: unawaited_futures
      _generatePreview(prepared);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedVideo = null;
        _isBusy = false;
        _isGeneratingThumb = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Could not open that video. Pick it again.',
          ),
        ),
      );
    }
  }

  Future<void> _generatePreview(File video) async {
    if (!mounted) return;
    setState(() => _isGeneratingThumb = true);

    String? thumbPath;
    try {
      final tempDir = await getTemporaryDirectory();
      thumbPath = await VideoThumbnail.thumbnailFile(
        video: video.path,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 75,
        timeMs: 500,
      ).timeout(const Duration(seconds: 4));
      // ignore: avoid_print
      print('Thumbnail path: $thumbPath');
    } catch (e) {
      // ignore: avoid_print
      print('Thumbnail generation error: $e');
    }

    // macOS: video_thumbnail unsupported — show paused first frame.
    if (thumbPath == null ||
        thumbPath.isEmpty ||
        !File(thumbPath).existsSync()) {
      try {
        final controller = VideoPlayerController.file(video);
        await controller.initialize().timeout(const Duration(seconds: 6));
        await controller.pause();
        await controller.seekTo(const Duration(milliseconds: 500));
        if (mounted && _selectedVideo?.path == video.path) {
          await _frameController?.dispose();
          _frameController = controller;
        } else {
          await controller.dispose();
        }
      } catch (e) {
        // ignore: avoid_print
        print('Frame preview error: $e');
      }
    }

    if (!mounted) return;
    if (_selectedVideo?.path != video.path) return;
    setState(() {
      _thumbnailPath = thumbPath;
      _isGeneratingThumb = false;
    });
  }

  Future<void> _recordMyShot() async {
    if (_isBusy) return;
    final allowed = await SubscriptionService.checkAnalysisAccess();
    if (!mounted) return;
    if (!allowed) {
      await SubscriptionService.openAnalysisOrPaywall(
        context,
        destination: AppRoutes.analyzeShot,
      );
      return;
    }

    final picker = ImagePicker();

    try {
      final video = await picker.pickVideo(source: ImageSource.camera);
      if (!mounted || video == null) return;
      await _setSelectedVideo(File(video.path));
    } catch (_) {
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || video == null) return;
      await _setSelectedVideo(File(video.path));
    }
  }

  Future<void> _uploadFromLibrary() async {
    if (_isBusy) return;
    final allowed = await SubscriptionService.checkAnalysisAccess();
    if (!mounted) return;
    if (!allowed) {
      await SubscriptionService.openAnalysisOrPaywall(
        context,
        destination: AppRoutes.analyzeShot,
      );
      return;
    }

    final picker = ImagePicker();

    try {
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return;
      if (video == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No video selected. Try again.')),
        );
        return;
      }
      await _setSelectedVideo(File(video.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open library: $e')),
      );
    }
  }

  void _analyzeShot() {
    final file = _selectedVideo;
    if (file == null || _isBusy) return;
    // ignore: avoid_print
    print(
      'Analyze Shot → Processing with ${file.path} thumb=$_thumbnailPath',
    );
    PendingAnalysisStore.setVideo(file);
    // Use push so the File extra is not dropped by redirect/replace.
    context.push(AppRoutes.processing, extra: file);
  }

  void _clearSelection() {
    _frameController?.dispose();
    _frameController = null;
    setState(() {
      _selectedVideo = null;
      _thumbnailPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedVideo;

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
                      const AnalyzeShotHero(),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const _TitleSection(),
                      const SizedBox(height: PremiumSpacing.section),
                      if (selected == null) ...[
                        ShotSourceCard(
                          emoji: '📹',
                          title: 'Record My Shot',
                          description:
                              'Use your camera to capture your shooting motion.',
                          buttonLabel: 'Record My Shot',
                          isSelected: false,
                          onSelect: _recordMyShot,
                          onAction: () {},
                        ),
                        const SizedBox(height: PremiumSpacing.goalCardGap),
                        ShotSourceCard(
                          emoji: '🎞️',
                          title: 'Upload From Library',
                          description:
                              'Choose an existing shooting video from your phone.',
                          buttonLabel: 'Upload From Library',
                          isSelected: false,
                          onSelect: _uploadFromLibrary,
                          onAction: () {},
                        ),
                      ] else
                        _VideoPreviewCard(
                          video: selected,
                          thumbnailPath: _thumbnailPath,
                          frameController: _frameController,
                          isGeneratingThumb: _isGeneratingThumb,
                          onAnalyze: _analyzeShot,
                          onChangeVideo: _clearSelection,
                        ),
                      const SizedBox(height: 24),
                      const OnboardingFootnote(
                        text: 'Your video will be analyzed by ShotIQ AI.',
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

class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({
    required this.video,
    required this.thumbnailPath,
    required this.frameController,
    required this.isGeneratingThumb,
    required this.onAnalyze,
    required this.onChangeVideo,
  });

  final File video;
  final String? thumbnailPath;
  final VideoPlayerController? frameController;
  final bool isGeneratingThumb;
  final VoidCallback onAnalyze;
  final VoidCallback onChangeVideo;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(video.path);
    final hasThumb =
        thumbnailPath != null && File(thumbnailPath!).existsSync();
    final hasFrame =
        frameController != null && frameController!.value.isInitialized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasThumb)
                  Image.file(File(thumbnailPath!), fit: BoxFit.cover)
                else if (hasFrame)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: frameController!.value.size.width,
                      height: frameController!.value.size.height,
                      child: VideoPlayer(frameController!),
                    ),
                  )
                else
                  Container(
                    color: PremiumColors.cardBackground,
                    child: Center(
                      child: isGeneratingThumb
                          ? const CircularProgressIndicator(
                              color: PremiumColors.accentOrange,
                            )
                          : const Icon(
                              Icons.videocam_rounded,
                              size: 48,
                              color: PremiumColors.subtitle,
                            ),
                    ),
                  ),
                Container(color: Colors.black.withValues(alpha: 0.25)),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 68,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: PremiumColors.title,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: onAnalyze,
            style: FilledButton.styleFrom(
              backgroundColor: ShootIQTheme.buttonBlue,
              foregroundColor: Colors.white,
              side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Analyze Shot'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onChangeVideo,
          child: const Text('Choose a different video'),
        ),
      ],
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
          'Analyze Your Shot',
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
            'Upload or record your shooting video and let AI analyze your form, release, and mechanics.',
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
