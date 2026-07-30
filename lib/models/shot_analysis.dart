import 'package:shootiq/models/biomechanics_result.dart';
import 'package:shootiq/models/breakdown_item.dart';

/// Shot analysis record stored in Supabase `shot_analysis`.
class ShotAnalysis {
  const ShotAnalysis({
    required this.id,
    required this.userId,
    required this.overallScore,
    required this.releaseScore,
    required this.arcScore,
    required this.elbowScore,
    required this.balanceScore,
    required this.followThroughScore,
    required this.createdAt,
    this.videoUrl,
    this.analysisVideoUrl,
    this.feedback = const [],
    this.strengths = const [],
    this.issues = const [],
    this.recommendations = const [],
    this.biomechanics = const [],
  });

  final String id;
  final String userId;
  final String? videoUrl;
  final String? analysisVideoUrl;
  final int overallScore;
  final int releaseScore;
  final int arcScore;
  final int elbowScore;
  final int balanceScore;
  final int followThroughScore;
  final DateTime createdAt;
  final List<String> feedback;
  final List<String> strengths;
  final List<String> issues;
  final List<String> recommendations;

  /// Step 5/6 biomechanics coaching categories from `/analyze`.
  final List<BiomechanicsResult> biomechanics;

  /// Default placeholder scores used until real AI analysis exists.
  static const placeholderOverall = 87;
  static const placeholderRelease = 82;
  static const placeholderArc = 91;
  static const placeholderElbow = 76;
  static const placeholderBalance = 88;
  static const placeholderFollowThrough = 94;

  factory ShotAnalysis.fromJson(Map<String, dynamic> json) {
    return ShotAnalysis(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      videoUrl: json['video_url'] as String?,
      analysisVideoUrl: json['analysis_video_url'] as String?,
      overallScore: (json['overall_score'] as num?)?.toInt() ?? placeholderOverall,
      releaseScore: (json['release_score'] as num?)?.toInt() ?? placeholderRelease,
      arcScore: (json['arc_score'] as num?)?.toInt() ?? placeholderArc,
      elbowScore: (json['elbow_score'] as num?)?.toInt() ?? placeholderElbow,
      balanceScore: (json['balance_score'] as num?)?.toInt() ?? placeholderBalance,
      followThroughScore:
          (json['follow_through_score'] as num?)?.toInt() ??
              placeholderFollowThrough,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      feedback: const [],
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'video_url': videoUrl,
      'overall_score': overallScore,
      'release_score': releaseScore,
      'arc_score': arcScore,
      'elbow_score': elbowScore,
      'balance_score': balanceScore,
      'follow_through_score': followThroughScore,
    };
  }

