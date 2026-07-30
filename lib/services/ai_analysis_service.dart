import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shootiq/config/api_config.dart';
import 'package:shootiq/services/coaching_report_service.dart';
import 'package:shootiq/services/profile_service.dart';

/// Exception thrown when AI analysis fails for a known reason.
class AiAnalysisException implements Exception {
  AiAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the local ShootIQ FastAPI backend (`POST /analyze`).
///
/// Usage:
/// ```dart
/// final result = await AiAnalysisService().analyzeShot(videoFile);
/// ```
class AiAnalysisService {
  AiAnalysisService({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _client = client ?? http.Client();

  /// FastAPI server base URL (from [ApiConfig] unless overridden).
  final String baseUrl;

  final http.Client _client;

  Uri get _analyzeUri => Uri.parse('$baseUrl/analyze');

  /// Uploads [video] to the AI backend and returns decoded analysis JSON.
  Future<Map<String, dynamic>> analyzeShot(File video) async {
    if (!await video.exists()) {
      throw AiAnalysisException(
        'Video file not found. Please record or choose a video again.',
      );
    }

    final fileSize = await video.length();
    if (fileSize <= 0) {
      throw AiAnalysisException(
        'This video file is empty or invalid. Try another clip.',
      );
    }

    final filename = p.basename(video.path);
    final extension = p.extension(filename).toLowerCase();
    const allowed = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v'};
    if (extension.isNotEmpty && !allowed.contains(extension)) {
      throw AiAnalysisException(
        'Unsupported video format. Please upload an MP4 or MOV file.',
      );
    }

    final request = http.MultipartRequest('POST', _analyzeUri);
    request.headers['X-API-Key'] = ApiConfig.apiKey;
    try {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          video.path,
          filename: filename,
        ),
      );
      // Lets the backend lock the shooting arm from the user's own declared
      // hand instead of guessing from wrist visibility — auto-detection is
      // unreliable when the camera is on the side opposite the shooting
      // hand, since that arm is partially occluded through the whole clip.
      final dominantHand = ProfileService.current?.dominantHand?.trim();
      if (dominantHand != null && dominantHand.isNotEmpty) {
        request.fields['dominant_hand'] = dominantHand;
      }
    } on FileSystemException {
      throw AiAnalysisException(
        'Could not read the video file. Please try uploading again.',
      );
    } catch (_) {
      throw AiAnalysisException(
        'Could not prepare the video for upload. Please try again.',
      );
    }

    late final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw AiAnalysisException(
            'The AI server took too long to respond. Please try again.',
          );
        },
      );
    } on AiAnalysisException {
      rethrow;
    } on SocketException {
      throw AiAnalysisException(
        'AI server unavailable. Make sure the ShootIQ AI backend is running '
        'on $baseUrl.',
      );
    } on HttpException {
      throw AiAnalysisException(
        'Upload failed. Could not reach the AI server.',
      );
    } catch (error) {
      if (error is AiAnalysisException) rethrow;
      throw AiAnalysisException(
        'AI server unavailable. Start the backend with '
        '`uvicorn main:app --host 0.0.0.0 --port 8000`, then try again.',
      );
    }

    final response = await http.Response.fromStream(streamed);
    final body = response.body;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final decoded = jsonDecode(body);
        Map<String, dynamic> map;
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        } else if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          throw AiAnalysisException(
            'Received an unexpected response from the AI server.',
          );
        }
        // Client-side coaching enrichment (weighted score + priorities).
        try {
          return CoachingReportService.enrichResults(
            map,
            profile: ProfileService.current,
          );
        } catch (_) {
          return map;
        }
      } on FormatException {
        throw AiAnalysisException(
          'Received invalid JSON from the AI server.',
        );
      }
    }

    if (response.statusCode == 400) {
      throw AiAnalysisException(
        _extractDetail(body) ??
            'Invalid video. Please upload a valid basketball clip.',
      );
    }

    if (response.statusCode == 413) {
      throw AiAnalysisException(
        'Video is too large to upload. Try a shorter clip.',
      );
    }

    if (response.statusCode >= 500) {
      throw AiAnalysisException(
        _extractDetail(body) ??
            'AI analysis failed on the server. Please try again.',
      );
    }

    throw AiAnalysisException(
      _extractDetail(body) ??
          'Upload failed (status ${response.statusCode}). Please try again.',
    );
  }

  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Ignore parse errors — caller will use a fallback message.
    }
    return null;
  }
}
