import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/video_prep_service.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();
  XFile? _selectedVideo;
  bool _isUploading = false;
  String? _errorMessage;

  Future<void> _pickVideo() async {
    setState(() => _errorMessage = null);
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: VideoPrepService.maxDuration,
    );

    if (video != null) {
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  Future<void> _uploadVideo() async {
    final selected = _selectedVideo;
    if (selected == null || _isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final prepared = await VideoPrepService.prepareForUpload(File(selected.path));
      if (!mounted) return;
      PendingAnalysisStore.setVideo(prepared);
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

  String _formatFileSize(String path) {
    final bytes = File(path).lengthSync();
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Video')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UploadDropZone(
              selectedVideo: _selectedVideo,
              onPick: _pickVideo,
            ),
            if (_selectedVideo != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ShootIQTheme.basketballOrange
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.movie,
                          color: ShootIQTheme.basketballOrange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedVideo!.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatFileSize(_selectedVideo!.path),
                              style: const TextStyle(
                                color: ShootIQTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedVideo = null),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: ShootIQTheme.errorRed),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed:
                  _selectedVideo == null || _isUploading ? null : _uploadVideo,
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_isUploading ? 'Starting…' : 'Upload & Analyze'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickVideo,
              icon: const Icon(Icons.folder_open),
              label: Text(
                _selectedVideo == null
                    ? 'Choose Video'
                    : 'Choose Different Video',
              ),
            ),
            const SizedBox(height: 32),
            const _UploadTips(),
          ],
        ),
      ),
    );
  }
}

class _UploadDropZone extends StatelessWidget {
  const _UploadDropZone({
    required this.selectedVideo,
    required this.onPick,
  });

  final XFile? selectedVideo;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: ShootIQTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ShootIQTheme.basketballOrange.withValues(alpha: 0.4),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selectedVideo != null
                  ? Icons.check_circle
                  : Icons.cloud_upload_outlined,
              size: 56,
              color: ShootIQTheme.basketballOrange,
            ),
            const SizedBox(height: 16),
            Text(
              selectedVideo != null
                  ? 'Video ready — tap Analyze'
                  : 'Tap to choose a shooting video',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MP4 or MOV · max 15 seconds',
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadTips extends StatelessWidget {
  const _UploadTips();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tips for best analysis',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          SizedBox(height: 10),
          Text('• Film from the side at chest height'),
          SizedBox(height: 4),
          Text('• Keep your full body in frame'),
          SizedBox(height: 4),
          Text('• One clean jumper is enough'),
        ],
      ),
    );
  }
}