  /// Maps FastAPI `/analyze` JSON into a [ShotAnalysis] for UI + storage.
  factory ShotAnalysis.fromAiResponse(
    Map<String, dynamic> json, {
    String? videoUrl,
    String? userId,
  }) {
    final metrics = Map<String, dynamic>.from(
      (json['metrics'] as Map?) ?? const {},
    );
    final issues = (json['issues'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final recommendations = (json['recommendations'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final feedback = (json['feedback'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        recommendations;

    final elbow =
        (metrics['elbow_alignment'] as num?)?.toInt() ?? placeholderElbow;
    final knee = (metrics['knee_bend'] as num?)?.toInt() ?? placeholderArc;
    final balance =
        (metrics['balance'] as num?)?.toInt() ?? placeholderBalance;
    final followThrough = (metrics['follow_through'] as num?)?.toInt() ??
        placeholderFollowThrough;
    final release = (metrics['release_point'] as num?)?.toInt() ??
        (metrics['release_position'] as num?)?.toInt() ??
        placeholderFollowThrough;

    // Prefer API strengths; otherwise derive from metric scores only.
    var strengths = (json['strengths'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    if (strengths.isEmpty) {
      final derived = <String>[];
      if (balance >= 80) derived.add('Balance');
      if (followThrough >= 80) derived.add('Follow Through');
      if (knee >= 80) derived.add('Knee Bend');
      if (elbow >= 80) derived.add('Elbow Alignment');
      strengths = derived;
    }

    final bioSource =
        (json['biomechanics'] as List?) ?? (json['breakdown'] as List?);
    final biomechanics = bioSource
            ?.whereType<Map>()
            .map(
              (item) =>
                  BreakdownItem.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const <BiomechanicsResult>[];

    return ShotAnalysis(
      id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
      userId: userId ?? 'local',
      videoUrl: videoUrl,
      analysisVideoUrl: json['analysis_video_url'] as String? ??
          json['analysis_video'] as String?,
      overallScore:
          (json['overall_score'] as num?)?.toInt() ?? placeholderOverall,
      releaseScore: release,
      arcScore: knee,
      elbowScore: elbow,
      balanceScore: balance,
      followThroughScore: followThrough,
      createdAt: DateTime.now(),
      feedback: feedback,
      strengths: strengths,
      issues: issues,
      recommendations: recommendations,
      biomechanics: biomechanics,
    );
  }

  /// Single offline/demo analysis when DB/storage is unavailable.
  factory ShotAnalysis.placeholder({
    String? id,
    String? userId,
    String? videoUrl,
    DateTime? createdAt,
  }) {
    return ShotAnalysis(
      id: id ?? 'local-placeholder',
      userId: userId ?? 'local',
      videoUrl: videoUrl,
      overallScore: placeholderOverall,
      releaseScore: placeholderRelease,
      arcScore: placeholderArc,
      elbowScore: placeholderElbow,
      balanceScore: placeholderBalance,
      followThroughScore: placeholderFollowThrough,
      createdAt: createdAt ?? DateTime.now(),
      feedback: const [
        'Keep elbow closer to body',
        'Good balance',
      ],
      strengths: const [
        'Good balance',
        'Strong follow through',
      ],
      issues: const [
        'Elbow flares outward',
      ],
      recommendations: const [
        'Keep elbow underneath the ball',
        'Load legs before jumping',
      ],
    );
  }

  /// Home-page fallback list matching previous hardcoded cards.
  static List<ShotAnalysis> placeholderHistory() {
    final now = DateTime.now();
    return [
      ShotAnalysis.placeholder(
        id: 'placeholder-1',
        createdAt: now,
      ).copyWith(overallScore: 87),
      ShotAnalysis.placeholder(
        id: 'placeholder-2',
        createdAt: now.subtract(const Duration(days: 1)),
      ).copyWith(overallScore: 84),
      ShotAnalysis.placeholder(
        id: 'placeholder-3',
        createdAt: now.subtract(const Duration(days: 2)),
      ).copyWith(overallScore: 81),
      ShotAnalysis.placeholder(
        id: 'placeholder-4',
        createdAt: DateTime(now.year, now.month, 19),
      ).copyWith(overallScore: 89),
    ];
  }

  ShotAnalysis copyWith({
    String? id,
    String? userId,
    String? videoUrl,
    String? analysisVideoUrl,
    int? overallScore,
    int? releaseScore,
    int? arcScore,
    int? elbowScore,
    int? balanceScore,
    int? followThroughScore,
    DateTime? createdAt,
    List<String>? feedback,
    List<String>? strengths,
    List<String>? issues,
    List<String>? recommendations,
  }) {
    return ShotAnalysis(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      videoUrl: videoUrl ?? this.videoUrl,
      analysisVideoUrl: analysisVideoUrl ?? this.analysisVideoUrl,
      overallScore: overallScore ?? this.overallScore,
      releaseScore: releaseScore ?? this.releaseScore,
      arcScore: arcScore ?? this.arcScore,
      elbowScore: elbowScore ?? this.elbowScore,
      balanceScore: balanceScore ?? this.balanceScore,
      followThroughScore: followThroughScore ?? this.followThroughScore,
      createdAt: createdAt ?? this.createdAt,
      feedback: feedback ?? this.feedback,
      strengths: strengths ?? this.strengths,
      issues: issues ?? this.issues,
      recommendations: recommendations ?? this.recommendations,
    );
  }

  String get formattedDate {
    final now = DateTime.now();
    final local = createdAt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }
}
