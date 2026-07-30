import 'dart:io';

import 'package:shootiq/models/shot_analysis.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Legacy helpers related to Supabase Storage.
///
/// Basketball shot videos are **never** uploaded here. Videos stay on-device
/// (see [LocalMediaStore]) and are only sent temporarily to the local AI
/// server for analysis. Supabase is limited to auth, profiles, and
/// subscription status.
class VideoUploadService {
  VideoUploadService._();

  /// Historical bucket name — not used for new shot videos.
  static const bucketName = 'shot-videos';
  static const tableName = 'shot_analysis';

  static SupabaseClient get _client => Supabase.instance.client;

  /// Disabled: shot videos must not be stored in Supabase Storage.
  static Future<String> uploadShotVideo(File file) async {
    throw UnsupportedError(
      'Shot videos are stored on-device only. '
      'Do not upload basketball videos to Supabase Storage.',
    );
  }

  /// Extract a `shot-videos` object path from a legacy Supabase public URL.
  static String? objectPathFromPublicUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    const marker = '/object/public/$bucketName/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    final path = Uri.decodeComponent(url.substring(index + marker.length));
    return path.isEmpty ? null : path;
  }

  /// Best-effort remove of legacy objects (cleanup for older installs only).
  static Future<void> removePublicUrls(Iterable<String?> urls) async {
    final paths = <String>{};
    for (final url in urls) {
      final path = objectPathFromPublicUrl(url);
      if (path != null) {
        // Never delete avatar objects from shot cleanup.
        if (path.contains('/avatar/')) continue;
        paths.add(path);
      }
    }
    if (paths.isEmpty) return;

    try {
      await _client.storage.from(bucketName).remove(paths.toList());
    } catch (e) {
      // ignore: avoid_print
      print('Legacy storage cleanup skipped: $e');
    }
  }

  /// Disabled: analysis rows with video URLs are not written to Supabase.
  static Future<ShotAnalysis> saveAnalysisRecord({
    required String videoUrl,
    int overallScore = ShotAnalysis.placeholderOverall,
    int releaseScore = ShotAnalysis.placeholderRelease,
    int arcScore = ShotAnalysis.placeholderArc,
    int elbowScore = ShotAnalysis.placeholderElbow,
    int balanceScore = ShotAnalysis.placeholderBalance,
    int followThroughScore = ShotAnalysis.placeholderFollowThrough,
  }) async {
    throw UnsupportedError(
      'Shot analysis is saved locally on the device, not in Supabase.',
    );
  }

  /// Local placeholder history only (no remote video table).
  static Future<List<ShotAnalysis>> getUserAnalyses({int limit = 20}) async {
    return ShotAnalysis.placeholderHistory();
  }

  /// Returns a local placeholder — never uploads video to Supabase.
  static Future<ShotAnalysis> uploadAndSavePlaceholderAnalysis(
    File file,
  ) async {
    return ShotAnalysis.placeholder(
      videoUrl: file.path,
      userId: AuthService.currentUser?.id,
    );
  }
}
