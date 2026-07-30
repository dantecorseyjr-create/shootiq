import 'package:shootiq/models/breakdown_item.dart';

/// A saved basketball shot analysis row from Supabase `shots` / local history.
class ShotRecord {
  const ShotRecord({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.overallScore,
    required this.elbowAlignment,
    required this.kneeBend,
    required this.balance,
    required this.followThrough,
    this.releasePoint = 0,
    this.videoUrl,
    this.analysisVideoUrl,
    this.skeletonVideoUrl,
    this.slowMotionVideoUrl,
    this.poseDataUrl,
    this.metricsJson = const {},
    this.issues = const [],
    this.recommendations = const [],
    this.breakdown = const [],
    this.timeline = const [],
    this.improvementSummary,
    this.shotType,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final String? videoUrl;
  final String? analysisVideoUrl;
  final String? skeletonVideoUrl;
  final String? slowMotionVideoUrl;
  final String? poseDataUrl;
  final int overallScore;
  final int elbowAlignment;
  final int kneeBend;
  final int balance;
  final int followThrough;
  final int releasePoint;

  /// Extensible bag for future metrics (weekly reports, achievements, etc.).
  final Map<String, dynamic> metricsJson;

  /// Stance / Feet & Stance from metrics_json or breakdown (0 if unavailable).
  int get feetStance {
    final fromMetrics = (metricsJson['feet_stance'] as num?)?.toInt() ??
        (metricsJson['stance'] as num?)?.toInt();
    if (fromMetrics != null && fromMetrics > 0) return fromMetrics;
    for (final item in breakdown) {
      final cat = item.category.toLowerCase();
      if (cat.contains('feet') || cat == 'stance') {
        return item.score;
      }
    }
    return 0;
  }

  /// Best available analyzed video URL for compare playback.
  /// Prefers on-device files over temporary AI-server URLs.
  String? get comparePlaybackUrl {
    for (final candidate in <String?>[
      skeletonVideoUrl,
      analysisVideoUrl,
      slowMotionVideoUrl,
      videoUrl,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (!candidate.startsWith('http://') &&
          !candidate.startsWith('https://')) {
        return candidate;
      }
    }
    return skeletonVideoUrl ??
        analysisVideoUrl ??
        slowMotionVideoUrl ??
        videoUrl;
  }

  /// True when at least one stored path looks like a local file (not http).
  bool get hasLocalVideoCandidate {
    for (final candidate in <String?>[
      videoUrl,
      analysisVideoUrl,
      skeletonVideoUrl,
      slowMotionVideoUrl,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (!candidate.startsWith('http://') &&
          !candidate.startsWith('https://')) {
        return true;
      }
    }
    return false;
  }

  final List<String> issues;
  final List<String> recommendations;
  final List<BreakdownItem> breakdown;
  final List<TimelineItem> timeline;
  final String? improvementSummary;
  final String? shotType;

  /// Primary historical metrics used by Progress analytics.
  Map<String, int> get historicalMetrics => {
        'overall_score': overallScore,
        'elbow_alignment': elbowAlignment,
        'knee_bend': kneeBend,
        'balance': balance,
        'follow_through': followThrough,
        'release_point': releasePoint,
      };

  String? get strongestCategory {
    final ranked = _categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.isEmpty ? null : ranked.first.key;
  }

  String? get needsWorkCategory {
    final ranked = _categoryScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return ranked.isEmpty ? null : ranked.first.key;
  }

  Map<String, int> get _categoryScores => {
        'Elbow Alignment': elbowAlignment,
        'Knee Bend': kneeBend,
        'Balance': balance,
        'Follow Through': followThrough,
        'Release Point': releasePoint,
        // Feet & Stance lives in breakdown/metrics_json when available.
        if ((metricsJson['feet_stance'] as num?)?.toInt() != null)
          'Feet & Stance': (metricsJson['feet_stance'] as num).toInt(),
      };

  factory ShotRecord.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic value) {
      if (value is List) {
        return value.map((item) => item.toString()).toList();
      }
      return const [];
    }

    List<BreakdownItem> parseBreakdown(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => BreakdownItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    List<TimelineItem> parseTimeline(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => TimelineItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    int score(String primary, String legacy) =>
        (json[primary] as num?)?.toInt() ??
        (json[legacy] as num?)?.toInt() ??
        0;

    final slowUrl = json['slow_motion_video_url'] as String? ??
        json['analysis_video_url'] as String?;
    final analysisUrl = slowUrl ?? json['video_url'] as String?;
    final originalUrl = json['original_video_url'] as String? ??
        json['video_url'] as String?;

    final issues = parseList(json['issues']);
    final breakdown = parseBreakdown(json['biomechanics'] ?? json['breakdown']);

    final metricsJson = Map<String, dynamic>.from(
      (json['metrics_json'] as Map?) ?? const {},
    );

    int releaseFromBreakdown() {
      for (final item in breakdown) {
        if (item.category.toLowerCase().contains('release')) {
          return item.score;
        }
      }
      return 0;
    }

    final releasePoint = score('release_point', 'release_score') != 0
        ? score('release_point', 'release_score')
        : (metricsJson['release_point'] as num?)?.toInt() ??
            releaseFromBreakdown();

    return ShotRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      videoUrl: originalUrl,
      analysisVideoUrl: analysisUrl,
      skeletonVideoUrl: json['skeleton_video_url'] as String?,
      slowMotionVideoUrl: slowUrl,
      poseDataUrl: json['pose_data_url'] as String?,
      metricsJson: metricsJson,
      overallScore: (json['overall_score'] as num?)?.toInt() ?? 0,
      elbowAlignment: score('elbow_alignment', 'elbow_score'),
      kneeBend: score('knee_bend', 'arc_score'),
      balance: score('balance', 'balance_score'),
      followThrough: score('follow_through', 'follow_through_score'),
      releasePoint: releasePoint,
      issues: issues,
      recommendations: parseList(json['recommendations']),
      breakdown: breakdown,
      timeline: parseTimeline(json['timeline']),
      improvementSummary: json['improvement_summary'] as String? ??
          (issues.isNotEmpty
              ? issues.first
              : (breakdown.isNotEmpty && !breakdown.first.isPass
                  ? breakdown.first.issue
                  : null)),
      shotType: json['shot_type'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() {
    final metrics = {
      ...metricsJson,
      ...historicalMetrics,
    };
    return {
      'user_id': userId,
      'video_url': videoUrl,
      'analysis_video_url': analysisVideoUrl ?? slowMotionVideoUrl,
      'skeleton_video_url': skeletonVideoUrl,
      'slow_motion_video_url': slowMotionVideoUrl ?? analysisVideoUrl,
      'original_video_url': videoUrl,
      'pose_data_url': poseDataUrl,
      'overall_score': overallScore,
      'elbow_alignment': elbowAlignment,
      'knee_bend': kneeBend,
      'balance': balance,
      'follow_through': followThrough,
      'release_point': releasePoint,
      'metrics_json': metrics,
      'issues': issues,
      'recommendations': recommendations,
      'breakdown': breakdown.map((item) => item.toJson()).toList(),
      'biomechanics': breakdown.map((item) => item.toJson()).toList(),
      'timeline': timeline.map((item) => item.toJson()).toList(),
      if (improvementSummary != null)
        'improvement_summary': improvementSummary,
      if (shotType != null) 'shot_type': shotType,
    };
  }

  /// Full row including id/created_at for local persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      ...toInsertJson(),
    };
  }

  ShotRecord copyWith({
    String? id,
    String? userId,
    DateTime? createdAt,
    String? videoUrl,
    String? analysisVideoUrl,
    String? skeletonVideoUrl,
    String? slowMotionVideoUrl,
    String? poseDataUrl,
    Map<String, dynamic>? metricsJson,
    int? overallScore,
    int? elbowAlignment,
    int? kneeBend,
    int? balance,
    int? followThrough,
    int? releasePoint,
    List<String>? issues,
    List<String>? recommendations,
    List<BreakdownItem>? breakdown,
    List<TimelineItem>? timeline,
    String? improvementSummary,
    String? shotType,
  }) {
    return ShotRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      videoUrl: videoUrl ?? this.videoUrl,
      analysisVideoUrl: analysisVideoUrl ?? this.analysisVideoUrl,
      skeletonVideoUrl: skeletonVideoUrl ?? this.skeletonVideoUrl,
      slowMotionVideoUrl: slowMotionVideoUrl ?? this.slowMotionVideoUrl,
      poseDataUrl: poseDataUrl ?? this.poseDataUrl,
      metricsJson: metricsJson ?? this.metricsJson,
      overallScore: overallScore ?? this.overallScore,
      elbowAlignment: elbowAlignment ?? this.elbowAlignment,
      kneeBend: kneeBend ?? this.kneeBend,
      balance: balance ?? this.balance,
      followThrough: followThrough ?? this.followThrough,
      releasePoint: releasePoint ?? this.releasePoint,
      issues: issues ?? this.issues,
      recommendations: recommendations ?? this.recommendations,
      breakdown: breakdown ?? this.breakdown,
      timeline: timeline ?? this.timeline,
      improvementSummary: improvementSummary ?? this.improvementSummary,
      shotType: shotType ?? this.shotType,
    );
  }

  /// Payload for legacy `shot_analysis` (limited columns).
  Map<String, dynamic> toShotAnalysisInsertJson() {
    return {
      'user_id': userId,
      'video_url': analysisVideoUrl ?? videoUrl,
      'overall_score': overallScore,
      'elbow_score': elbowAlignment,
      'arc_score': kneeBend,
      'balance_score': balance,
      'follow_through_score': followThrough,
      'release_score': releasePoint,
    };
  }

  /// Map into ResultsPage FastAPI-shaped payload (history reopen parity).
  Map<String, dynamic> toResultsMap() {
    final playback = skeletonVideoUrl ??
        slowMotionVideoUrl ??
        analysisVideoUrl ??
        videoUrl;
    final hasSkeleton = skeletonVideoUrl != null && skeletonVideoUrl!.isNotEmpty;
    final frameMetrics = metricsJson['frame_metrics'];
    final framePhases = metricsJson['frame_phases'];
    final phaseDetector = metricsJson['phase_detector'];
    final coachingReport = metricsJson['coaching_report'];
    final categoryScores = metricsJson['category_scores'];
    final pointLosses = metricsJson['point_losses'];
    final priorityImprovements = metricsJson['priority_improvements'];
    return {
      'overall_score': overallScore,
      'metrics': {
        ...historicalMetrics,
        if (metricsJson['shot_arc'] != null) 'shot_arc': metricsJson['shot_arc'],
        if (metricsJson['landing'] != null) 'landing': metricsJson['landing'],
        if (metricsJson['hip_core'] != null) 'hip_core': metricsJson['hip_core'],
      },
      'metrics_json': metricsJson,
      'issues': issues,
      'recommendations': recommendations,
      'breakdown': breakdown.map((item) => item.toJson()).toList(),
      'biomechanics': breakdown.map((item) => item.toJson()).toList(),
      'timeline': timeline.map((item) => item.toJson()).toList(),
      if (frameMetrics != null) 'frame_metrics': frameMetrics,
      if (framePhases != null) 'frame_phases': framePhases,
      if (phaseDetector != null) 'phase_detector': phaseDetector,
      if (coachingReport != null) 'coaching_report': coachingReport,
      if (categoryScores != null) 'category_scores': categoryScores,
      if (pointLosses != null) 'point_losses': pointLosses,
      if (priorityImprovements != null)
        'priority_improvements': priorityImprovements,
      'improvement_summary': improvementSummary,
      'strengths': breakdown
          .where((item) => item.isPass)
          .map((item) => item.category)
          .toList(),
      'analysis_video_url': analysisVideoUrl ?? playback,
      'slow_motion_video_url': slowMotionVideoUrl,
      'skeleton_video_url': skeletonVideoUrl,
      'original_video_url': videoUrl,
      'local_video_path': videoUrl,
      'pose_data_url': poseDataUrl,
      'analysis_video': playback,
      'video_url': videoUrl,
      'shot_type': shotType,
      'overlay_ready': hasSkeleton,
      'step': 5,
    };
  }

  String get formattedDate {
    final local = createdAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}
