import 'package:shootiq/models/training_drill.dart';
import 'package:shootiq/services/ai_coach_personalization.dart';

/// Personalized basketball drills + workout builder driven by shot weaknesses.
class TrainingDrillsService {
  TrainingDrillsService._();

  static const catalog = <TrainingDrill>[
    // Release
    TrainingDrill(
      id: 'release_quick',
      title: 'Quick Release Shooting',
      category: DrillCategory.release,
      durationMinutes: 15,
      difficulty: 'Intermediate',
      problem: 'Late Release Timing',
      instructions: [
        'Start at mid range.',
        'Catch and shoot immediately.',
        'Focus on releasing before reaching the peak of your jump.',
      ],
      reps: '5 sets × 10 shots',
      sets: 5,
      focusCue: 'Up and through',
    ),
    TrainingDrill(
      id: 'release_one_motion',
      title: 'One Motion Shooting',
      category: DrillCategory.release,
      durationMinutes: 12,
      difficulty: 'Intermediate',
      problem: 'Hitchy or two-motion release',
      instructions: [
        'Start close to the basket with perfect form.',
        'Load legs and rise in one continuous motion.',
        'No pause at the set point — fluid from dip to release.',
      ],
      reps: '4 sets × 12 makes',
      focusCue: 'One piece',
    ),
    TrainingDrill(
      id: 'release_catch_shoot',
      title: 'Catch and Shoot',
      category: DrillCategory.release,
      durationMinutes: 14,
      difficulty: 'Beginner',
      problem: 'Slow gather into the shot',
      instructions: [
        'Partner or self-toss into a catch.',
        'Feet set before the ball arrives.',
        'Shoot on the catch — no extra dip if timing is late.',
      ],
      reps: '6 spots × 8 shots',
      focusCue: 'Ready early',
    ),
    // Balance
    TrainingDrill(
      id: 'balance_one_leg',
      title: 'One Leg Landing',
      category: DrillCategory.balance,
      durationMinutes: 10,
      difficulty: 'Advanced',
      problem: 'Unstable landing / fading',
      instructions: [
        'Shoot form shots and land quietly on both feet.',
        'Progress to a soft one-leg hold for 2 seconds after make.',
        'Keep chest square — no side lean.',
      ],
      reps: '3 sets × 10 holds',
      focusCue: 'Quiet feet',
    ),
    TrainingDrill(
      id: 'balance_hold_ft',
      title: 'Hold Follow Through',
      category: DrillCategory.balance,
      durationMinutes: 10,
      difficulty: 'Beginner',
      problem: 'Balance breaks after release',
      instructions: [
        'Shoot and freeze the finish until the ball hits.',
        'Check that you land in the same footprint.',
        'Reset stance fully between every rep.',
      ],
      reps: '4 sets × 10 makes',
      focusCue: 'Finish tall',
    ),
    TrainingDrill(
      id: 'balance_jump_stops',
      title: 'Controlled Jump Stops',
      category: DrillCategory.balance,
      durationMinutes: 12,
      difficulty: 'Intermediate',
      problem: 'Rushing into off-balance shots',
      instructions: [
        'Dribble into a jump stop at mid range.',
        'Pause one count, then rise straight up.',
        'Land soft — same spot you left.',
      ],
      reps: '5 sets × 8 shots',
      focusCue: 'Stop, then shoot',
    ),
    // Range
    TrainingDrill(
      id: 'range_progressive',
      title: 'Progressive Distance Shooting',
      category: DrillCategory.range,
      durationMinutes: 18,
      difficulty: 'Intermediate',
      problem: 'Form breaks as distance increases',
      instructions: [
        'Make 8 shots at close range with perfect form.',
        'Step back one shoe length and repeat.',
        'If form breaks, move closer immediately.',
      ],
      reps: 'Until game distance × 8 makes each',
      focusCue: 'Legs for range',
    ),
    TrainingDrill(
      id: 'range_deep_form',
      title: 'Deep Shot Form Drill',
      category: DrillCategory.range,
      durationMinutes: 15,
      difficulty: 'Advanced',
      problem: 'Muscling deep shots',
      instructions: [
        'Warm up inside the arc with high arc.',
        'Take deep shots focusing on leg drive, not arm power.',
        'Hold a high finish on every attempt.',
      ],
      reps: '4 sets × 10 deep shots',
      focusCue: 'Finish above the rim',
    ),
    // Consistency
    TrainingDrill(
      id: 'consistency_100',
      title: '100 Shot Challenge',
      category: DrillCategory.consistency,
      durationMinutes: 25,
      difficulty: 'Intermediate',
      problem: 'Inconsistent mechanics under volume',
      instructions: [
        'Take 100 quality shots from mixed spots.',
        'Track makes — reset form every miss streak of 3.',
        'Same routine and cue on every attempt.',
      ],
      reps: '100 total shots',
      focusCue: 'Same shot every time',
    ),
    TrainingDrill(
      id: 'consistency_game_speed',
      title: 'Game Speed Shooting',
      category: DrillCategory.consistency,
      durationMinutes: 16,
      difficulty: 'Advanced',
      problem: 'Form only works in slow practice',
      instructions: [
        'Warm up with 10 slow makes.',
        'Switch to game-speed catch-and-shoot.',
        'Only count makes that look identical to your form shots.',
      ],
      reps: '5 spots × 10 game-speed shots',
      focusCue: 'Same form, faster feet',
    ),
    // Elbow
    TrainingDrill(
      id: 'elbow_wall',
      title: 'Elbow Alignment Wall Drill',
      category: DrillCategory.elbow,
      durationMinutes: 10,
      difficulty: 'Beginner',
      problem: 'Flared elbow / poor alignment',
      instructions: [
        'Stand sideways to a wall on your shooting side.',
        'Rise to set point with forearm lightly tracking the wall path.',
        'Shoot without letting the elbow flare out.',
      ],
      reps: '4 sets × 12 makes',
      focusCue: 'Elbow to the rim',
    ),
    TrainingDrill(
      id: 'elbow_pocket',
      title: 'Shot Pocket Consistency',
      category: DrillCategory.elbow,
      durationMinutes: 12,
      difficulty: 'Intermediate',
      problem: 'Inconsistent set point',
      instructions: [
        'Start every rep with the ball in the same shot pocket.',
        'Pause briefly at set point to check elbow under the ball.',
        'Release and hold finish.',
      ],
      reps: '5 sets × 8 shots',
      focusCue: 'Pocket → rim',
    ),
    // Follow through
    TrainingDrill(
      id: 'ft_goose',
      title: 'Goose-Neck Finish',
      category: DrillCategory.followThrough,
      durationMinutes: 10,
      difficulty: 'Beginner',
      problem: 'Dropping the follow-through early',
      instructions: [
        'One-hand form shots only.',
        'Snap wrist and hold goose-neck until ball lands.',
        'Guide hand off early to kill thumb flick.',
      ],
      reps: '25 makes',
      focusCue: 'Hold the finish',
    ),
  ];

