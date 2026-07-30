import 'dart:math' as math;

import 'package:shootiq/models/ai_coach_message.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/achievements_service.dart';
import 'package:shootiq/services/ai_coach_history_store.dart';
import 'package:shootiq/services/personal_baseline_service.dart';
import 'package:shootiq/services/session_dashboard_service.dart';
import 'package:shootiq/services/shot_history_service.dart';

enum ProgressRange { days7, days30, days90, allTime }

enum ProgressMetric {
  overall,
  elbow,
  knee,
  balance,
  followThrough,
  release,
  footwork,
}

/// Aggregates historical shot analyses into Progress insights.
class ProgressAnalyticsService {
  ProgressAnalyticsService._();

  static const categoryProgressOrder = <ProgressMetric>[
    ProgressMetric.release,
    ProgressMetric.balance,
    ProgressMetric.elbow,
    ProgressMetric.followThrough,
    ProgressMetric.footwork,
  ];

  static Future<ProgressSnapshot> load({
    ProgressRange range = ProgressRange.days30,
  }) async {
    final shots = await ShotHistoryService.getUserShots(limit: 500);
    Map<String, dynamic>? baseline;
    try {
      baseline = await PersonalBaselineService.load();
      if (baseline == null || baseline['ready'] != true) {
        baseline = await PersonalBaselineService.recompute(shots: shots);
      }
    } catch (_) {
      baseline = null;
    }
    final session = SessionDashboardService.fromShots(shots);
    List<AiCoachMessage> coachMessages = const [];
    try {
      coachMessages = await AiCoachHistoryStore.load();
    } catch (_) {}
    final progression = AchievementsService.fromShots(
      shots,
      coachMessages: coachMessages,
    );
    return fromShots(
      shots,
      range: range,
      baseline: baseline,
      session: session,
      progression: progression,
    );
  }

  static ProgressSnapshot fromShots(
    List<ShotRecord> allShots, {
    ProgressRange range = ProgressRange.days30,
    Map<String, dynamic>? baseline,
    SessionDashboardSnapshot? session,
    PlayerProgression? progression,
  }) {
    final sorted = [...allShots]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final filtered = _filter(sorted, range);
    final resolvedProgression =
        progression ?? AchievementsService.fromShots(sorted);

    return ProgressSnapshot(
      range: range,
      allShots: sorted,
      shotsInRange: filtered,
      baselinePayload: baseline,
      session: session ?? SessionDashboardService.fromShots(sorted),
      progression: resolvedProgression,
    );
  }

  static List<ShotRecord> _filter(List<ShotRecord> sorted, ProgressRange range) {
    if (range == ProgressRange.allTime) return sorted;
    final days = daysFor(range);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return sorted.where((s) => !s.createdAt.isBefore(cutoff)).toList();
  }

  /// Calendar days for a bounded range. Returns 0 for [ProgressRange.allTime].
  static int daysFor(ProgressRange range) {
    return switch (range) {
      ProgressRange.days7 => 7,
      ProgressRange.days30 => 30,
      ProgressRange.days90 => 90,
      ProgressRange.allTime => 0,
    };
  }

  static String metricLabel(ProgressMetric metric) {
    return switch (metric) {
      ProgressMetric.overall => 'Overall Score',
      ProgressMetric.elbow => 'Elbow Alignment',
      ProgressMetric.knee => 'Knee Bend',
      ProgressMetric.balance => 'Balance',
      ProgressMetric.followThrough => 'Follow Through',
      ProgressMetric.release => 'Release Timing',
      ProgressMetric.footwork => 'Footwork',
    };
  }

  static int metricValue(ShotRecord shot, ProgressMetric metric) {
    return switch (metric) {
      ProgressMetric.overall => shot.overallScore,
      ProgressMetric.elbow => shot.elbowAlignment,
      ProgressMetric.knee => shot.kneeBend,
      ProgressMetric.balance => shot.balance,
      ProgressMetric.followThrough => shot.followThrough,
      ProgressMetric.release => shot.releasePoint,
      // Prefer feet/stance when present; otherwise knee bend as stance proxy.
      ProgressMetric.footwork =>
        shot.feetStance > 0 ? shot.feetStance : shot.kneeBend,
    };
  }

