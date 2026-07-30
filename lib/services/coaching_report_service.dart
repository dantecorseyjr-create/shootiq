import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/models/shot_record.dart';

import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/models/shot_record.dart';

/// One ranked coaching priority (max 3 shown to the athlete).
class CoachingPriority {
  const CoachingPriority({
    required this.rank,
    required this.category,
    required this.score,
    required this.observation,
    required this.fix,
    this.pointsLost = 0,
  });

  final int rank;
  final String category;
  final int score;
  final String observation;
  final String fix;
  final int pointsLost;

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'category': category,
        'score': score,
        'observation': observation,
        'fix': fix,
        'points_lost': pointsLost,
      };

  factory CoachingPriority.fromJson(Map<String, dynamic> json) {
    return CoachingPriority(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      observation: json['observation'] as String? ?? '',
      fix: json['fix'] as String? ?? '',
      pointsLost: (json['points_lost'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Explicit reason a category cost the athlete points vs ideal.
class PointLossItem {
  const PointLossItem({
    required this.category,
    required this.pointsLost,
    required this.reason,
    required this.score,
  });

  final String category;
  final int pointsLost;
  final String reason;
  final int score;

  Map<String, dynamic> toJson() => {
        'category': category,
        'points_lost': pointsLost,
        'reason': reason,
        'score': score,
      };

  factory PointLossItem.fromJson(Map<String, dynamic> json) {
    return PointLossItem(
      category: json['category'] as String? ?? '',
      pointsLost: (json['points_lost'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Coach-ready report built from biomechanics + player context.
class CoachingReport {
  const CoachingReport({
    required this.overallScore,
    required this.categoryScores,
    required this.weightedComponents,
    required this.priorities,
    required this.pointLosses,
    required this.specificFeedback,
    required this.issues,
    required this.recommendations,
    this.skillTone,
  });

  final int overallScore;
  final Map<String, int> categoryScores;
  final Map<String, int> weightedComponents;
  final List<CoachingPriority> priorities;
  final List<PointLossItem> pointLosses;
  final String specificFeedback;
  final List<String> issues;
  final List<String> recommendations;
  final String? skillTone;

  Map<String, dynamic> toJson() => {
        'overall_score': overallScore,
        'category_scores': categoryScores,
        'weighted_components': weightedComponents,
        'priorities': priorities.map((p) => p.toJson()).toList(),
        'point_losses': pointLosses.map((p) => p.toJson()).toList(),
        'specific_feedback': specificFeedback,
        'issues': issues,
        'recommendations': recommendations,
        if (skillTone != null) 'skill_tone': skillTone,
      };
}

/// Turns raw biomechanics into specific, prioritized basketball coaching.
class CoachingReportService {
  CoachingReportService._();

  /// Display categories every shot should evaluate.
  static const displayCategories = <String>[
    'Feet & Stance',
    'Knee Bend',
    'Hip & Core',
    'Elbow Alignment',
    'Release Timing',
    'Shot Arc',
    'Landing',
    'Follow Through',
  ];

  /// Weighted overall components (must sum to 1.0).
  static const weightRelease = 0.25;
  static const weightBalance = 0.20;
  static const weightElbow = 0.20;
  static const weightLowerBody = 0.15;
  static const weightFollowThrough = 0.10;
  static const weightConsistency = 0.10;

  static const _idealFloor = 92;

  static CoachingReport build({
    required List<BreakdownItem> breakdown,
    Map<String, dynamic> metrics = const {},
    PlayerProfile? profile,
    List<ShotRecord> history = const [],
    int? serverOverall,
  }) {
    final categoryScores = _resolveCategoryScores(breakdown, metrics);
    final weighted = _weightedComponents(categoryScores);
    final overall = _weightedOverall(weighted);
    final pointLosses = _pointLosses(categoryScores, breakdown);
    final priorities = _topPriorities(
      categoryScores: categoryScores,
      breakdown: breakdown,
      profile: profile,
      history: history,
      pointLosses: pointLosses,
    );
    final feedback = _specificFeedback(
      priorities: priorities,
      categoryScores: categoryScores,
      breakdown: breakdown,
      profile: profile,
      history: history,
    );
    final issues = priorities.map((p) => p.observation).toList();
    final recommendations = priorities.map((p) => p.fix).toList();

    return CoachingReport(
      overallScore: serverOverall ?? overall,
      categoryScores: categoryScores,
      weightedComponents: weighted,
      priorities: priorities,
      pointLosses: pointLosses,
      specificFeedback: feedback,
      issues: issues,
      recommendations: recommendations,
      skillTone: _skillTone(profile),
    );
  }

  /// Enrich a raw `/analyze` (or history) map for Results + persistence.
  static Map<String, dynamic> enrichResults(
    Map<String, dynamic> raw, {
    PlayerProfile? profile,
    List<ShotRecord> history = const [],
  }) {
    final breakdownSource =
        (raw['biomechanics'] as List?) ?? (raw['breakdown'] as List?);
    final breakdown = breakdownSource
            ?.whereType<Map>()
            .map((e) => BreakdownItem.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <BreakdownItem>[];
    final metrics = Map<String, dynamic>.from(
      (raw['metrics'] as Map?) ?? const {},
    );
    final report = build(
      breakdown: breakdown,
      metrics: metrics,
      profile: profile,
      history: history,
      serverOverall: (raw['overall_score'] as num?)?.toInt(),
    );

    final out = Map<String, dynamic>.from(raw);
    out['overall_score'] = report.overallScore;
    out['coaching_report'] = report.toJson();
    out['priority_improvements'] =
        report.priorities.map((p) => p.toJson()).toList();
    out['point_losses'] = report.pointLosses.map((p) => p.toJson()).toList();
    out['category_scores'] = report.categoryScores;
    out['weighted_components'] = report.weightedComponents;
    out['issues'] = report.issues.isNotEmpty
        ? report.issues
        : (raw['issues'] as List?) ?? const [];
    out['recommendations'] = report.recommendations.isNotEmpty
        ? report.recommendations
        : (raw['recommendations'] as List?) ?? const [];
    out['improvement_summary'] = report.specificFeedback;
    // Keep metrics in sync with coaching labels.
    final m = Map<String, dynamic>.from(metrics);
    m['feet_stance'] =
        report.categoryScores['Feet & Stance'] ?? m['feet_stance'];
    m['knee_bend'] = report.categoryScores['Knee Bend'] ?? m['knee_bend'];
    m['balance'] = report.categoryScores['Hip & Core'] ??
        report.categoryScores['Landing'] ??
        m['balance'];
    m['elbow_alignment'] =
        report.categoryScores['Elbow Alignment'] ?? m['elbow_alignment'];
    m['release_point'] =
        report.categoryScores['Release Timing'] ?? m['release_point'];
    m['follow_through'] =
        report.categoryScores['Follow Through'] ?? m['follow_through'];
    m['shot_arc'] = report.categoryScores['Shot Arc'];
    m['landing'] = report.categoryScores['Landing'];
    m['hip_core'] = report.categoryScores['Hip & Core'];
    out['metrics'] = m;
    return out;
  }

  static Map<String, int> _resolveCategoryScores(
    List<BreakdownItem> breakdown,
    Map<String, dynamic> metrics,
  ) {
    int fromBreakdown(List<String> aliases) {
      for (final item in breakdown) {
        final cat = item.category.toLowerCase();
        for (final alias in aliases) {
          if (cat == alias || cat.contains(alias)) return item.score;
        }
      }
      return 0;
    }

    int fromMetrics(List<String> keys) {
      for (final key in keys) {
        final v = (metrics[key] as num?)?.toInt();
        if (v != null && v > 0) return v;
      }
      return 0;
    }

    final feet = _firstPositive([
      fromBreakdown(const ['feet', 'stance']),
      fromMetrics(const ['feet_stance', 'stance']),
    ]);
    final knee = _firstPositive([
      fromBreakdown(const ['knee', 'load']),
      fromMetrics(const ['knee_bend', 'load']),
    ]);
    final elbow = _firstPositive([
      fromBreakdown(const ['elbow', 'set point', 'set_point']),
      fromMetrics(const ['elbow_alignment', 'set_point']),
    ]);
    final release = _firstPositive([
      fromBreakdown(const ['release']),
      fromMetrics(const ['release_point', 'release', 'release_position']),
    ]);
    final follow = _firstPositive([
      fromBreakdown(const ['follow']),
      fromMetrics(const ['follow_through']),
    ]);
    final balance = _firstPositive([
      fromBreakdown(const ['balance']),
      fromMetrics(const ['balance']),
      feet,
    ]);
    final ball = _firstPositive([
      fromBreakdown(const ['ball', 'hand', 'arc']),
      fromMetrics(const ['release_position', 'shot_arc']),
      release,
    ]);

    // Hip & Core: prefer balance body lean; blend with stance if needed.
    final hipCore = balance > 0
        ? ((balance * 0.7) + (feet * 0.3)).round().clamp(0, 100)
        : feet;
    // Shot Arc: ball path / release height proxy.
    final shotArc = ball > 0
        ? ((ball * 0.6) + (release * 0.4)).round().clamp(0, 100)
        : release;
    // Landing: follow-through balance finish.
    final landing = follow > 0
        ? ((follow * 0.55) + (balance * 0.45)).round().clamp(0, 100)
        : balance;

    final scores = <String, int>{
      'Feet & Stance': feet,
      'Knee Bend': knee,
      'Hip & Core': hipCore,
      'Elbow Alignment': elbow,
      'Release Timing': release,
      'Shot Arc': shotArc,
      'Landing': landing,
      'Follow Through': follow,
    };

    // Drop zeros that were never measured.
    scores.removeWhere((_, v) => v <= 0);
    return scores;
  }

  static int _firstPositive(List<int> values) {
    for (final v in values) {
      if (v > 0) return v;
    }
    return 0;
  }

  static Map<String, int> _weightedComponents(Map<String, int> scores) {
    final release = scores['Release Timing'] ?? 0;
    final balance = _avgNonZero([
      scores['Hip & Core'],
      scores['Landing'],
      scores['Feet & Stance'],
    ]);
    final elbow = scores['Elbow Alignment'] ?? 0;
    final lowerBody = _avgNonZero([
      scores['Knee Bend'],
      scores['Feet & Stance'],
    ]);
    final follow = scores['Follow Through'] ?? scores['Landing'] ?? 0;
    final consistency = _consistencyScore(scores);

    return {
      'Release Timing': release,
      'Balance': balance,
      'Elbow Alignment': elbow,
      'Lower Body': lowerBody,
      'Follow Through': follow,
      'Consistency': consistency,
    };
  }

  static int _weightedOverall(Map<String, int> components) {
    final pairs = <(int score, double weight)>[
      (components['Release Timing'] ?? 0, weightRelease),
      (components['Balance'] ?? 0, weightBalance),
      (components['Elbow Alignment'] ?? 0, weightElbow),
      (components['Lower Body'] ?? 0, weightLowerBody),
      (components['Follow Through'] ?? 0, weightFollowThrough),
      (components['Consistency'] ?? 0, weightConsistency),
    ].where((p) => p.$1 > 0).toList();

    if (pairs.isEmpty) return 0;
    final weightSum = pairs.fold<double>(0, (s, p) => s + p.$2);
    if (weightSum <= 0) return 0;
    final weighted = pairs.fold<double>(
      0,
      (s, p) => s + (p.$1 * p.$2),
    );
    return (weighted / weightSum).round().clamp(0, 100);
  }

  static int _avgNonZero(List<int?> values) {
    final nums = values.whereType<int>().where((v) => v > 0).toList();
    if (nums.isEmpty) return 0;
    return (nums.reduce((a, b) => a + b) / nums.length).round();
  }

  static int _consistencyScore(Map<String, int> scores) {
    final vals = scores.values.where((v) => v > 0).toList();
    if (vals.length < 2) return vals.isEmpty ? 0 : vals.first;
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    final variance =
        vals.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) /
            vals.length;
    final std = variance <= 0 ? 0.0 : _sqrt(variance);
    // Tight spread → high consistency (std 0 → 95, std 20 → ~55).
    return (95 - std * 2).round().clamp(40, 98);
  }

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    var x = value;
    for (var i = 0; i < 8; i++) {
      x = 0.5 * (x + value / x);
    }
    return x;
  }

  static List<PointLossItem> _pointLosses(
    Map<String, int> scores,
    List<BreakdownItem> breakdown,
  ) {
    final items = <PointLossItem>[];
    for (final entry in scores.entries) {
      final lost = (_idealFloor - entry.value).clamp(0, 100);
      if (lost < 4) continue;
      final source = _matchBreakdown(breakdown, entry.key);
      final reason = _lossReason(
        category: entry.key,
        score: entry.value,
        lost: lost,
        item: source,
      );
      items.add(
        PointLossItem(
          category: entry.key,
          pointsLost: lost,
          reason: reason,
          score: entry.value,
        ),
      );
    }
    items.sort((a, b) => b.pointsLost.compareTo(a.pointsLost));
    return items.take(5).toList();
  }

  static String _lossReason({
    required String category,
    required int score,
    required int lost,
    required BreakdownItem? item,
  }) {
    final measurement = item?.measurement?.trim();
    final issue = item?.issue.trim() ?? '';
    if (issue.isNotEmpty && !_isGeneric(issue)) {
      return issue;
    }
    if (measurement != null && measurement.isNotEmpty) {
      return 'Measured $measurement — $lost points below ideal timing/form.';
    }
    return switch (category) {
      'Release Timing' =>
        'Late release compared to ideal timing near the top of the jump.',
      'Elbow Alignment' =>
        'Shooting elbow drifted off the ideal under-ball path.',
      'Feet & Stance' =>
        'Stance width or foot alignment reduced base stability.',
      'Knee Bend' =>
        'Lower-body load depth or timing was off the ideal window.',
      'Hip & Core' => 'Core lean or hip alignment reduced transfer of power.',
      'Shot Arc' =>
        'Release angle / trajectory estimate was outside ideal arc.',
      'Landing' => 'Balance after the shot drifted forward or backward.',
      'Follow Through' =>
        'Finish was cut short before the ball reached the rim.',
      _ => 'Form in this category scored below the ideal range.',
    };
  }

  static List<CoachingPriority> _topPriorities({
    required Map<String, int> categoryScores,
    required List<BreakdownItem> breakdown,
    required PlayerProfile? profile,
    required List<ShotRecord> history,
    required List<PointLossItem> pointLosses,
  }) {
    final ranked = categoryScores.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final priorities = <CoachingPriority>[];
    for (var i = 0; i < ranked.length && priorities.length < 3; i++) {
      final entry = ranked[i];
      if (entry.value >= 88) continue;
      final source = _matchBreakdown(breakdown, entry.key);
      final loss = pointLosses.cast<PointLossItem?>().firstWhere(
            (p) => p?.category == entry.key,
            orElse: () => null,
          );
      priorities.add(
        CoachingPriority(
          rank: priorities.length + 1,
          category: entry.key,
          score: entry.value,
          observation: _observationFor(
            category: entry.key,
            score: entry.value,
            item: source,
            profile: profile,
            history: history,
          ),
          fix: _fixFor(
            category: entry.key,
            item: source,
            profile: profile,
          ),
          pointsLost:
              loss?.pointsLost ?? (_idealFloor - entry.value).clamp(0, 100),
        ),
      );
    }
    return priorities;
  }

  static BreakdownItem? _matchBreakdown(
    List<BreakdownItem> breakdown,
    String category,
  ) {
    final aliases = switch (category) {
      'Feet & Stance' => const ['stance', 'feet'],
      'Knee Bend' => const ['knee', 'load'],
      'Hip & Core' => const ['balance', 'hip', 'core'],
      'Elbow Alignment' => const ['elbow', 'set'],
      'Release Timing' => const ['release'],
      'Shot Arc' => const ['ball', 'hand', 'arc'],
      'Landing' => const ['landing', 'follow', 'balance'],
      'Follow Through' => const ['follow'],
      _ => const <String>[],
    };
    for (final item in breakdown) {
      final cat = item.category.toLowerCase();
      for (final alias in aliases) {
        if (cat.contains(alias)) return item;
      }
    }
    return null;
  }

  static bool _isGeneric(String text) {
    final t = text.toLowerCase();
    return t.contains('improve your') ||
        t.contains('needs attention') ||
        t.contains('form needs') ||
        t == 'improve your release.';
  }

  static String _observationFor({
    required String category,
    required int score,
    required BreakdownItem? item,
    required PlayerProfile? profile,
    required List<ShotRecord> history,
  }) {
    final issue = item?.issue.trim() ?? '';
    final measurement = item?.measurement?.trim();
    final skill = (profile?.skillLevel ?? '').toLowerCase();
    final hand = (profile?.dominantHand ?? 'shooting').toLowerCase();

    String base;
    if (issue.isNotEmpty && !_isGeneric(issue)) {
      base = issue;
      if (!base.endsWith('.') && !base.endsWith('!')) base = '$base.';
    } else {
      base = switch (category) {
        'Release Timing' =>
          'Your release is slightly late. Power from the legs finishes before the ball leaves your hand.',
        'Elbow Alignment' => measurement != null && measurement.contains('°')
            ? 'Your shooting elbow opens outward at set ($measurement).'
            : 'Your shooting elbow flares off the under-ball line at set point.',
        'Feet & Stance' =>
          'Your base is inconsistent — foot width or alignment is costing balance into the shot.',
        'Knee Bend' =>
          'Your dip timing is off. The knees are not loading and rising with the arm path.',
        'Hip & Core' =>
          'Your hips/core lean during the rise, leaking energy out of the shot line.',
        'Shot Arc' =>
          'Your release angle is flattening the arc — the ball is leaving on a lower trajectory.',
        'Landing' =>
          'You are drifting on the landing instead of finishing on balance in the same footprint.',
        'Follow Through' =>
          'Your wrist finish is short — the follow-through drops before the ball reaches the rim.',
        _ =>
          'This category scored $score and is limiting the rest of your form.',
      };
    }

    // Personalization layers.
    if (skill.contains('beginner') || skill.contains('youth')) {
      base = '$base Keep the cue simple: one motion, same set point every rep.';
    } else if (skill.contains('advanced') ||
        skill.contains('elite') ||
        skill.contains('college') ||
        skill.contains('pro')) {
      base =
          '$base At your level this should be automatic under fatigue — film game-speed reps.';
    }

    if (category == 'Elbow Alignment' && hand.contains('left')) {
      base = '$base Watch the left elbow track under the ball toward the rim.';
    } else if (category == 'Elbow Alignment' && hand.contains('right')) {
      base = '$base Watch the right elbow track under the ball toward the rim.';
    }

    // History-aware note.
    if (history.length >= 3) {
      final recentWeak = history.take(5).where((s) {
        final weak = s.needsWorkCategory?.toLowerCase() ?? '';
        return weak.contains(category.split(' ').first.toLowerCase()) ||
            (category == 'Elbow Alignment' && weak.contains('elbow')) ||
            (category == 'Release Timing' && weak.contains('release'));
      }).length;
      if (recentWeak >= 2) {
        base =
            '$base This has shown up on $recentWeak of your last ${history.take(5).length} analyses.';
      }
    }

    return base;
  }

  static String _fixFor({
    required String category,
    required BreakdownItem? item,
    required PlayerProfile? profile,
  }) {
    final correction = item?.correction.trim() ?? '';
    if (correction.isNotEmpty && !_isGeneric(correction)) {
      return correction.endsWith('.') ? correction : '$correction.';
    }

    final skill = (profile?.skillLevel ?? '').toLowerCase();
    final beginner = skill.contains('beginner') || skill.contains('youth');

    return switch (category) {
      'Release Timing' => beginner
          ? 'Start your wrist snap as you leave the dip — release near the top of your jump.'
          : 'Sync the wrist snap with the last inch of leg extension so the ball leaves at jump peak.',
      'Elbow Alignment' =>
        'Keep your shooting elbow under the ball — elbow to the rim on the rise.',
      'Feet & Stance' =>
        'Set shoulder-width feet, shooting-side toe slightly ahead, and hold that base into the jump.',
      'Knee Bend' =>
        'Load the knees first, then rise — legs start the shot, arms finish it.',
      'Hip & Core' =>
        'Keep the chest quiet and hips square; do not lean back to create arc.',
      'Shot Arc' =>
        'Finish higher with a soft wrist — aim for a rainbow that drops through the rim.',
      'Landing' =>
        'Land in the same footprint you jumped from and hold balance for a full count.',
      'Follow Through' =>
        'Hold your goose-neck follow-through until the ball reaches the rim.',
      _ => 'Slow the move down, own one cue, then rebuild to game speed.',
    };
  }

  static String _specificFeedback({
    required List<CoachingPriority> priorities,
    required Map<String, int> categoryScores,
    required List<BreakdownItem> breakdown,
    required PlayerProfile? profile,
    required List<ShotRecord> history,
  }) {
    if (priorities.isEmpty) {
      final strong = categoryScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = strong.isNotEmpty ? strong.first.key : 'your form';
      return 'Solid mechanics overall. $top is already a strength — '
          'protect it while you add game-speed volume.';
    }

    final top = priorities.first;
    final parts = <String>[top.observation, top.fix];

    if (priorities.length > 1) {
      parts.add(
        'Second focus: ${priorities[1].category.toLowerCase()} — ${priorities[1].fix}',
      );
    }

    // Trend sentence from history.
    if (history.length >= 4) {
      final releaseDelta = _categoryTrend(history, (s) => s.releasePoint);
      final elbowDelta = _categoryTrend(history, (s) => s.elbowAlignment);
      if (releaseDelta != null && elbowDelta != null) {
        if (releaseDelta >= 3 && elbowDelta <= 0) {
          parts.add(
            'Your release improved about ${releaseDelta.round()} points recently, '
            'but elbow alignment is still your biggest limiter.',
          );
        } else if (elbowDelta >= 3) {
          parts.add(
            'Elbow alignment has climbed about ${elbowDelta.round()} points — keep reinforcing that set point.',
          );
        }
      }
    }

    final position = profile?.position;
    if (position != null && position.isNotEmpty) {
      parts.add(_positionNote(position, top.category));
    }

    return parts.join(' ');
  }

  static double? _categoryTrend(
    List<ShotRecord> history,
    int Function(ShotRecord) picker,
  ) {
    if (history.length < 4) return null;
    final recent = history.take(3).map(picker).where((v) => v > 0).toList();
    final older =
        history.skip(3).take(5).map(picker).where((v) => v > 0).toList();
    if (recent.isEmpty || older.isEmpty) return null;
    final r = recent.reduce((a, b) => a + b) / recent.length;
    final o = older.reduce((a, b) => a + b) / older.length;
    return r - o;
  }

  static String _positionNote(String position, String focus) {
    final p = position.toLowerCase();
    if (p.contains('guard')) {
      return focus.contains('Release')
          ? 'As a guard, quicker release on the catch is the game-speed standard.'
          : 'Guards win with a quiet base and a fast, repeatable set point.';
    }
    if (p.contains('forward') || p.contains('wing')) {
      return 'Forwards need this fix under contact — own it on catch-and-shoot first.';
    }
    if (p.contains('center') || p.contains('post')) {
      return 'Bigs: keep the same pocket and finish high even from shorter range.';
    }
    return '';
  }

  static String? _skillTone(PlayerProfile? profile) {
    final skill = profile?.skillLevel;
    if (skill == null || skill.isEmpty) return null;
    return skill;
  }
}
