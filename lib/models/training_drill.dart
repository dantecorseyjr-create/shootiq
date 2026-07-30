/// Drill category used by the AI training library.
enum DrillCategory {
  release,
  balance,
  range,
  consistency,
  elbow,
  followThrough;

  String get label => switch (this) {
        DrillCategory.release => 'Release Drills',
        DrillCategory.balance => 'Balance Drills',
        DrillCategory.range => 'Range Drills',
        DrillCategory.consistency => 'Consistency Drills',
        DrillCategory.elbow => 'Elbow Drills',
        DrillCategory.followThrough => 'Follow-Through Drills',
      };

  String get shortLabel => switch (this) {
        DrillCategory.release => 'Release',
        DrillCategory.balance => 'Balance',
        DrillCategory.range => 'Range',
        DrillCategory.consistency => 'Consistency',
        DrillCategory.elbow => 'Elbow',
        DrillCategory.followThrough => 'Follow Through',
      };
}

/// A single AI-generated or catalog basketball drill.
class TrainingDrill {
  const TrainingDrill({
    required this.id,
    required this.title,
    required this.category,
    required this.durationMinutes,
    required this.difficulty,
    required this.problem,
    required this.instructions,
    required this.reps,
    this.focusCue,
    this.sets,
  });

  final String id;
  final String title;
  final DrillCategory category;
  final int durationMinutes;
  final String difficulty;
  final String problem;
  final List<String> instructions;
  final String reps;
  final String? focusCue;
  final int? sets;

  String get durationLabel => '$durationMinutes min';
}

/// A timed workout assembled from warmup + main drills + cooldown.
class TrainingWorkout {
  const TrainingWorkout({
    required this.title,
    required this.totalMinutes,
    required this.focus,
    required this.warmup,
    required this.mainDrills,
    required this.cooldown,
    required this.summary,
  });

  final String title;
  final int totalMinutes;
  final String focus;
  final List<TrainingDrill> warmup;
  final List<TrainingDrill> mainDrills;
  final List<TrainingDrill> cooldown;
  final String summary;

  List<TrainingDrill> get allDrills => [
        ...warmup,
        ...mainDrills,
        ...cooldown,
      ];
}
