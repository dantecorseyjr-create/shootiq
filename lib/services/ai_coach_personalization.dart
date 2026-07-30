import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/shot_history_service.dart';

/// Snapshot of the athlete used to personalize AI Coach replies.
class AiCoachPersonalization {
  const AiCoachPersonalization({
    this.profile,
    this.shots = const [],
    this.goal,
  });

  final PlayerProfile? profile;
  final List<ShotRecord> shots;
  final String? goal;

  bool get hasAnalyses => shots.isNotEmpty;

  double? get averageScore {
    if (shots.isEmpty) return null;
    final total = shots.fold<int>(0, (sum, s) => sum + s.overallScore);
    return total / shots.length;
  }

  List<int> get recentScores =>
      shots.take(5).map((s) => s.overallScore).toList();

  String? get dominantHand => profile?.dominantHand;
  String? get position => profile?.position;
  String? get skillLevel => profile?.skillLevel;
  String? get displayName => profile?.fullName;

  List<String> get strengths {
    if (shots.isEmpty) return const [];
    final counts = <String, int>{};
    for (final shot in shots.take(8)) {
      final key = shot.strongestCategory;
      if (key != null) counts[key] = (counts[key] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(2).map((e) => e.key).toList();
  }

  List<String> get weaknesses {
    if (shots.isEmpty) return const [];
    final counts = <String, int>{};
    for (final shot in shots.take(8)) {
      final key = shot.needsWorkCategory;
      if (key != null) counts[key] = (counts[key] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(2).map((e) => e.key).toList();
  }

  bool get releaseImproving {
    final delta = categoryTrend((s) => s.releasePoint);
    return delta != null && delta > 2;
  }

  bool get elbowImproving {
    final delta = categoryTrend((s) => s.elbowAlignment);
    return delta != null && delta > 2;
  }

  bool get elbowStillWeak {
    if (shots.isEmpty) return false;
    final recent = shots.take(5).map((s) => s.elbowAlignment).where((v) => v > 0);
    if (recent.isEmpty) return false;
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    return avg < 78;
  }

  /// Positive = improving over recent vs older window (last ~10 shots).
  double? categoryTrend(int Function(ShotRecord) picker) {
    if (shots.length < 4) return null;
    final recent = shots.take(3).map(picker).where((v) => v > 0).toList();
    final older = shots.skip(3).take(7).map(picker).where((v) => v > 0).toList();
    if (recent.isEmpty || older.isEmpty) return null;
    final r = recent.reduce((a, b) => a + b) / recent.length;
    final o = older.reduce((a, b) => a + b) / older.length;
    return r - o;
  }

  int? get releaseTrendPoints {
    final d = categoryTrend((s) => s.releasePoint);
    return d?.round();
  }

  int? get elbowTrendPoints {
    final d = categoryTrend((s) => s.elbowAlignment);
    return d?.round();
  }

  String contextBlock() {
    final lines = <String>[];
    if (displayName != null && displayName!.isNotEmpty) {
      lines.add('Player: $displayName');
    }
    if (skillLevel != null) lines.add('Skill: $skillLevel');
    if (position != null) lines.add('Position: $position');
    if (dominantHand != null) lines.add('Dominant hand: $dominantHand');
    if (goal != null && goal!.isNotEmpty) lines.add('Goal: $goal');

    if (hasAnalyses) {
      final avg = averageScore?.round();
      lines.add('Analyses: ${shots.length}');
      if (avg != null) lines.add('Average score: $avg');
      if (recentScores.isNotEmpty) {
        lines.add('Recent scores: ${recentScores.join(', ')}');
      }
      if (strengths.isNotEmpty) {
        lines.add('Strengths: ${strengths.join(', ')}');
      }
      if (weaknesses.isNotEmpty) {
        lines.add('Weaknesses: ${weaknesses.join(', ')}');
      }
      if (releaseImproving) {
        final pts = releaseTrendPoints;
        lines.add(
          pts != null
              ? 'Trend: release timing improving (~+$pts points)'
              : 'Trend: release timing improving over recent shots',
        );
      }
      if (elbowStillWeak) {
        final pts = elbowTrendPoints;
        lines.add(
          pts != null && pts > 0
              ? 'Elbow improving slightly (~+$pts) but still inconsistent'
              : 'Elbow alignment still a limiter across recent shots',
        );
      }
    } else {
      lines.add('No prior shot analyses on file');
    }

    return lines.join('\n');
  }

  /// One-paragraph coach lead that weaves profile + recent analysis trends.
  String smartContextLead() {
    if (!hasAnalyses) {
      final bits = <String>[
        if (skillLevel != null) skillLevel!,
        if (position != null) position!,
        if (dominantHand != null) '${dominantHand!.toLowerCase()}-hand',
      ];
      if (bits.isEmpty && (goal == null || goal!.isEmpty)) return '';
      final who = bits.isEmpty ? 'your game' : bits.join(' · ');
      if (goal != null && goal!.isNotEmpty) {
        return 'For $who with a goal of **$goal**, I will keep advice practical '
            'until we have shot analyses on file.';
      }
      return 'Coaching for $who — analyze a few shots and I will tie every cue '
          'to your real mechanics.';
    }

    final parts = <String>[];
    final avg = averageScore?.round();
    final window = shots.take(5).length;

    if (avg != null) {
      parts.add('Your last $window shots average **$avg**');
    }

    if (releaseImproving && elbowStillWeak) {
      final pts = releaseTrendPoints;
      parts.add(
        'release timing is improving'
        '${pts != null ? ' (~+$pts points)' : ''}, but **elbow alignment** '
        'is still your biggest weakness',
      );
    } else {
      if (releaseImproving) {
        final pts = releaseTrendPoints;
        parts.add(
          pts != null
              ? 'release timing is improving (~+$pts points)'
              : 'release timing is improving',
        );
      }
      if (elbowStillWeak) {
        parts.add('elbow alignment is still your biggest limiter');
      } else if (weaknesses.isNotEmpty) {
        parts.add('**${weaknesses.first}** is still the clearest focus area');
      }
      if (strengths.isNotEmpty && !releaseImproving) {
        parts.add('**${strengths.first}** is already a strength');
      }
    }

    if (goal != null && goal!.isNotEmpty) {
      parts.add('goal: **$goal**');
    }

    if (parts.isEmpty) return '';
    if (parts.length == 1) return '${parts.first}.';
    final head = parts.first;
    final rest = parts.sublist(1);
    if (rest.length == 1) return '$head — ${rest.first}.';
    return '$head — ${rest.sublist(0, rest.length - 1).join(', ')}, '
        'and ${rest.last}.';
  }

  static Future<AiCoachPersonalization> load() async {
    PlayerProfile? profile = ProfileService.current;
    try {
      profile = await ProfileService.loadProfile();
    } catch (_) {}

    List<ShotRecord> shots = const [];
    try {
      shots = await ShotHistoryService.getUserShots(limit: 20);
    } catch (_) {}

    return AiCoachPersonalization(
      profile: profile,
      shots: shots,
      goal: OnboardingService.selectedGoal,
    );
  }
}