  static List<DrillCategory> get primaryCategories => const [
        DrillCategory.release,
        DrillCategory.balance,
        DrillCategory.range,
        DrillCategory.consistency,
      ];

  static List<TrainingDrill> drillsForCategory(DrillCategory category) {
    return catalog.where((d) => d.category == category).toList();
  }

  static TrainingDrill? byId(String id) {
    for (final drill in catalog) {
      if (drill.id == id) return drill;
    }
    return null;
  }

  /// Rank catalog drills for this athlete's weaknesses / goals / level.
  static List<TrainingDrill> personalizedDrills(
    AiCoachPersonalization personalization, {
    int limit = 6,
  }) {
    final ranked = List<TrainingDrill>.from(catalog);
    ranked.sort((a, b) {
      final scoreA = _relevance(a, personalization);
      final scoreB = _relevance(b, personalization);
      return scoreB.compareTo(scoreA);
    });
    return ranked.take(limit).toList();
  }

  /// Top AI drill targeting the current biggest weakness.
  static TrainingDrill primaryAiDrill(AiCoachPersonalization personalization) {
    final ranked = personalizedDrills(personalization, limit: 1);
    return ranked.isNotEmpty ? ranked.first : catalog.first;
  }

  static int _relevance(
    TrainingDrill drill,
    AiCoachPersonalization personalization,
  ) {
    var score = 0;
    final weak = personalization.weaknesses.map((w) => w.toLowerCase()).toList();
    final strong =
        personalization.strengths.map((s) => s.toLowerCase()).toList();
    final goal = (personalization.goal ?? '').toLowerCase();
    final level = (personalization.skillLevel ?? '').toLowerCase();
    final position = (personalization.position ?? '').toLowerCase();

    for (final w in weak) {
      if (_categoryMatchesWeakness(drill.category, w)) score += 12;
      if (drill.problem.toLowerCase().contains(w.split(' ').first)) score += 6;
      if (drill.title.toLowerCase().contains(w.split(' ').first)) score += 4;
    }

    for (final s in strong) {
      if (_categoryMatchesWeakness(drill.category, s)) score -= 3;
    }

    if (goal.contains('three') || goal.contains('range') || goal.contains('deep')) {
      if (drill.category == DrillCategory.range) score += 8;
    }
    if (goal.contains('consistency') || goal.contains('free throw')) {
      if (drill.category == DrillCategory.consistency) score += 6;
    }
    if (goal.contains('release') || goal.contains('quicker')) {
      if (drill.category == DrillCategory.release) score += 8;
    }

    if (level.contains('beginner') && drill.difficulty == 'Beginner') {
      score += 4;
    } else if (level.contains('advanced') || level.contains('elite')) {
      if (drill.difficulty == 'Advanced') score += 3;
    }

    if (position.contains('guard') &&
        (drill.category == DrillCategory.release ||
            drill.category == DrillCategory.range)) {
      score += 2;
    }

    if (personalization.releaseImproving &&
        drill.category == DrillCategory.release) {
      // Still reinforce, but nudge toward next weakness.
      score += 1;
    }

    // Recent low scores → consistency volume.
    final avg = personalization.averageScore;
    if (avg != null && avg < 70 && drill.category == DrillCategory.consistency) {
      score += 5;
    }

    return score;
  }

