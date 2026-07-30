import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/models/shot_analysis.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/coaching_report_service.dart';

/// Everything the shot AI chat needs for personalized coaching.
class ShotCoachContext {
  const ShotCoachContext({
    required this.overallScore,
    required this.categoryScores,
    this.issues = const [],
    this.recommendations = const [],
    this.improvementSummary,
    this.breakdown = const [],
    this.timeline = const [],
    this.metrics = const {},
    this.profileSummary,
    this.previousShots = const [],
    this.priorities = const [],
    this.pointLosses = const [],
    this.skillLevel,
    this.position,
    this.dominantHand,
  });

  final int overallScore;
  final Map<String, int> categoryScores;
  final List<String> issues;
  final List<String> recommendations;
  final String? improvementSummary;
  final List<BreakdownItem> breakdown;
  final List<TimelineItem> timeline;
  final Map<String, dynamic> metrics;
  final String? profileSummary;
  final List<ShotHistorySnippet> previousShots;
  final List<CoachingPriority> priorities;
  final List<PointLossItem> pointLosses;
  final String? skillLevel;
  final String? position;
  final String? dominantHand;

  factory ShotCoachContext.fromAnalysis({
    required ShotAnalysis analysis,
    required List<BreakdownItem> breakdown,
    required List<TimelineItem> timeline,
    Map<String, dynamic>? rawResults,
    PlayerProfile? profile,
    List<ShotRecord> history = const [],
  }) {
    final metrics = Map<String, dynamic>.from(
      (rawResults?['metrics'] as Map?) ?? const {},
    );

    final report = CoachingReportService.build(
      breakdown: breakdown,
      metrics: metrics,
      profile: profile,
      history: history,
      serverOverall: analysis.overallScore,
    );

    final categoryScores = <String, int>{
      ...report.categoryScores,
      for (final item in breakdown) item.category: item.score,
    };

    final recommendations = report.recommendations.isNotEmpty
        ? report.recommendations
        : analysis.recommendations.isNotEmpty
            ? analysis.recommendations
            : breakdown
                .where((b) => b.status.toUpperCase() != 'PASS')
                .map((b) => b.correction)
                .where((c) => c.trim().isNotEmpty)
                .toList();

    final issues = report.issues.isNotEmpty
        ? report.issues
        : analysis.issues.isNotEmpty
            ? analysis.issues
            : breakdown
                .where((b) => b.status.toUpperCase() != 'PASS')
                .map((b) => b.issue)
                .where((c) => c.trim().isNotEmpty)
                .toList();

    final improvement = report.specificFeedback.isNotEmpty
        ? report.specificFeedback
        : rawResults?['improvement_summary'] as String? ??
            (issues.isNotEmpty ? issues.first : null);

    final previous = history
        .take(6)
        .map(
          (shot) => ShotHistorySnippet(
            score: shot.overallScore,
            createdAt: shot.createdAt,
            topIssue: shot.issues.isNotEmpty
                ? shot.issues.first
                : shot.improvementSummary,
            elbow: shot.elbowAlignment,
            balance: shot.balance,
            followThrough: shot.followThrough,
            release: shot.releasePoint,
          ),
        )
        .toList();

    return ShotCoachContext(
      overallScore: report.overallScore > 0
          ? report.overallScore
          : analysis.overallScore,
      categoryScores: categoryScores,
      issues: issues,
      recommendations: recommendations,
      improvementSummary: improvement,
      breakdown: breakdown,
      timeline: timeline,
      metrics: metrics,
      profileSummary: _profileLine(profile),
      previousShots: previous,
      priorities: report.priorities,
      pointLosses: report.pointLosses,
      skillLevel: profile?.skillLevel,
      position: profile?.position,
      dominantHand: profile?.dominantHand,
    );
  }

