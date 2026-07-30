import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/achievements_service.dart';
import 'package:shootiq/services/api_service.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/coaching_report_service.dart';
import 'package:shootiq/services/local_media_store.dart';
import 'package:shootiq/services/local_shot_history_store.dart';
import 'package:shootiq/services/personal_baseline_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/video_upload_service.dart';

/// Persists analyzed shots on the user's device only.
///
/// Basketball videos are never written to Supabase Storage. Supabase is used
/// for authentication, profiles, and subscription status — not shot media or
/// shot history tables.
class ShotHistoryService {
  ShotHistoryService._();

  /// Wait for a background FastAPI overlay, then download to Documents.
  static Future<String?> _downloadWhenReady({
    required String userId,
    required String shotId,
    required String url,
    required String suffix,
    int maxAttempts = 45,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final ready = await ApiService.isMediaReady(url);
      if (ready) {
        final path = await LocalMediaStore.downloadToDevice(
          userId: userId,
          shotId: shotId,
          url: url,
          suffix: suffix,
        );
        if (path != null) return path;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // ignore: avoid_print
    print('ShotHistoryService $suffix download timed out for $url');
    return LocalMediaStore.downloadToDevice(
      userId: userId,
      shotId: shotId,
      url: url,
      suffix: suffix,
    );
  }

  /// Save AI analysis for the signed-in user (local device only).
  static Future<ShotRecord> saveAnalyzedShot({
    required File localVideo,
    required Map<String, dynamic> aiResults,
    String shotType = 'Basketball Shot',
  }) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to save a shot.');
    }

    List<ShotRecord> prior = const [];
    try {
      prior = await getUserShots(limit: 10);
    } catch (_) {}
    try {
      await ProfileService.loadProfile();
    } catch (_) {}
    final enriched = CoachingReportService.enrichResults(
      aiResults,
      profile: ProfileService.current,
      history: prior,
    );

    final metrics = Map<String, dynamic>.from(
      (enriched['metrics'] as Map?) ?? const {},
    );

    final shotId = 'local-${DateTime.now().millisecondsSinceEpoch}';

    // Keep the original capture on-device (Documents), never Supabase.
    final localVideoPath = await LocalMediaStore.persistLocalVideo(
      userId: user.id,
      source: localVideo,
      shotId: shotId,
      suffix: 'original',
    );
    if (localVideoPath.startsWith('http://') ||
        localVideoPath.startsWith('https://')) {
      throw StateError('Failed to persist shot video on device.');
    }

    // Optional: pull temporary AI overlay onto the device for offline replay.
    String? analysisVideoPath;
    final remoteAnalysis = ApiService.resolveMediaUrl(
          enriched['analysis_video_url'] as String? ??
              enriched['analysis_video'] as String?,
        ) ??
        ApiService.resolveMediaUrl(
          enriched['original_video_url'] as String?,
        );
    if (remoteAnalysis != null) {
      analysisVideoPath = await LocalMediaStore.downloadToDevice(
        userId: user.id,
        shotId: shotId,
        url: remoteAnalysis,
        suffix: 'analysis',
      );
    }

    // Skeleton/slow render in the background — wait until ready, then save locally.
    String? skeletonPath;
    final skeletonRemote = ApiService.resolveMediaUrl(
      enriched['skeleton_video_url'] as String?,
    );
    if (skeletonRemote != null) {
      skeletonPath = await _downloadWhenReady(
        userId: user.id,
        shotId: shotId,
        url: skeletonRemote,
        suffix: 'skeleton',
      );
    }

    String? slowPath;
    final slowRemote = ApiService.resolveMediaUrl(
      enriched['slow_motion_video_url'] as String?,
    );
    if (slowRemote != null) {
      slowPath = await _downloadWhenReady(
        userId: user.id,
        shotId: shotId,
        url: slowRemote,
        suffix: 'slow',
        maxAttempts: 20,
      );
    }

    // Delete temporary AI server copies after overlays are on-device.
    final tempMediaId = enriched['temp_media_id'] as String?;
    if (tempMediaId != null && tempMediaId.isNotEmpty) {
      Future<void>.delayed(const Duration(minutes: 5), () async {
        await ApiService.cleanupTempMedia(tempMediaId);
      });
    }

    final issues = (enriched['issues'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final recommendations = (enriched['recommendations'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final breakdownSource =
        (enriched['biomechanics'] as List?) ?? (enriched['breakdown'] as List?);
    final breakdown = breakdownSource
            ?.whereType<Map>()
            .map(
              (item) =>
                  BreakdownItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const <BreakdownItem>[];
    final timeline = (enriched['timeline'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => TimelineItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const <TimelineItem>[];
    final improvementSummary = enriched['improvement_summary'] as String? ??
        (issues.isNotEmpty ? issues.first : null);

    var elbow = (metrics['elbow_alignment'] as num?)?.toInt() ??
        (metrics['set_point'] as num?)?.toInt() ??
        0;
    var knee = (metrics['knee_bend'] as num?)?.toInt() ??
        (metrics['load'] as num?)?.toInt() ??
        0;
    final balance = (metrics['balance'] as num?)?.toInt() ??
        (metrics['stance'] as num?)?.toInt() ??
        0;
    final follow = (metrics['follow_through'] as num?)?.toInt() ?? 0;
    var release = (metrics['release_position'] as num?)?.toInt() ??
        (metrics['release_point'] as num?)?.toInt() ??
        (metrics['release'] as num?)?.toInt() ??
        0;
    if (elbow == 0) {
      for (final item in breakdown) {
        final cat = item.category.toLowerCase();
        if (cat.contains('set') || cat.contains('elbow')) {
          elbow = item.score;
          break;
        }
      }
    }
    if (knee == 0) {
      for (final item in breakdown) {
        final cat = item.category.toLowerCase();
        if (cat == 'load' || cat.contains('knee')) {
          knee = item.score;
          break;
        }
      }
    }
    if (release == 0) {
      for (final item in breakdown) {
        if (item.category.toLowerCase().contains('release')) {
          release = item.score;
          break;
        }
      }
    }

    final overall = (enriched['overall_score'] as num?)?.toInt() ?? 0;
    var feet = (metrics['feet_stance'] as num?)?.toInt() ??
        (metrics['stance'] as num?)?.toInt() ??
        0;
    if (feet == 0) {
      for (final item in breakdown) {
        final cat = item.category.toLowerCase();
        if (cat.contains('feet') || cat == 'stance') {
          feet = item.score;
          break;
        }
      }
    }

    final baselineFeatures = Map<String, dynamic>.from(
      (enriched['baseline_features'] as Map?) ?? const {},
    );
    final measurementConfidence = Map<String, dynamic>.from(
      (enriched['measurement_confidence'] as Map?) ?? const {},
    );
    if (measurementConfidence.isEmpty) {
      for (final item in breakdown) {
        if (item.confidence != null) {
          measurementConfidence[item.category] = item.confidence;
        }
      }
    }
    final phaseLandmarks = Map<String, dynamic>.from(
      (enriched['phase_landmarks'] as Map?) ?? const {},
    );
    final personalization = Map<String, dynamic>.from(
      (enriched['personalization'] as Map?) ?? const {},
    );

    final frameMetrics = (enriched['frame_metrics'] as List?) ?? const [];
    final framePhases = (enriched['frame_phases'] as List?) ?? const [];
    final phaseDetector =
        Map<String, dynamic>.from((enriched['phase_detector'] as Map?) ?? const {});
    final coachingReport = Map<String, dynamic>.from(
      (enriched['coaching_report'] as Map?) ?? const {},
    );
    final categoryScores = Map<String, dynamic>.from(
      (enriched['category_scores'] as Map?) ?? const {},
    );
    final pointLosses = (enriched['point_losses'] as List?) ?? const [];
    final priorityImprovements =
        (enriched['priority_improvements'] as List?) ?? const [];

    final metricsJson = <String, dynamic>{
      'overall_score': overall,
      'feet_stance': feet,
      'elbow_alignment': elbow,
      'knee_bend': knee,
      'balance': balance,
      'follow_through': follow,
      'release_point': release,
      'baseline_features': baselineFeatures,
      'measurement_confidence': measurementConfidence,
      'phase_landmarks': phaseLandmarks,
      'personalization': personalization,
      'frame_metrics': frameMetrics,
      'frame_phases': framePhases,
      'phase_detector': phaseDetector,
      'coaching_report': coachingReport,
      'category_scores': categoryScores,
      'point_losses': pointLosses,
      'priority_improvements': priorityImprovements,
      'detected_issues': issues,
      'ai_recommendations': recommendations,
      'source': 'analyze',
      'step': enriched['step'] ?? 5,
      'storage': 'device_only',
    };

    final record = ShotRecord(
      id: shotId,
      userId: user.id,
      createdAt: DateTime.now(),
      videoUrl: localVideoPath,
      analysisVideoUrl: analysisVideoPath ?? localVideoPath,
      skeletonVideoUrl: skeletonPath,
      slowMotionVideoUrl: slowPath,
      poseDataUrl: null, // pose JSON stays ephemeral on the AI server
      metricsJson: metricsJson,
      overallScore: overall,
      elbowAlignment: elbow,
      kneeBend: knee,
      balance: balance,
      followThrough: follow,
      releasePoint: release,
      issues: issues,
      recommendations: recommendations,
      breakdown: breakdown,
      timeline: timeline,
      improvementSummary: improvementSummary,
      shotType: shotType,
    );

    await LocalShotHistoryStore.upsert(record);

    try {
      await PersonalBaselineService.recompute();
    } catch (e) {
      // ignore: avoid_print
      print('Personal baseline recompute skipped: $e');
    }

    try {
      final history = await getUserShots(limit: 500);
      final progression = AchievementsService.fromShots(history);
      await AchievementsService.syncCache(
        progression,
        lastScore: record.overallScore,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Achievements sync skipped: $e');
    }

    // ignore: avoid_print
    print(
      'Saved local shot history id=${record.id} score=${record.overallScore} '
      'video=${record.videoUrl}',
    );
    return record;
  }

  /// Permanently delete a shot from on-device history and local media files.
  static Future<void> deleteShot(ShotRecord shot) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to delete a shot.');
    }
    if (shot.userId.isNotEmpty && shot.userId != user.id) {
      throw StateError('You can only delete your own shots.');
    }

    final mediaUrls = <String?>[
      shot.videoUrl,
      shot.analysisVideoUrl,
      shot.skeletonVideoUrl,
      shot.slowMotionVideoUrl,
    ];

    // Legacy cleanup only — new shots never land in Supabase Storage.
    try {
      await VideoUploadService.removePublicUrls(mediaUrls);
    } catch (e) {
      // ignore: avoid_print
      print('Legacy storage cleanup warning: $e');
    }

    for (final url in mediaUrls) {
      await LocalMediaStore.deletePath(url);
    }

    // Remove sibling files under shootiq_media/{user}/{shotId}_*
    try {
      final sample = shot.videoUrl;
      if (sample != null && !sample.startsWith('http')) {
        final parent = Directory(p.dirname(sample));
        if (await parent.exists()) {
          final prefix = '${shot.id}_';
          await for (final entity in parent.list()) {
            if (entity is File && p.basename(entity.path).startsWith(prefix)) {
              await LocalMediaStore.deletePath(entity.path);
            }
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Local media folder cleanup warning: $e');
    }

    await LocalShotHistoryStore.removeById(shot.id);

    // ignore: avoid_print
    print('Deleted local shot history id=${shot.id}');
  }

  /// Newest shots for the signed-in user (on-device only).
  static Future<List<ShotRecord>> getUserShots({int limit = 50}) async {
    final user = AuthService.currentUser;
    if (user == null) return const [];

    final local = await LocalShotHistoryStore.loadForUser(user.id);
    return local.take(limit).toList();
  }
}
