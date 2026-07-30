import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';

/// Friendly error types with consistent copy across the app.
enum AppErrorType {
  cameraPermission,
  uploadFailed,
  aiUnavailable,
  noInternet,
  invalidVideo,
  videoTooLong,
  poorVideoQuality,
  analysisTimeout,
  generic,
}

class AppErrorInfo {
  const AppErrorInfo({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  static AppErrorInfo forType(AppErrorType type) {
    return switch (type) {
      AppErrorType.cameraPermission => const AppErrorInfo(
          title: 'Camera access needed',
          message:
              'ShootIQ needs camera permission to record your shot. '
              'Enable it in Settings, then try again.',
        ),
      AppErrorType.uploadFailed => const AppErrorInfo(
          title: 'Upload failed',
          message:
              'We could not upload your video. Check your connection and try again.',
        ),
      AppErrorType.aiUnavailable => const AppErrorInfo(
          title: 'AI server unavailable',
          message:
              'Our analysis engine is temporarily unavailable. '
              'Your video is safe — retry in a moment.',
        ),
      AppErrorType.noInternet => const AppErrorInfo(
          title: 'No internet connection',
          message:
              'ShootIQ needs a connection to analyze your shot. '
              'Reconnect and retry.',
        ),
      AppErrorType.invalidVideo => const AppErrorInfo(
          title: 'Invalid video',
          message:
              'This file could not be read as a valid basketball shot clip. '
              'Try recording or picking another video.',
        ),
      AppErrorType.videoTooLong => const AppErrorInfo(
          title: 'Video too long',
          message:
              'Keep recordings to 15 seconds or less for the best AI analysis.',
        ),
      AppErrorType.poorVideoQuality => const AppErrorInfo(
          title: 'Poor video quality',
          message:
              'Lighting or resolution looks too low. Retake with a steady side '
              'angle and your full body in frame.',
        ),
      AppErrorType.analysisTimeout => const AppErrorInfo(
          title: 'Analysis timed out',
          message:
              'The analysis took too long. Try a shorter clip or retry — '
              'shorter side-angle videos work best.',
        ),
      AppErrorType.generic => const AppErrorInfo(
          title: 'Something went wrong',
          message: 'We hit an unexpected issue. Retry, or go back and try again.',
        ),
    };
  }

  /// Map raw exception text into a friendly error type.
  static AppErrorType classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission') || text.contains('camera')) {
      return AppErrorType.cameraPermission;
    }
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup') ||
        text.contains('connection') ||
        text.contains('offline')) {
      return AppErrorType.noInternet;
    }
    if (text.contains('timeout') || text.contains('timed out')) {
      return AppErrorType.analysisTimeout;
    }
    if (text.contains('upload')) {
      return AppErrorType.uploadFailed;
    }
    if (text.contains('too long') ||
        text.contains('max 15') ||
        text.contains('15 second')) {
      return AppErrorType.videoTooLong;
    }
    if (text.contains('quality') ||
        text.contains('lighting') ||
        text.contains('too low')) {
      return AppErrorType.poorVideoQuality;
    }
    if (text.contains('invalid') ||
        text.contains('0 bytes') ||
        text.contains('empty') ||
        text.contains('format') ||
        text.contains('codec') ||
        text.contains('not readable') ||
        text.contains('not found')) {
      return AppErrorType.invalidVideo;
    }
    if (text.contains('503') ||
        text.contains('502') ||
        text.contains('500') ||
        text.contains('unavailable') ||
        text.contains('server')) {
      return AppErrorType.aiUnavailable;
    }
    return AppErrorType.generic;
  }
}

/// Full-page / inline error with Retry + Return actions.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.type,
    this.detail,
    this.onRetry,
    this.onReturn,
    this.returnLabel = 'Go Back',
  });

  final AppErrorType type;
  final String? detail;
  final VoidCallback? onRetry;
  final VoidCallback? onReturn;
  final String returnLabel;

  @override
  Widget build(BuildContext context) {
    final info = AppErrorInfo.forType(type);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: ShootIQTheme.errorRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 34,
                color: ShootIQTheme.errorRed,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              info.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              info.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (detail != null && detail!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ShootIQTheme.surfaceElevated,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (onRetry != null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: ShootIQTheme.buttonBlue,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (onReturn != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: onReturn,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ShootIQTheme.textPrimary,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(returnLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