  static String? _profileLine(PlayerProfile? profile) {
    if (profile == null) return null;
    final parts = <String>[
      if (profile.fullName.isNotEmpty) profile.fullName,
      if (profile.skillLevel != null && profile.skillLevel!.isNotEmpty)
        profile.skillLevel!,
      if (profile.position != null && profile.position!.isNotEmpty)
        profile.position!,
      if (profile.dominantHand != null && profile.dominantHand!.isNotEmpty)
        '${profile.dominantHand} hand',
      if (profile.height != null && profile.height!.isNotEmpty) profile.height!,
      if (profile.experience != null) '${profile.experience} yrs exp',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  MapEntry<String, int>? get weakestCategory {
    if (categoryScores.isEmpty) return null;
    final ranked = categoryScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return ranked.first;
  }

  MapEntry<String, int>? get strongestCategory {
    if (categoryScores.isEmpty) return null;
    final ranked = categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first;
  }

  Map<String, dynamic> toExtra() => {
        'overallScore': overallScore,
        'categoryScores': categoryScores,
        'issues': issues,
        'recommendations': recommendations,
        'improvementSummary': improvementSummary,
        'breakdown': breakdown.map((b) => b.toJson()).toList(),
        'timeline': timeline.map((t) => t.toJson()).toList(),
        'metrics': metrics,
        'profileSummary': profileSummary,
        'previousShots': previousShots.map((s) => s.toJson()).toList(),
        'priorities': priorities.map((p) => p.toJson()).toList(),
        'pointLosses': pointLosses.map((p) => p.toJson()).toList(),
        'skillLevel': skillLevel,
        'position': position,
        'dominantHand': dominantHand,
      };

  static ShotCoachContext? fromExtra(Object? extra) {
    if (extra is ShotCoachContext) return extra;
    if (extra is! Map) return null;
    final map = Map<String, dynamic>.from(extra);
    return ShotCoachContext(
      overallScore: (map['overallScore'] as num?)?.toInt() ?? 0,
      categoryScores: Map<String, int>.from(
        (map['categoryScores'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {},
      ),
      issues: (map['issues'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      recommendations: (map['recommendations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      improvementSummary: map['improvementSummary'] as String?,
      breakdown: (map['breakdown'] as List?)
              ?.whereType<Map>()
              .map((e) => BreakdownItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      timeline: (map['timeline'] as List?)
              ?.whereType<Map>()
              .map((e) => TimelineItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      metrics: Map<String, dynamic>.from(
        (map['metrics'] as Map?) ?? const {},
      ),
      profileSummary: map['profileSummary'] as String?,
      previousShots: (map['previousShots'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    ShotHistorySnippet.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
      priorities: (map['priorities'] as List?)
              ?.whereType<Map>()
              .map(
                (e) =>
                    CoachingPriority.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
      pointLosses: (map['pointLosses'] as List?)
              ?.whereType<Map>()
              .map((e) => PointLossItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      skillLevel: map['skillLevel'] as String?,
      position: map['position'] as String?,
      dominantHand: map['dominantHand'] as String?,
    );
  }
}

class ShotHistorySnippet {
  const ShotHistorySnippet({
    required this.score,
    required this.createdAt,
    this.topIssue,
    this.elbow = 0,
    this.balance = 0,
    this.followThrough = 0,
    this.release = 0,
  });

  final int score;
  final DateTime createdAt;
  final String? topIssue;
  final int elbow;
  final int balance;
  final int followThrough;
  final int release;

  Map<String, dynamic> toJson() => {
        'score': score,
        'createdAt': createdAt.toIso8601String(),
        'topIssue': topIssue,
        'elbow': elbow,
        'balance': balance,
        'followThrough': followThrough,
        'release': release,
      };

  factory ShotHistorySnippet.fromJson(Map<String, dynamic> json) {
    return ShotHistorySnippet(
      score: (json['score'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      topIssue: json['topIssue'] as String?,
      elbow: (json['elbow'] as num?)?.toInt() ?? 0,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      followThrough: (json['followThrough'] as num?)?.toInt() ?? 0,
      release: (json['release'] as num?)?.toInt() ?? 0,
    );
  }
}
