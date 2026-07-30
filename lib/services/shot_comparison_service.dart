import 'package:shootiq/models/shot_record.dart';

/// One metric row for side-by-side shot comparison (saved data only).
class ComparisonMetric {
  const ComparisonMetric({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final int before;
  final int after;

  /// Alias for table UIs that still label columns A/B.
  int get left => before;
  int get right => after;

  int get delta => after - before;
  bool get improved => delta > 0;
  bool get declined => delta < 0;
  bool get unchanged => delta == 0;

  String get changeLabel => delta > 0 ? '+$delta' : '$delta';
}

/// Key body-position phase for visual comparison scrubbing.
class ComparisonPhaseMarker {
  const ComparisonPhaseMarker({
    required this.label,
    required this.key,
    this.beforeSeconds,
    this.afterSeconds,
  });

  final String label;
  final String key;
  final double? beforeSeconds;
  final double? afterSeconds;

  bool get hasBefore => beforeSeconds != null;
  bool get hasAfter => afterSeconds != null;
}

/// Compare two saved analyses without reprocessing video / MediaPipe.
class ShotComparison {
  const ShotComparison({
    required this.older,
    required this.newer,
    required this.metrics,
    required this.summaries,
    required this.narrativeSummary,
    required this.developmentScorePercent,
    required this.phases,
  });

  /// Chronologically earlier shot (Before).
  final ShotRecord older;

  /// Chronologically later shot (After).
  final ShotRecord newer;

  final List<ComparisonMetric> metrics;
  final List<String> summaries;

  /// Single coach-style paragraph for the AI Summary card.
  final String narrativeSummary;

  /// Overall improvement vs the older shot in this pair (can be negative).
  final int developmentScorePercent;

  final List<ComparisonPhaseMarker> phases;

  /// Backward-compatible aliases used by existing UI.
  ShotRecord get left => older;
  ShotRecord get right => newer;

  static const metricOrder = <String>[
    'Overall Score',
    'Release Timing',
    'Elbow Alignment',
    'Balance',
    'Follow Through',
    'Knee Bend',
    'Feet & Stance',
  ];

  static const phaseOrder = <(String key, String label)>[
    ('setup', 'Setup'),
    ('dip', 'Dip'),
    ('jump', 'Jump'),
    ('release', 'Release'),
    ('follow_through', 'Follow Through'),
  ];

  /// Compare two shots. Automatically assigns older → newer by [createdAt].
  static ShotComparison compare(ShotRecord a, ShotRecord b) {
    final older = a.createdAt.isBefore(b.createdAt) ? a : b;
    final newer = identical(older, a) ? b : a;

    final values = <String, (int, int)>{
      'Overall Score': (older.overallScore, newer.overallScore),
      'Release Timing': (older.releasePoint, newer.releasePoint),
      'Elbow Alignment': (older.elbowAlignment, newer.elbowAlignment),
      'Balance': (older.balance, newer.balance),
      'Follow Through': (older.followThrough, newer.followThrough),
      'Knee Bend': (older.kneeBend, newer.kneeBend),
      'Feet & Stance': (older.feetStance, newer.feetStance),
    };

    final metrics = metricOrder
        .map(
          (label) => ComparisonMetric(
            label: label,
            before: values[label]!.$1,
            after: values[label]!.$2,
          ),
        )
        .where((m) {
          // Hide zero-zero stance rows when the metric was never captured.
          if (m.label == 'Feet & Stance' && m.before == 0 && m.after == 0) {
            return false;
          }
          return true;
        })
        .toList();

    final overall = metrics.firstWhere(
      (m) => m.label == 'Overall Score',
      orElse: () => ComparisonMetric(
        label: 'Overall Score',
        before: older.overallScore,
        after: newer.overallScore,
      ),
    );

    final development = _developmentPercent(
      before: overall.before,
      after: overall.after,
    );

    return ShotComparison(
      older: older,
      newer: newer,
      metrics: metrics,
      summaries: _summariesFromMetrics(metrics),
      narrativeSummary: _narrativeSummary(metrics),
      developmentScorePercent: development,
      phases: _buildPhases(older, newer),
    );
  }

  /// Improvement vs the player's first analyzed shot (career development).
  static int careerDevelopmentPercent({
    required ShotRecord firstShot,
    required ShotRecord currentShot,
  }) {
    return _developmentPercent(
      before: firstShot.overallScore,
      after: currentShot.overallScore,
    );
  }

  static int _developmentPercent({required int before, required int after}) {
    if (before <= 0) {
      return after > 0 ? 100 : 0;
    }
    final raw = ((after - before) / before) * 100;
    return raw.round();
  }

  static List<ComparisonPhaseMarker> _buildPhases(
    ShotRecord older,
    ShotRecord newer,
  ) {
    return phaseOrder.map((entry) {
      final key = entry.$1;
      final label = entry.$2;
      return ComparisonPhaseMarker(
        label: label,
        key: key,
        beforeSeconds: _phaseSeconds(older, key, label),
        afterSeconds: _phaseSeconds(newer, key, label),
      );
    }).toList();
  }

  static double? _phaseSeconds(ShotRecord shot, String key, String label) {
    final lowerKey = key.toLowerCase();
    final lowerLabel = label.toLowerCase();

    for (final item in shot.timeline) {
      final itemKey = (item.phaseKey ?? '').toLowerCase();
      final itemPhase = item.phase.toLowerCase();
      if (itemKey == lowerKey ||
          itemPhase == lowerLabel ||
          itemPhase.contains(lowerLabel) ||
          _phaseAliases(lowerKey).any(
            (alias) => itemKey.contains(alias) || itemPhase.contains(alias),
          )) {
        return item.keySeconds ?? item.startSeconds ?? item.seconds;
      }
    }

    for (final item in shot.breakdown) {
      final itemKey = (item.phaseKey ?? '').toLowerCase();
      final itemPhase = (item.phase ?? '').toLowerCase();
      if (itemKey == lowerKey ||
          itemPhase == lowerLabel ||
          _phaseAliases(lowerKey).any(
            (alias) => itemKey.contains(alias) || itemPhase.contains(alias),
          )) {
        if (item.seconds > 0) return item.seconds;
      }
    }

    return null;
  }

  static List<String> _phaseAliases(String key) {
    return switch (key) {
      'setup' => const ['setup', 'stance', 'gather'],
      'dip' => const ['dip', 'knee_load', 'load'],
      'jump' => const ['jump', 'upward', 'lift'],
      'release' => const ['release', 'set_point'],
      'follow_through' => const ['follow', 'landing'],
      _ => const [],
    };
  }

  /// Rule-based bullet insights from score differences.
  static List<String> _summariesFromMetrics(List<ComparisonMetric> metrics) {
    final lines = <String>[];

    String tone(ComparisonMetric m) {
      final mag = m.delta.abs();
      if (m.unchanged || mag <= 2) {
        return '${m.label} remained consistent.';
      }
      if (m.improved) {
        if (mag >= 10) return '${m.label} improved significantly.';
        if (mag >= 5) return '${m.label} improved.';
        return '${m.label} improved slightly.';
      }
      if (m.label == 'Follow Through') {
        if (mag >= 5) return 'Follow-through became less consistent.';
        return 'Follow-through decreased slightly.';
      }
      if (mag >= 10) return '${m.label} declined significantly.';
      if (mag >= 5) return '${m.label} declined.';
      return '${m.label} decreased slightly.';
    }

    final body = metrics.where((m) => m.label != 'Overall Score').toList()
      ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

    for (final m in body.take(3)) {
      lines.add(tone(m));
    }

    final overall = metrics.cast<ComparisonMetric?>().firstWhere(
          (m) => m?.label == 'Overall Score',
          orElse: () => null,
        );
    if (overall != null) {
      if (overall.delta >= 5) {
        lines.insert(0, 'Overall shooting score is up ${overall.delta} points.');
      } else if (overall.delta <= -5) {
        lines.insert(
          0,
          'Overall shooting score is down ${overall.delta.abs()} points.',
        );
      } else if (lines.isEmpty) {
        lines.add('Overall score remained consistent between these shots.');
      }
    }

    return lines.take(4).toList();
  }

  /// Coach-style paragraph highlighting the biggest improvement / regression.
  static String _narrativeSummary(List<ComparisonMetric> metrics) {
    final body = metrics.where((m) => m.label != 'Overall Score').toList();
    if (body.isEmpty) {
      return 'Compare these shots side by side to track your shooting evolution.';
    }

    final improved = body.where((m) => m.improved).toList()
      ..sort((a, b) => b.delta.compareTo(a.delta));
    final declined = body.where((m) => m.declined).toList()
      ..sort((a, b) => a.delta.compareTo(b.delta));

    final overall = metrics.cast<ComparisonMetric?>().firstWhere(
          (m) => m?.label == 'Overall Score',
          orElse: () => null,
        );

    final parts = <String>[];

    if (improved.isNotEmpty) {
      final top = improved.first;
      parts.add(
        'Your biggest improvement came from ${_friendlyLabel(top.label).toLowerCase()}.',
      );
      parts.add(_improvementDetail(top));
      if (improved.length > 1 && improved[1].delta >= 5) {
        parts.add(
          'Your ${_friendlyLabel(improved[1].label).toLowerCase()} has also improved.',
        );
      }
    } else if (declined.isNotEmpty) {
      final worst = declined.first;
      parts.add(
        'The biggest drop was in ${_friendlyLabel(worst.label).toLowerCase()}.',
      );
      parts.add(
        'Focus your next session on rebuilding that movement with clean, slow reps.',
      );
    } else {
      parts.add(
        'These shots were very similar across categories — consistency is locked in.',
      );
    }

    if (overall != null && overall.delta.abs() >= 3) {
      parts.add(
        overall.improved
            ? 'Overall you are up ${overall.delta} points.'
            : 'Overall you are down ${overall.delta.abs()} points — tighten the weak link and re-test.',
      );
    }

    return parts.join(' ');
  }

  static String _friendlyLabel(String label) {
    if (label == 'Release Timing') return 'Release timing';
    return label;
  }

  static String _improvementDetail(ComparisonMetric m) {
    return switch (m.label) {
      'Release Timing' =>
        'Your release is now happening closer to the top of your jump.',
      'Elbow Alignment' =>
        'Your elbow is tracking cleaner under the ball toward the rim.',
      'Balance' =>
        'Your base and landing are quieter and more repeatable.',
      'Follow Through' =>
        'You are holding a cleaner finish after the ball leaves your hand.',
      'Knee Bend' =>
        'Your load into the shot is using the legs more effectively.',
      'Feet & Stance' =>
        'Your stance is more consistent from catch to release.',
      _ => 'Keep reinforcing this mechanic in game-speed reps.',
    };
  }
}
