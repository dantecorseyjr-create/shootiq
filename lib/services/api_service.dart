import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shootiq/config/api_config.dart';
import 'package:shootiq/services/coaching_report_service.dart';
import 'package:shootiq/services/personal_baseline_service.dart';
import 'package:shootiq/services/profile_service.dart';

class ApiService {
  ApiService._();

  /// Prevents duplicate in-flight analyze requests for the same local path.
  static final Map<String, Future<Map<String, dynamic>>> _inFlight = {};

  static Future<Map<String, dynamic>?> _personalBaselinePayload() {
    return PersonalBaselineService.baselineForAnalyzeRequest();
  }

  /// FastAPI base URL from [ApiConfig] (`--dart-define=API_URL=...`).
  static String get baseUrl => ApiConfig.baseUrl;

  /// Host used when rewriting FastAPI media URLs for playback.
  static String get mediaHost => ApiConfig.host;

  /// True for on-device Documents/Caches media (history reopen).
  /// Must not match FastAPI `processed_videos/` paths (even on macOS where they exist).
  static bool _isOnDeviceMediaPath(String path) {
    if (path.startsWith('file://')) return true;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    final lower = path.replaceAll('\\', '/').toLowerCase();
    if (lower.contains('/processed_videos/') ||
        lower.contains('/shootiq_ai/uploads/')) {
      return false;
    }
    if (lower.contains('/shootiq_media/')) return true;
    if (lower.contains('/library/containers/') && lower.contains('/data/')) {
      return true;
    }
    if (lower.contains('/data/data/') || lower.contains('/data/user/')) {
      return true;
    }
    if (lower.contains('/documents/') ||
        lower.contains('/application support/') ||
        lower.contains('/library/caches/')) {
      return true;
    }
    return false;
  }