  static String rangeLabel(ProgressRange range) {
    return switch (range) {
      ProgressRange.days7 => '7 Days',
      ProgressRange.days30 => '30 Days',
      ProgressRange.days90 => '90 Days',
      ProgressRange.allTime => 'All Time',
    };
  }
}

class ProgressSnapshot {
  const ProgressSnapshot({
    required this.range,
    required this.allShots,
    required this.shotsInRange,
    required this.progression,
    this.baselinePayload,
    this.session,
  });

  final ProgressRange range;
  final List<ShotRecord> allShots;
  final List<ShotRecord> shotsInRange;
  final PlayerProgression progression;
  final Map<String, dynamic>? baselinePayload;
  final SessionDashboardSnapshot? session;

  bool get isEmpty => allShots.isEmpty;

  int get totalAnalyses => allShots.length;

  /// Current-window average overall score.
  int? get currentAverageScore {
    final window = _currentWindow();
    if (window.isEmpty) return null;
    return _avg(window.map((s) => s.overallScore));
  }

  /// Prior-window average overall score.
  int? get previousAverageScore {
    final window = _previousWindow();
    if (window.isEmpty) return null;
    return _avg(window.map((s) => s.overallScore));
  }

  int get improvementDelta {
    final current = currentAverageScore;
    final previous = previousAverageScore;
    if (current == null || previous == null) return 0;
    return current - previous;
  }

  /// Latest single-shot score (kept for compatibility).
  int? get currentScore {
    if (allShots.isEmpty) return null;
    return allShots.last.overallScore;
  }

  int? get previousScore {
    if (allShots.length < 2) return null;
    return allShots[allShots.length - 2].overallScore;
  }

  int get scoreDelta {
    final current = currentScore;
    final previous = previousScore;
    if (current == null || previous == null) return 0;
    return current - previous;
  }

  int get weeklyChange {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final thisWeek =
        allShots.where((s) => !s.createdAt.isBefore(weekAgo)).toList();
    final prior = allShots.where((s) => s.createdAt.isBefore(weekAgo)).toList();
    if (thisWeek.isEmpty) return 0;
    final weekAvg = _avg(thisWeek.map((s) => s.overallScore));
    if (prior.isEmpty) {
      if (thisWeek.length < 2) return 0;
      return thisWeek.last.overallScore - thisWeek.first.overallScore;
    }
    final priorAvg = _avg(prior.map((s) => s.overallScore));
    return weekAvg - priorAvg;
  }

  List<ProgressPoint> series(ProgressMetric metric) {
    return shotsInRange
        .map(
          (shot) => ProgressPoint(
            date: shot.createdAt,
            value: ProgressAnalyticsService.metricValue(shot, metric).toDouble(),
            shotId: shot.id,
          ),
        )
        .toList();
  }

  /// Average / count / consistency for the active shot-trends range.
  ProgressTrendStats get trendStats {
    final shots = shotsInRange;
    if (shots.isEmpty) {
      return const ProgressTrendStats(
        averageScore: 0,
        shotsAnalyzed: 0,
        consistency: 0,
      );
    }
    final scores = shots.map((s) => s.overallScore).toList();
    return ProgressTrendStats(
      averageScore: _avg(scores),
      shotsAnalyzed: shots.length,
      consistency: _consistencyPercent(scores),
    );
  }

  List<CategoryProgress> get categoryProgress {
    final current = _currentWindow();
    final previous = _previousWindow();
    if (current.isEmpty) return const [];

    return ProgressAnalyticsService.categoryProgressOrder.map((metric) {
      final currentAvg =
          _avg(current.map((s) => ProgressAnalyticsService.metricValue(s, metric)));
      final beforeAvg = previous.isEmpty
          ? _baselineCategoryAverage(metric) ?? currentAvg
          : _avg(
              previous.map(
                (s) => ProgressAnalyticsService.metricValue(s, metric),
              ),
            );
      return CategoryProgress(
        metric: metric,
        label: ProgressAnalyticsService.metricLabel(metric),
        before: beforeAvg,
        current: currentAvg,
        delta: currentAvg - beforeAvg,
      );
    }).toList();
  }