  static bool _categoryMatchesWeakness(DrillCategory category, String weakness) {
    final w = weakness.toLowerCase();
    return switch (category) {
      DrillCategory.release =>
        w.contains('release') || w.contains('timing') || w.contains('point'),
      DrillCategory.balance =>
        w.contains('balance') || w.contains('stance') || w.contains('feet'),
      DrillCategory.range => w.contains('range') || w.contains('arc'),
      DrillCategory.consistency =>
        w.contains('consist') || w.contains('knee'),
      DrillCategory.elbow => w.contains('elbow') || w.contains('alignment'),
      DrillCategory.followThrough =>
        w.contains('follow') || w.contains('wrist'),
    };
  }

  /// Build a 15 / 30 / 60 minute workout.
  static TrainingWorkout buildWorkout({
    required AiCoachPersonalization personalization,
    required int minutes,
  }) {
    final clamped = minutes <= 15
        ? 15
        : minutes <= 30
            ? 30
            : 60;
    final focus = personalization.weaknesses.isNotEmpty
        ? personalization.weaknesses.first
        : 'release timing';
    final ranked = personalizedDrills(personalization, limit: 8);

    final warmup = <TrainingDrill>[
      TrainingDrill(
        id: 'warmup_form',
        title: 'Form Activation',
        category: DrillCategory.consistency,
        durationMinutes: clamped == 15 ? 3 : 5,
        difficulty: 'Beginner',
        problem: 'Cold start',
        instructions: [
          'Bodyweight squats × 10',
          'Arm circles and wrist rolls',
          'Close-range form shots — perfect makes only',
        ],
        reps: clamped == 15 ? '3 minutes' : '5 minutes',
        focusCue: 'Wake up the legs',
      ),
    ];

    final cooldown = <TrainingDrill>[
      TrainingDrill(
        id: 'cooldown_ft',
        title: 'Free Throw Cool Down',
        category: DrillCategory.consistency,
        durationMinutes: clamped == 15 ? 2 : 4,
        difficulty: 'Beginner',
        problem: 'End under fatigue',
        instructions: [
          'Same free-throw routine every rep',
          'Hold follow-through until the ball lands',
          'Leave only after a make-based ladder or 8/10',
        ],
        reps: clamped == 60 ? '15 free throws' : '10 free throws',
        focusCue: 'Routine under fatigue',
      ),
    ];

    final budget = clamped -
        warmup.first.durationMinutes -
        cooldown.first.durationMinutes;
    final main = <TrainingDrill>[];
    var used = 0;
    for (final drill in ranked) {
      if (used + drill.durationMinutes > budget + 2) continue;
      main.add(drill);
      used += drill.durationMinutes;
      if (clamped == 15 && main.isNotEmpty) break;
      if (clamped == 30 && main.length >= 2) break;
      if (clamped == 60 && main.length >= 3) break;
    }

    if (main.isEmpty) {
      main.add(primaryAiDrill(personalization));
    }

    final level = personalization.skillLevel ?? 'your level';
    final summary =
        'Built for a $level shooter focusing on $focus. '
        '${personalization.releaseImproving ? 'Your release timing improved — ' : ''}'
        '${personalization.weaknesses.length >= 2 ? 'today also protects ${personalization.weaknesses[1]}.' : 'lock in clean reps before adding volume.'}';

    return TrainingWorkout(
      title: '$clamped-Minute $focus Workout',
      totalMinutes: clamped,
      focus: focus,
      warmup: warmup,
      mainDrills: main,
      cooldown: cooldown,
      summary: summary,
    );
  }