  /// Resolve a FastAPI media path into a playable URL.
  /// Prefers `/processed/...` or `/media/...` routes over absolute disk paths.
  /// Local history files are returned unchanged (never rewritten to the AI host).
  static String? resolveMediaUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      final uri = Uri.parse(pathOrUrl);
      // FastAPI may advertise 0.0.0.0 / localhost — rewrite for this device.
      if (uri.host == '0.0.0.0' ||
          uri.host == '127.0.0.1' ||
          uri.host == 'localhost' ||
          uri.host == mediaHost) {
        return uri.replace(host: mediaHost).toString();
      }
      return pathOrUrl;
    }
    if (_isOnDeviceMediaPath(pathOrUrl)) {
      return pathOrUrl;
    }
    // API route paths
    if (pathOrUrl.startsWith('/processed/') ||
        pathOrUrl.startsWith('/media/') ||
        pathOrUrl.startsWith('/media-file/')) {
      return '$baseUrl$pathOrUrl';
    }
    // Bare filename from processed_videos/
    if (!pathOrUrl.contains('/') && pathOrUrl.endsWith('.mp4')) {
      return '$baseUrl/processed/$pathOrUrl';
    }
    // Absolute server disk path → use basename on /processed/
    final name = pathOrUrl.split('/').last;
    if (name.endsWith('.mp4') || name.endsWith('.mov')) {
      return '$baseUrl/processed/$name';
    }
    if (pathOrUrl.startsWith('/')) {
      return '$baseUrl$pathOrUrl';
    }
    return '$baseUrl/processed/$pathOrUrl';
  }

  /// Ask the AI server to delete temporary upload/processed copies for [tempMediaId].
  ///
  /// Videos are only held on the AI server during analysis; after results are
  /// saved on-device the server copy should be removed.
  static Future<void> cleanupTempMedia(String tempMediaId) async {
    if (tempMediaId.isEmpty) return;
    try {
      final uri = Uri.parse('$baseUrl/cleanup/$tempMediaId');
      final response = await http
          .delete(uri, headers: {'X-API-Key': ApiConfig.apiKey})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // ignore: avoid_print
        print('ApiService cleaned temp media $tempMediaId via $baseUrl');
        return;
      }
    } catch (e) {
      // ignore: avoid_print
      print('ApiService cleanup via $baseUrl failed: $e');
    }
  }

  /// True when a processed media URL is available (skeleton overlay, etc.).
  static Future<bool> isMediaReady(String? url) async {
    if (url == null || url.isEmpty) return false;
    if (_isOnDeviceMediaPath(url)) {
      try {
        final path =
            url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        return File(path).existsSync();
      } catch (_) {
        return false;
      }
    }
    try {
      final uri = Uri.parse(url);
      final head = await http
          .head(uri)
          .timeout(const Duration(seconds: 4));
      if (head.statusCode >= 200 && head.statusCode < 300) return true;

      // Some servers reject HEAD — probe with a 1-byte range GET.
      if (head.statusCode == 404) return false;
      final probe = await http
          .get(uri, headers: const {'Range': 'bytes=0-0'})
          .timeout(const Duration(seconds: 6));
      return probe.statusCode == 200 || probe.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> analyzeShot(File videoFile) async {
    final path = videoFile.path;
    final existing = _inFlight[path];
    if (existing != null) {
      // ignore: avoid_print
      print('ApiService reusing in-flight analyze for $path');
      return existing;
    }

    final future = _analyzeShotInternal(videoFile);
    _inFlight[path] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(path);
    }
  }

  static Future<Map<String, dynamic>> _analyzeShotInternal(
    File videoFile,
  ) async {
    if (!await videoFile.exists()) {
      throw Exception('Video file not found at ${videoFile.path}');
    }

    final size = await videoFile.length();
    // ignore: avoid_print
    print(
      'ApiService uploading ${videoFile.path} ($size bytes) → ${ApiConfig.analyzeUrl}',
    );
    if (size <= 0) {
      throw Exception('Video file is empty (0 bytes)');
    }

    final filename = videoFile.uri.pathSegments.isNotEmpty
        ? videoFile.uri.pathSegments.last
        : 'shot.mp4';

    String? baselineJson;
    try {
      final baseline = await _personalBaselinePayload();
      if (baseline != null) {
        baselineJson = jsonEncode(baseline);
      }
    } catch (e) {
      // ignore: avoid_print
      print('ApiService baseline attach skipped: $e');
    }

    return _postAnalyze(
      videoFile: videoFile,
      filename: filename,
      analyzeUrl: ApiConfig.analyzeUrl,
      baselineJson: baselineJson,
      dominantHand: ProfileService.current?.dominantHand,
    );
  }

  static Future<Map<String, dynamic>> _postAnalyze({
    required File videoFile,
    required String filename,
    required String analyzeUrl,
    String? baselineJson,
    String? dominantHand,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(analyzeUrl));
    request.headers['X-API-Key'] = ApiConfig.apiKey;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        videoFile.path,
        filename: filename,
      ),
    );
    if (baselineJson != null) {
      request.fields['personal_baseline'] = baselineJson;
    }
    // Lets the backend lock the shooting arm from the user's own declared
    // hand instead of guessing from wrist visibility — auto-detection is
    // unreliable when the camera is on the side opposite the shooting hand,
    // since that arm is partially occluded through the whole clip.
    if (dominantHand != null && dominantHand.trim().isNotEmpty) {
      request.fields['dominant_hand'] = dominantHand.trim();
    }

    final client = http.Client();
    try {
      // Pose + overlay rendering can take a while on longer clips.
      final streamed = await client
          .send(request)
          .timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);

      // ignore: avoid_print
      print(
        'ApiService status=${response.statusCode} body=${response.body.length} chars via $analyzeUrl',
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        Map<String, dynamic> map;
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        } else if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          throw Exception('Unexpected AI response format');
        }

        // Immediate playback must use a file that already exists.
        // Slow-mo / skeleton are rendered in the background and 404 until ready.
        final overlayReady = map['overlay_ready'] == true;
        final readyUrl = resolveMediaUrl(
          map['analysis_video_url'] as String? ??
              map['original_video_url'] as String? ??
              map['analysis_video'] as String?,
        );
        final slowUrl = resolveMediaUrl(
          map['slow_motion_video_url'] as String?,
        );
        final skeleton = resolveMediaUrl(
          map['skeleton_video_url'] as String?,
        );
        final original = resolveMediaUrl(
          map['original_video_url'] as String?,
        );

        // Always keep a ready-now URL for immediate Results playback.
        if (readyUrl != null) {
          map['analysis_video_url'] = readyUrl;
        }
        if (overlayReady && slowUrl != null) {
          map['slow_motion_video_url'] = slowUrl;
        } else {
          // Don't hand the client a 404 slow-mo URL.
          map.remove('slow_motion_video_url');
        }
        if (skeleton != null) {
          map['skeleton_video_url'] = skeleton;
        }
        if (original != null) {
          map['original_video_url'] = original;
        }

        // ignore: avoid_print
        print(
          'ApiService playback url=${map['analysis_video_url']} '
          'overlayReady=$overlayReady slow=$slowUrl '
          'temp_media_id=${map['temp_media_id']}',
        );

        // Weighted overall + specific coaching priorities for Results.
        try {
          return CoachingReportService.enrichResults(
            map,
            profile: ProfileService.current,
          );
        } catch (_) {
          return map;
        }
      }

      throw Exception(
        'AI analysis failed (${response.statusCode}): ${response.body}',
      );
    } finally {
      client.close();
    }
  }
}