  PersonalBaselineCompare? get baselineCompare {
    if (allShots.length < PersonalBaselineService.minSamples) {
      return PersonalBaselineCompare.notReady(
        sampleCount: allShots.length,
        minSamples: PersonalBaselineService.minSamples,
      );
    }

    final baselineScores = _scoreBaselineAverages();
    if (baselineScores.isEmpty) return null;

    final recent = allShots.length >= 5
        ? allShots.sublist(allShots.length - 5)
        : allShots;
    final userAvg = _avg(allShots.map((s) => s.overallScore));
    final bestShot = allShots.map((s) => s.overallScore).reduce(_max);
    final recentCategoryAvgs = <ProgressMetric, int>{
      for (final metric in ProgressAnalyticsService.categoryProgressOrder)
        metric: _avg(
          recent.map((s) => ProgressAnalyticsService.metricValue(s, metric)),
        ),
    };

    String? weakestLabel;
    var weakestScore = 101;
    for (final entry in recentCategoryAvgs.entries) {
      if (entry.value < weakestScore) {
        weakestScore = entry.value;
        weakestLabel = ProgressAnalyticsService.metricLabel(entry.key);
      }
    }

    final comparisons = <BaselineCategoryDelta>[];
    for (final metric in ProgressAnalyticsService.categoryProgressOrder) {
      final base = baselineScores[metric];
      final current = recentCategoryAvgs[metric];
      if (base == null || current == null || base == 0) continue;
      final pct = (((current - base) / base) * 100).round();
      comparisons.add(
        BaselineCategoryDelta(
          metric: metric,
          label: ProgressAnalyticsService.metricLabel(metric),
          baseline: base,
          current: current,
          percentDelta: pct,
        ),
      );
    }

    comparisons.sort(
      (a, b) => b.percentDelta.abs().compareTo(a.percentDelta.abs()),
    );

    return PersonalBaselineCompare(
      ready: true,
      sampleCount: allShots.length,
      minSamples: PersonalBaselineService.minSamples,
      userAverage: userAvg,
      bestShot: bestShot,
      weakestCategory: weakestLabel,
      weakestCategoryScore: weakestLabel == null ? null : weakestScore,
      categoryDeltas: comparisons,
      highlight: comparisons.isEmpty
          ? null
          : _baselineHighlight(comparisons.first),
    );
  }

  List<String> get aiInsights {
    if (allShots.isEmpty) {
      return const [
        'Analyze a shot to unlock AI development insights.',
      ];
    }

    final lines = <String>[];
    final categories = categoryProgress;
    if (categories.isNotEmpty) {
      final best = [...categories]..sort((a, b) => b.delta.compareTo(a.delta));
      final worst = [...categories]..sort((a, b) => a.delta.compareTo(b.delta));
      if (best.first.delta > 0) {
        final period = switch (range) {
          ProgressRange.days7 => 'this week',
          ProgressRange.days30 => 'this month',
          ProgressRange.days90 => 'these 90 days',
          ProgressRange.allTime => 'over time',
        };
        lines.add(
          'Your biggest improvement $period is ${best.first.label.toLowerCase()}.',
        );
      }
      if (worst.first.delta <= 0 ||
          worst.first.current <=
              categories.map((c) => c.current).reduce(_min)) {
        lines.add(
          'Your ${worst.first.label.toLowerCase()} is your biggest opportunity.',
        );
      }
    }

    final sessions = _practiceSessionCount(days: 30);
    final consistency = trendStats.consistency;
    if (sessions >= 3 && consistency >= 70) {
      lines.add(
        'Your consistency increased after completing $sessions practice sessions.',
      );
    } else if (sessions >= 3) {
      lines.add(
        'You logged $sessions practice sessions — keep stacking reps to lock in consistency.',
      );
    }

    final today = session;
    if (today != null &&
        today.hasTodaySession &&
        today.mostImprovedCategory != null &&
        (today.mostImprovedDelta ?? 0) > 0) {
      lines.add(
        "Today's session: ${today.mostImprovedCategory!.toLowerCase()} is up ${today.mostImprovedDelta} points.",
      );
    } else if (today != null &&
        today.hasTodaySession &&
        today.lowestCategory != null) {
      lines.add(
        "Focus next: ${today.lowestCategory!.toLowerCase()} is your weakest category today.",
      );
    }

    final baseline = baselineCompare;
    final highlight = baseline?.highlight;
    if (highlight != null &&
        highlight.isNotEmpty &&
        baseline?.ready == true) {
      lines.add(highlight);
    }

    final week = weeklyChange;
    if (week >= 3) {
      lines.add('Overall shooting score is up $week points this week.');
    } else if (week <= -3) {
      lines.add(
        'Overall shooting score is down ${week.abs()} points this week.',
      );
    }

    final streak = progression.streak.currentDays;
    if (streak >= 3) {
      lines.add('You are on a $streak-day analysis streak. Keep it going.');
    }

    for (final reminder in progression.reminders.take(2)) {
      lines.add(reminder.message);
    }

    if (lines.isEmpty) {
      lines.add('Keep analyzing shots to reveal clearer improvement patterns.');
    }

    // De-dupe while preserving order.
    final seen = <String>{};
    return lines.where(seen.add).take(4).toList();
  }

