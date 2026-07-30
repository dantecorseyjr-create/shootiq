import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/shot_history_service.dart';

/// Aggregates saved analyses into a "Today's Session" dashboard snapshot.
class SessionDashboardService {
  SessionDashboardService._();

  static const categoryOrder = <String>[
    'Feet & Stance',
    'Knee Bend',
    'Balance',
    'Elbow Alignment',
    'Release Point',
    'Follow Through',
  ];

  static Future<SessionDashboardSnapshot> load() async {
    final shots = await ShotHistoryService.getUserShots(limit: 200);
    return fromShots(shots);
  }

  static SessionDashboardSnapshot fromShots(List<ShotRecord> allShots) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrow = todayStart.add(const Duration(days: 1));

    final sortedAll = [...allShots]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final today = sortedAll
        .where(
          (s) =>
              !s.createdAt.isBefore(todayStart) && s.createdAt.isBefore(tomorrow),
        )
        .toList();

    final prior = sortedAll.where((s) => s.createdAt.isBefore(todayStart)).toList();

    if (today.isEmpty) {
      return SessionDashboardSnapshot.empty(
        recent: sortedAll.isEmpty ? null : sortedAll.first,
      );
    }

    final scores = today.map((s) => s.overallScore).toList();
    final avgOverall =
        (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.reduce((a, b) => a > b ? a : b);
    final lowest = scores.reduce((a, b) => a < b ? a : b);

    final categoryAverages = <String, int>{
      for (final label in categoryOrder)
        label: _average(today.map((s) => _categoryScore(s, label))),
    };

    final improvement = _mostImproved(today: today, prior: prior);
    final lowestCategory = categoryOrder.reduce(
      (a, b) => categoryAverages[a]! <= categoryAverages[b]! ? a : b,
    );

    return SessionDashboardSnapshot(
      shotsAnalyzed: today.length,
      averageOverall: avgOverall,
      bestOverall: best,
      lowestOverall: lowest,
      categoryAverages: categoryAverages,
      mostImprovedCategory: improvement?.$1,
      mostImprovedDelta: improvement?.$2,
      lowestCategory: lowestCategory,
      lowestCategoryScore: categoryAverages[lowestCategory]!,
      recent: today.first,
      hasTodaySession: true,
    );
  }

  /// Returns (category, delta) for the largest positive or least-negative change.
  static (String, int)? _mostImproved({
    required List<ShotRecord> today,
    required List<ShotRecord> prior,
  }) {
    final deltas = <String, int>{};

    if (prior.isNotEmpty) {
      final todayStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      var baseline = prior
          .where(
            (s) =>
                !s.createdAt.isBefore(yesterdayStart) &&
                s.createdAt.isBefore(todayStart),
          )
          .toList();
      if (baseline.isEmpty) {
        baseline = prior.take(20).toList();
      }

      for (final label in categoryOrder) {
        final current = _average(today.map((s) => _categoryScore(s, label)));
        final previous =
            _average(baseline.map((s) => _categoryScore(s, label)));
        deltas[label] = current - previous;
      }
    } else if (today.length >= 2) {
      final chronological = [...today]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final first = chronological.first;
      final last = chronological.last;
      for (final label in categoryOrder) {
        deltas[label] =
            _categoryScore(last, label) - _categoryScore(first, label);
      }
    } else {
      return null;
    }

    String? bestLabel;
    var bestDelta = -9999;
    for (final entry in deltas.entries) {
      if (entry.value > bestDelta) {
        bestDelta = entry.value;
        bestLabel = entry.key;
      }
    }
    if (bestLabel == null) return null;
    return (bestLabel, bestDelta);
  }

  static int _average(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return (list.reduce((a, b) => a + b) / list.length).round();
  }

  static int _categoryScore(ShotRecord shot, String label) {
    return switch (label) {
      'Feet & Stance' => shot.feetStance,
      'Knee Bend' => shot.kneeBend,
      'Balance' => shot.balance,
      'Elbow Alignment' => shot.elbowAlignment,
      'Release Point' => shot.releasePoint,
      'Follow Through' => shot.followThrough,
      _ => 0,
    };
  }
}

class SessionDashboardSnapshot {
  const SessionDashboardSnapshot({
    required this.shotsAnalyzed,
    required this.averageOverall,
    required this.bestOverall,
    required this.lowestOverall,
    required this.categoryAverages,
    required this.mostImprovedCategory,
    required this.mostImprovedDelta,
    required this.lowestCategory,
    required this.lowestCategoryScore,
    required this.recent,
    required this.hasTodaySession,
  });

  final int shotsAnalyzed;
  final int averageOverall;
  final int bestOverall;
  final int lowestOverall;
  final Map<String, int> categoryAverages;
  final String? mostImprovedCategory;
  final int? mostImprovedDelta;
  final String? lowestCategory;
  final int? lowestCategoryScore;
  final ShotRecord? recent;
  final bool hasTodaySession;

  factory SessionDashboardSnapshot.empty({ShotRecord? recent}) {
    return SessionDashboardSnapshot(
      shotsAnalyzed: 0,
      averageOverall: 0,
      bestOverall: 0,
      lowestOverall: 0,
      categoryAverages: {
        for (final label in SessionDashboardService.categoryOrder) label: 0,
      },
      mostImprovedCategory: null,
      mostImprovedDelta: null,
      lowestCategory: null,
      lowestCategoryScore: null,
      recent: recent,
      hasTodaySession: false,
    );
  }
}