  /// Coach reply for "What should I practice today?"
  static String practiceTodayReply(AiCoachPersonalization personalization) {
    final workout = buildWorkout(
      personalization: personalization,
      minutes: 30,
    );
    final primary = primaryAiDrill(personalization);
    final weak = personalization.weaknesses;
    final strong = personalization.strengths;

    final buf = StringBuffer();
    if (personalization.displayName != null &&
        personalization.displayName!.isNotEmpty) {
      buf.writeln('Hey ${personalization.displayName!.split(' ').first},');
      buf.writeln();
    }

    if (!personalization.hasAnalyses) {
      buf.writeln(
        'You do not have shot analyses yet, so today starts with a form foundation.',
      );
      buf.writeln();
      buf.writeln('### Today\'s focus: Release Timing');
      buf.writeln();
      buf.writeln('**${primary.title}** · ${primary.durationLabel}');
      buf.writeln();
      for (var i = 0; i < primary.instructions.length; i++) {
        buf.writeln('${i + 1}. ${primary.instructions[i]}');
      }
      buf.writeln();
      buf.writeln('Reps: ${primary.reps}');
      buf.writeln();
      buf.writeln('Analyze a shot after practice so tomorrow\'s plan is personal.');
      return buf.toString();
    }

    if (personalization.releaseImproving &&
        weak.any((w) => w.toLowerCase().contains('elbow'))) {
      buf.writeln(
        'Your release timing improved, but your elbow alignment dropped. '
        'Today\'s workout focuses on elbow positioning.',
      );
    } else if (weak.isNotEmpty && strong.isNotEmpty) {
      buf.writeln(
        '**${strong.first}** is holding up. The priority today is **${weak.first}**.',
      );
    } else if (weak.isNotEmpty) {
      buf.writeln('Today we attack your biggest weakness: **${weak.first}**.');
    } else {
      buf.writeln('Today is about locking in consistency at game speed.');
    }

    buf.writeln();
    buf.writeln('### AI Drill: ${primary.title}');
    buf.writeln();
    buf.writeln('**Problem:** ${primary.problem}');
    buf.writeln('**Duration:** ${primary.durationLabel}');
    buf.writeln();
    buf.writeln('**Instructions**');
    for (var i = 0; i < primary.instructions.length; i++) {
      buf.writeln('${i + 1}. ${primary.instructions[i]}');
    }
    buf.writeln();
    buf.writeln('**Reps:** ${primary.reps}');
    if (primary.focusCue != null) {
      buf.writeln();
      buf.writeln('Cue: *"${primary.focusCue}"*');
    }
    buf.writeln();
    buf.writeln('### Full ${workout.totalMinutes}-minute plan');
    buf.writeln(workout.summary);
    buf.writeln();
    buf.writeln('Open **Drills** to run the full warmup → main → cool down builder.');
    return buf.toString();
  }
}