  /// Legacy summaries API — prefer [aiInsights].
  List<String> get summaries => aiInsights;

  List<ProgressGoal> get goals {
    return progression.goals
        .map(
          (g) => ProgressGoal(
            title: g.title,
            current: g.current,
            target: g.target,
            unit: g.unit,
            isPrimary: g.isPrimary,
          ),
        )
        .toList();
  }

  ProgressBests get bests {
    if (allShots.isEmpty) {
      return const ProgressBests(
        highestOverall: 0,
        bestElbow: 0,
        bestBalance: 0,
        improvementStreak: 0,
        totalAnalyses: 0,
      );
    }
    return ProgressBests(
      highestOverall: allShots.map((s) => s.overallScore).reduce(_max),
      bestElbow: allShots.map((s) => s.elbowAlignment).reduce(_max),
      bestBalance: allShots.map((s) => s.balance).reduce(_max),
      improvementStreak: _longestImprovementStreak(allShots),
      totalAnalyses: allShots.length,
    );
  }

  PlayerCareerStats get profileStats {
    final p = progression;
    return PlayerCareerStats(
      shotsAnalyzed: p.shotsAnalyzed,
      averageScore: p.averageScore,
      bestScore: p.bestScore,
      currentStreakDays: p.streak.currentDays,
      longestStreakDays: p.streak.longestDays,
      lastTrainingDate: p.streak.lastTrainingDate,
      achievements: p.achievements
          .map(
            (a) => ProgressAchievement(
              emoji: a.emoji,
              title: a.title,
              description: a.description,
              current: a.current,
              target: a.target,
              unit: a.unit,
              status: a.status,
            ),
          )
          .toList(),
      challenges: p.challenges,
      reminders: p.reminders,
    );
  }

  /// Sync derived career streak / last score into local onboarding cache.
  Future<void> syncProfileCache() async {
    await AchievementsService.syncCache(
      progression,
      lastScore: allShots.isEmpty ? null : allShots.last.overallScore,
    );
  }

  List<ShotRecord> _currentWindow() {
    if (range == ProgressRange.allTime) {
      if (allShots.isEmpty) return const [];
      if (allShots.length == 1) return allShots;
      return allShots.sublist(allShots.length ~/ 2);
    }
    return shotsInRange;
  }

  List<ShotRecord> _previousWindow() {
    if (allShots.isEmpty) return const [];

    if (range == ProgressRange.allTime) {
      if (allShots.length < 2) return const [];
      return allShots.sublist(0, allShots.length ~/ 2);
    }

    final days = ProgressAnalyticsService.daysFor(range);
    final now = DateTime.now();
    final currentStart = now.subtract(Duration(days: days));
    final previousStart = now.subtract(Duration(days: days * 2));
    return allShots
        .where(
          (s) =>
              !s.createdAt.isBefore(previousStart) &&
              s.createdAt.isBefore(currentStart),
        )
        .toList();
  }

