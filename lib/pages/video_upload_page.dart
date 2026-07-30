import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/video_prep_service.dart';
import 'package:shootiq/widgets/shot_video_player.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Pick or record a shot video, then upload and continue to processing.
class VideoUploadPage extends StatefulWidget {
  const VideoUploadPage({super.key});

  @override
  State<VideoUploadPage> createState() => _VideoUploadPageState();
}

class _VideoUploadPageState extends State<VideoUploadPage>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();

  File? _selectedVideo;
  String? _thumbnailPath;
  bool _isUploading = false;
  bool _isGeneratingThumb = false;
  String? _errorMessage;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    setState(() => _errorMessage = null);

    try {
      // ignore: avoid_print
      print('Opening video picker source=$source');
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: VideoPrepService.maxDuration,
      );
      if (picked == null) {
        // ignore: avoid_print
        print('Video picker cancelled or blocked (null result)');
        return;
      }
      await _setSelectedVideo(File(picked.path));
    } catch (e) {
      // ignore: avoid_print
      print('Video picker error: $e');
      // Camera may be unavailable on desktop — fall back to library.
      if (source == ImageSource.camera) {
        try {
          final picked = await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: VideoPrepService.maxDuration,
          );
          if (picked == null) return;
          await _setSelectedVideo(File(picked.path));
          return;
        } catch (fallbackError) {
          // ignore: avoid_print
          print('Gallery fallback error: $fallbackError');
        }
      }
      setState(() {
        _errorMessage =
            'Could not open the video picker. On macOS, quit and relaunch the app after entitlements update.';
      });
    }
  }

  Future<void> _setSelectedVideo(File video) async {
    // ignore: avoid_print
    print('Picked video path: ${video.path}');

    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _thumbnailPath = null;
      _isGeneratingThumb = true;
    });

    try {
      // Copy into app cache immediately — macOS sandbox can revoke Downloads
      // access before the user taps Analyze.
      final prepared = await VideoPrepService.prepareForUpload(video);
      // ignore: avoid_print
      print('Cached upload path: ${prepared.path}');
      if (!mounted) return;
      setState(() {
        _selectedVideo = prepared;
        _isUploading = false;
      });
      // Thumbnail is cosmetic only — never block Analyze if the plugin hangs.
      // ignore: unawaited_futures
      _generateThumbnail(prepared);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedVideo = null;
        _thumbnailPath = null;
        _isUploading = false;
        _isGeneratingThumb = false;
        _errorMessage = e is StateError
            ? e.message
            : 'Could not open that video. Pick it again.\n$e';
      });
    }
  }

  Future<void> _generateThumbnail(File video) async {
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
      print('Stored thumbnail path: $thumbPath');
    } catch (e) {
      // ignore: avoid_print
      print('Thumbnail generation error: $e');
    }

    if (!mounted) return;
    // Ignore stale thumbs if the user picked another clip.
    if (_selectedVideo?.path != video.path) return;
    setState(() {
      _thumbnailPath = thumbPath;
      _isGeneratingThumb = false;
    });
  }

  Future<void> _analyzeShot() async {
    final file = _selectedVideo;
    if (file == null || _isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final prepared = await VideoPrepService.prepareForUpload(file);
      // ignore: avoid_print
      print(
        'Analyze Shot → Processing video=${prepared.path} thumb=$_thumbnailPath',
      );
      if (!mounted) return;
      PendingAnalysisStore.setVideo(prepared);
      // Prefer preview → processing when coming from record; upload can go direct.
      context.push(AppRoutes.processing, extra: prepared);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is StateError
            ? e.message
            : 'Could not start analysis. $e';
      });
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedVideo;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.analyze);
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
                        'Upload Shot',
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ShootIQTheme.surfaceElevated,
                              ShootIQTheme.cardBackground,
                              ShootIQTheme.basketballOrange
                                  .withValues(alpha: 0.14),
                            ],
                          ),
                          border: Border.all(
                            color: ShootIQTheme.cardBorder,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ShootIQTheme.basketballOrange
                                    .withValues(alpha: 0.16),
                              ),
                              child: const Icon(
                                Icons.cloud_upload_rounded,
                                color: ShootIQTheme.basketballOrange,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Upload Your Shot',
                              style: TextStyle(
                                color: ShootIQTheme.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Record a new clip or choose an existing shooting video.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ShootIQTheme.textSecondary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: _SourceButton(
                                    icon: Icons.videocam_rounded,
                                    label: 'Record Video',
                                    onPressed: _isUploading
                                        ? null
                                        : () =>
                                            _pickVideo(ImageSource.camera),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _SourceButton(
                                    icon: Icons.video_library_outlined,
                                    label: 'Choose From Library',
                                    onPressed: _isUploading
                                        ? null
                                        : () =>
                                            _pickVideo(ImageSource.gallery),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (selected != null)
                        _SelectedVideoPreview(
                          file: selected,
                          thumbnailPath: _thumbnailPath,
                          isGeneratingThumb: _isGeneratingThumb,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: ShootIQTheme.cardBackground,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: ShootIQTheme.cardBorder,
                            ),
                          ),
                          child: const Text(
                            'No video selected yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ShootIQTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ShootIQTheme.errorRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: ShootIQTheme.errorRed,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: selected == null || _isUploading
                              ? null
                              : _analyzeShot,
                          style: FilledButton.styleFrom(
                            backgroundColor: ShootIQTheme.buttonBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: ShootIQTheme.buttonBlue
                                .withValues(alpha: 0.4),
                            side: const BorderSide(
                              color: ShootIQTheme.redBorder,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Analyze Shot'),
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

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: ShootIQTheme.textPrimary,
        side: BorderSide(color: ShootIQTheme.surfaceElevated),
        backgroundColor: ShootIQTheme.surfaceElevated.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        children: [
          Icon(icon, color: ShootIQTheme.basketballOrange, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedVideoPreview extends StatefulWidget {
  const _SelectedVideoPreview({
    required this.file,
    required this.thumbnailPath,
    required this.isGeneratingThumb,
  });

  final File file;
  final String? thumbnailPath;
  final bool isGeneratingThumb;

  @override
  State<_SelectedVideoPreview> createState() => _SelectedVideoPreviewState();
}

class _SelectedVideoPreviewState extends State<_SelectedVideoPreview> {
  /// Desktop fallback when [video_thumbnail] is unavailable.
  VideoPlayerController? _frameController;
  bool _loadingFrame = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadDesktopFrame();
  }

  @override
  void didUpdateWidget(covariant _SelectedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.thumbnailPath != widget.thumbnailPath ||
        oldWidget.isGeneratingThumb != widget.isGeneratingThumb) {
      _maybeLoadDesktopFrame();
    }
  }

  @override
  void dispose() {
    _frameController?.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadDesktopFrame() async {
    final hasThumb = widget.thumbnailPath != null &&
        File(widget.thumbnailPath!).existsSync();
    if (widget.isGeneratingThumb || hasThumb) {
      await _frameController?.dispose();
      _frameController = null;
      return;
    }

    setState(() => _loadingFrame = true);
    try {
      final controller = VideoPlayerController.file(widget.file);
      await controller.initialize();
      await controller.pause();
      await controller.seekTo(const Duration(milliseconds: 500));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _frameController?.dispose();
      setState(() {
        _frameController = controller;
        _loadingFrame = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Desktop frame preview error: $e');
      if (!mounted) return;
      setState(() => _loadingFrame = false);
    }
  }

  Widget _buildThumbnailImage() {
    final path = widget.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    final frame = _frameController;
    if (frame != null && frame.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: frame.value.size.width,
          height: frame.value.size.height,
          child: VideoPlayer(frame),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShootIQTheme.surfaceElevated,
            ShootIQTheme.basketballOrange.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: (widget.isGeneratingThumb || _loadingFrame)
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: ShootIQTheme.basketballOrange,
                ),
              )
            : const Icon(
                Icons.videocam_rounded,
                color: Colors.white54,
                size: 40,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.file.path);

    return Container(
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: InkWell(
              onTap: () => showShotVideoPreview(context, widget.file),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnailImage(),
                  Container(color: Colors.black.withValues(alpha: 0.22)),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
