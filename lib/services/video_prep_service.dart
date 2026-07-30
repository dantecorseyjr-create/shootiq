import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Validates and prepares shot videos before AI upload.
class VideoPrepService {
  VideoPrepService._();

  static const minDuration = Duration(milliseconds: 800);
  static const maxDuration = Duration(seconds: 15);
  static const minReadableBytes = 8 * 1024; // ~8 KB
  static const warnLargeBytes = 80 * 1024 * 1024; // 80 MB

  /// In-memory guard so the same prepared path is not queued twice.
  static final Set<String> _preparedPaths = {};

  static Future<VideoValidationResult> validate(File video) async {
    try {
      if (!await video.exists()) {
        return VideoValidationResult.invalid(
          'Video not found. Record or pick the clip again.',
          code: VideoValidationCode.missing,
        );
      }

      final size = await video.length();
      if (size <= 0) {
        return VideoValidationResult.invalid(
          'Video file is empty and cannot be analyzed.',
          code: VideoValidationCode.empty,
        );
      }
      if (size < minReadableBytes) {
        return VideoValidationResult.invalid(
          'Video quality looks too low or the file is incomplete. Retake with better lighting.',
          code: VideoValidationCode.poorQuality,
        );
      }

      final controller = VideoPlayerController.file(video);
      try {
        await controller.initialize();
        final duration = controller.value.duration;
        if (duration <= Duration.zero) {
          return VideoValidationResult.invalid(
            'Could not read video duration. Try another clip.',
            code: VideoValidationCode.unreadable,
          );
        }
        if (duration < minDuration) {
          return VideoValidationResult.invalid(
            'Video is too short. Record at least one full shot.',
            code: VideoValidationCode.tooShort,
          );
        }
        if (duration > maxDuration) {
          return VideoValidationResult.invalid(
            'Video is too long (max 15 seconds). Trim or retake a shorter clip.',
            code: VideoValidationCode.tooLong,
          );
        }

        final sizeHint = size >= warnLargeBytes
            ? 'Large file — upload may take longer.'
            : null;

        return VideoValidationResult.valid(
          duration: duration,
          bytes: size,
          hint: sizeHint,
        );
      } finally {
        await controller.dispose();
      }
    } catch (e) {
      return VideoValidationResult.invalid(
        'Video is not readable. Record or upload a different clip.\n$e',
        code: VideoValidationCode.unreadable,
      );
    }
  }

  /// Copies the clip into app cache for a stable upload path and dedupes repeats.
  ///
  /// Call this immediately after the user picks a video — macOS sandbox access
  /// to Downloads/Photos paths can expire before Analyze is tapped.
  ///
  /// Returns the prepared file inside the app cache.
  static Future<File> prepareForUpload(File source) async {
    final validation = await validate(source);
    if (!validation.isValid) {
      throw StateError(validation.message);
    }

    final key = await _fingerprint(source);
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);

    final dest = File(p.join(dir.path, 'shootiq_upload_$key.mp4'));

    if (await dest.exists() && await dest.length() > 0) {
      _preparedPaths.add(dest.path);
      return dest;
    }

    // Already a cached ShootIQ copy — reuse as-is.
    if (_preparedPaths.contains(source.path) &&
        source.path.contains('shootiq_upload_') &&
        await source.exists()) {
      return source;
    }

    await _copyIntoCache(source, dest);
    _preparedPaths.add(dest.path);
    return dest;
  }

  /// Reliable copy for sandboxed macOS picks (Downloads / Photos).
  static Future<void> _copyIntoCache(File source, File dest) async {
    try {
      if (!await source.exists()) {
        throw StateError(
          'Video is no longer accessible. Pick the clip again from your library.',
        );
      }

      // Ensure parent exists (getTemporaryDirectory can return a missing folder
      // inside the macOS app container on first launch).
      await dest.parent.create(recursive: true);

      try {
        await source.copy(dest.path);
      } on PathNotFoundException {
        // Fall back to byte copy when File.copy cannot resolve the dest tree.
        final bytes = await source.readAsBytes();
        if (bytes.isEmpty) {
          throw StateError('Video file is empty and cannot be analyzed.');
        }
        await dest.writeAsBytes(bytes, flush: true);
      } on FileSystemException catch (e) {
        // Sandbox / permission edge cases — try raw bytes.
        // ignore: avoid_print
        print('VideoPrepService.copy fallback after: $e');
        final bytes = await source.readAsBytes();
        if (bytes.isEmpty) {
          throw StateError('Video file is empty and cannot be analyzed.');
        }
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(bytes, flush: true);
      }

      if (!await dest.exists() || await dest.length() <= 0) {
        throw StateError(
          'Could not save the video into app cache. Free some disk space and try again.',
        );
      }
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError(
        'Could not prepare the video for analysis. Pick the clip again.\n$e',
      );
    }
  }

  static Future<String> _fingerprint(File file) async {
    final stat = await file.stat();
    final base = p.basenameWithoutExtension(file.path)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final safe = base.isEmpty ? 'shot' : base;
    return '${stat.size}_${stat.modified.millisecondsSinceEpoch}_$safe';
  }

  static void clearPreparedCacheMark(String path) {
    _preparedPaths.remove(path);
  }
}

enum VideoValidationCode {
  ok,
  missing,
  empty,
  tooShort,
  tooLong,
  poorQuality,
  unreadable,
}

class VideoValidationResult {
  const VideoValidationResult._({
    required this.isValid,
    required this.message,
    required this.code,
    this.duration,
    this.bytes,
    this.hint,
  });

  factory VideoValidationResult.valid({
    required Duration duration,
    required int bytes,
    String? hint,
  }) {
    return VideoValidationResult._(
      isValid: true,
      message: 'Video ready',
      code: VideoValidationCode.ok,
      duration: duration,
      bytes: bytes,
      hint: hint,
    );
  }

  factory VideoValidationResult.invalid(
    String message, {
    required VideoValidationCode code,
  }) {
    return VideoValidationResult._(
      isValid: false,
      message: message,
      code: code,
    );
  }

  final bool isValid;
  final String message;
  final VideoValidationCode code;
  final Duration? duration;
  final int? bytes;
  final String? hint;
}