  Map<ProgressMetric, int> _scoreBaselineAverages() {
    final fromPayload = _baselineScoresFromPayload();
    if (fromPayload.isNotEmpty) return fromPayload;

    if (allShots.length < PersonalBaselineService.minSamples) {
      return const {};
    }
    final first = allShots.take(PersonalBaselineService.minSamples).toList();
    return {
      for (final metric in ProgressAnalyticsService.categoryProgressOrder)
        metric: _avg(
          first.map((s) => ProgressAnalyticsService.metricValue(s, metric)),
        ),
    };
  }

  Map<ProgressMetric, int> _baselineScoresFromPayload() {
    final payload = baselinePayload;
    if (payload == null || payload['ready'] != true) return const {};
    final scores = Map<String, dynamic>.from(
      (payload['scores'] as Map?) ?? const {},
    );
    if (scores.isEmpty) return const {};

    int? meanFor(String key) {
      final raw = scores[key];
      if (raw is Map) {
        final mean = raw['mean'];
        if (mean is num) return mean.round();
      }
      if (raw is num) return raw.round();
      return null;
    }

    final map = <ProgressMetric, int>{};
    final elbow = meanFor('elbow_alignment');
    final balance = meanFor('balance');
    final follow = meanFor('follow_through');
    final release = meanFor('release_point');
    if (elbow != null) map[ProgressMetric.elbow] = elbow;
    if (balance != null) map[ProgressMetric.balance] = balance;
    if (follow != null) map[ProgressMetric.followThrough] = follow;
    if (release != null) map[ProgressMetric.release] = release;
    return map;
  }

  int? _baselineCategoryAverage(ProgressMetric metric) {
    return _scoreBaselineAverages()[metric];
  }

  static String _baselineHighlight(BaselineCategoryDelta delta) {
    final label = delta.label.toLowerCase();
    if (delta.percentDelta > 0) {
      return 'Your $label is ${delta.percentDelta}% better than your baseline.';
    }
    if (delta.percentDelta < 0) {
      return 'Your $label is ${delta.percentDelta.abs()}% below your baseline.';
    }
    return 'Your $label is matching your personal baseline.';
  }

  int _practiceSessionCount({required int days}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final daysWithShots = <String>{};
    for (final shot in allShots) {
      if (shot.createdAt.isBefore(cutoff)) continue;
      final d = shot.createdAt;
      daysWithShots.add('${d.year}-${d.month}-${d.day}');
    }
    return daysWithShots.length;
  }

  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;

  static int _avg(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return (list.reduce((a, b) => a + b) / list.length).round();
  }

  static int _consistencyPercent(List<int> scores) {
    if (scores.isEmpty) return 0;
    if (scores.length == 1) return 100;
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    if (mean <= 0) return 0;
    var sumSq = 0.0;
    for (final s in scores) {
      final d = s - mean;
      sumSq += d * d;
    }
    final std = math.sqrt(sumSq / scores.length);
    final cv = (std / mean).clamp(0.0, 1.0);
    return ((1.0 - cv) * 100).round().clamp(0, 100);
  }

