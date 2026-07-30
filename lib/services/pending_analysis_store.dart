import 'dart:io';

/// Holds the prepared local video path across paywall / go_router redirects.
///
/// GoRouter `extra` is dropped when `/processing` is redirected to Premium.
/// Stashing the path keeps Analyze from falling into the empty demo path.
class PendingAnalysisStore {
  PendingAnalysisStore._();

  static String? _videoPath;

  static String? get videoPath => _videoPath;

  static File? get videoFile {
    final path = _videoPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  static void setVideo(File file) {
    _videoPath = file.path;
  }

  static void setPath(String path) {
    _videoPath = path;
  }

  static void clear() {
    _videoPath = null;
  }

  /// Prefer [extra] when it is a live [File]; otherwise use the stashed path.
  static File? resolveVideo(Object? extra) {
    if (extra is File && extra.existsSync()) {
      _videoPath = extra.path;
      return extra;
    }
    return videoFile;
  }
}