  static int _longestImprovementStreak(List<ShotRecord> chronological) {
    if (chronological.length < 2) return chronological.isEmpty ? 0 : 1;
    var best = 1;
    var current = 1;
    for (var i = 1; i < chronological.length; i++) {
      if (chronological[i].overallScore >= chronological[i - 1].overallScore) {
        current += 1;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }
}

class ProgressPoint {
  const ProgressPoint({
    required this.date,
    required this.value,
    required this.shotId,
  });

  final DateTime date;
  final double value;
  final String shotId;
}

class ProgressBests {
  const ProgressBests({
    required this.highestOverall,
    required this.bestElbow,
    required this.bestBalance,
    required this.improvementStreak,
    required this.totalAnalyses,
  });

  final int highestOverall;
  final int bestElbow;
  final int bestBalance;
  final int improvementStreak;
  final int totalAnalyses;
}

class ProgressTrendStats {
  const ProgressTrendStats({
    required this.averageScore,
    required this.shotsAnalyzed,
    required this.consistency,
  });

  final int averageScore;
  final int shotsAnalyzed;
  final int consistency;
}

class CategoryProgress {
  const CategoryProgress({
    required this.metric,
    required this.label,
    required this.before,
    required this.current,
    required this.delta,
  });

  final ProgressMetric metric;
  final String label;
  final int before;
  final int current;
  final int delta;
}

class BaselineCategoryDelta {
  const BaselineCategoryDelta({
    required this.metric,
    required this.label,
    required this.baseline,
    required this.current,
    required this.percentDelta,
  });

  final ProgressMetric metric;
  final String label;
  final int baseline;
  final int current;
  final int percentDelta;
}

class PersonalBaselineCompare {
  const PersonalBaselineCompare({
    required this.ready,
    required this.sampleCount,
    required this.minSamples,
    this.userAverage,
    this.bestShot,
    this.weakestCategory,
    this.weakestCategoryScore,
    this.categoryDeltas = const [],
    this.highlight,
  });

  factory PersonalBaselineCompare.notReady({
    required int sampleCount,
    required int minSamples,
  }) {
    return PersonalBaselineCompare(
      ready: false,
      sampleCount: sampleCount,
      minSamples: minSamples,
      highlight:
          'Analyze ${minSamples - sampleCount} more shot${minSamples - sampleCount == 1 ? '' : 's'} to unlock your personal baseline.',
    );
  }

  final bool ready;
  final int sampleCount;
  final int minSamples;
  final int? userAverage;
  final int? bestShot;
  final String? weakestCategory;
  final int? weakestCategoryScore;
  final List<BaselineCategoryDelta> categoryDeltas;
  final String? highlight;
}

class ProgressGoal {
  const ProgressGoal({
    required this.title,
    required this.current,
    required this.target,
    required this.unit,
    this.isPrimary = false,
  });

  final String title;
  final int current;
  final int target;
  final String unit;
  final bool isPrimary;

  double get progress => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  bool get completed => current >= target;
}

class ProgressAchievement {
  const ProgressAchievement({
    required this.emoji,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
    required this.unit,
    required this.status,
  });

  final String emoji;
  final String title;
  final String description;
  final int current;
  final int target;
  final String unit;
  final AchievementStatus status;

  bool get completed => status == AchievementStatus.completed;

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  String get statusLabel => switch (status) {
        AchievementStatus.locked => 'Locked',
        AchievementStatus.inProgress => 'In Progress',
        AchievementStatus.completed => 'Completed',
      };

  String get progressLabel => '$current / $target $unit';
}

class PlayerCareerStats {
  const PlayerCareerStats({
    required this.shotsAnalyzed,
    required this.averageScore,
    required this.bestScore,
    required this.currentStreakDays,
    required this.achievements,
    this.longestStreakDays = 0,
    this.lastTrainingDate,
    this.challenges = const [],
    this.reminders = const [],
  });

  final int shotsAnalyzed;
  final int averageScore;
  final int bestScore;
  final int currentStreakDays;
  final int longestStreakDays;
  final DateTime? lastTrainingDate;
  final List<ProgressAchievement> achievements;
  final List<ChallengeItem> challenges;
  final List<ProgressionReminder> reminders;
}

/// Legacy alias — prefer [ShotComparison] in `shot_comparison_service.dart`.
class SessionComparison {
  const SessionComparison({
    required this.a,
    required this.b,
    required this.deltas,
  });

  final ShotRecord a;
  final ShotRecord b;

  /// Positive = B improved vs A.
  final Map<String, int> deltas;

  static SessionComparison compare(ShotRecord older, ShotRecord newer) {
    final deltas = <String, int>{
      'Overall Score': newer.overallScore - older.overallScore,
      'Feet & Stance': newer.feetStance - older.feetStance,
      'Elbow Alignment': newer.elbowAlignment - older.elbowAlignment,
      'Knee Bend': newer.kneeBend - older.kneeBend,
      'Balance': newer.balance - older.balance,
      'Follow Through': newer.followThrough - older.followThrough,
      'Release Point': newer.releasePoint - older.releasePoint,
    };
    return SessionComparison(a: older, b: newer, deltas: deltas);
  }
}
