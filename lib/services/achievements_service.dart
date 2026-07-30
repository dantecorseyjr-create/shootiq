import 'package:shootiq/models/ai_coach_message.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/ai_coach_history_store.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/personal_baseline_service.dart';
import 'package:shootiq/services/shot_history_service.dart';

enum AchievementStatus { locked, inProgress, completed }

enum ChallengePeriod { daily, weekly, monthly }

/// Live achievements, challenges, streaks, and reminder notifications.
class AchievementsService {
  AchievementsService._();

  static Future<PlayerProgression> load() async {
    final shots = await ShotHistoryService.getUserShots(limit: 500);
    List<AiCoachMessage> coachMessages = const [];
    try {
      coachMessages = await AiCoachHistoryStore.load();
    } catch (_) {}
    return fromShots(shots, coachMessages: coachMessages);
  }

  static PlayerProgression fromShots(
    List<ShotRecord> allShots, {
    List<AiCoachMessage> coachMessages = const [],
  }) {
    final sorted = [...allShots]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final streak = computeStreak(sorted);
    final achievements = _buildAchievements(sorted, streak);
    final challenges = _buildChallenges(sorted, coachMessages);
    final reminders = _buildReminders(
      sorted: sorted,
      streak: streak,
      achievements: achievements,
      challenges: challenges,
    );

    final avg = sorted.isEmpty
        ? 0
        : _avg(sorted.map((s) => s.overallScore));
    final best = sorted.isEmpty
        ? 0
        : sorted.map((s) => s.overallScore).reduce((a, b) => a > b ? a : b);

    return PlayerProgression(
      shotsAnalyzed: sorted.length,
      averageScore: avg,
      bestScore: best,
      streak: streak,
      achievements: achievements,
      challenges: challenges,
      reminders: reminders,
      goals: _buildGoals(sorted, achievements, challenges),
    );
  }

  static Future<void> syncCache(
    PlayerProgression progression, {
    int? lastScore,
  }) async {
    await OnboardingService.setCurrentStreakDays(progression.streak.currentDays);
    await OnboardingService.setLongestStreakDays(progression.streak.longestDays);
    if (lastScore != null) {
      await OnboardingService.setLastScore(lastScore);
    }
  }

  static StreakInfo computeStreak(List<ShotRecord> chronological) {
    if (chronological.isEmpty) {
      return const StreakInfo(
        currentDays: 0,
        longestDays: 0,
        lastTrainingDate: null,
      );
    }

    final daySet = chronological
        .map(
          (s) => DateTime(
            s.createdAt.year,
            s.createdAt.month,
            s.createdAt.day,
          ),
        )
        .toSet();
    final days = daySet.toList()..sort();

    final lastTraining = days.last;
    final longest = _longestConsecutiveDays(days);
    final current = _currentStreakDays(days);

    return StreakInfo(
      currentDays: current,
      longestDays: longest,
      lastTrainingDate: lastTraining,
    );
  }

  static List<AchievementBadge> _buildAchievements(
    List<ShotRecord> sorted,
    StreakInfo streak,
  ) {
    final total = sorted.length;
    final best = total == 0
        ? 0
        : sorted.map((s) => s.overallScore).reduce((a, b) => a > b ? a : b);
    final trainingDays = _uniqueTrainingDays(sorted).length;
    final baselineAvg = _baselineAverage(sorted);
    final currentAvg =
        total == 0 ? 0 : _avg(sorted.map((s) => s.overallScore));
    final improvedPoints =
        baselineAvg == null ? 0 : (currentAvg - baselineAvg).clamp(0, 999);
    final eliteDays = _eliteAverageDays(sorted);

    return [
      _badge(
        id: 'first_analysis',
        emoji: '🏆',
        title: 'First Analysis',
        description: 'Complete your first shot analysis',
        current: total.clamp(0, 1),
        target: 1,
        unit: 'shot',
      ),
      _badge(
        id: 'streak_7',
        emoji: '🔥',
        title: '7-Day Streak',
        description: 'Practice every day for 7 days',
        current: streak.currentDays.clamp(0, 7),
        target: 7,
        unit: 'days',
        // Unlock permanently once longest streak ever hit 7.
        forceCompleted: streak.longestDays >= 7,
        displayCurrent: streak.longestDays >= 7
            ? 7
            : streak.currentDays.clamp(0, 7),
      ),
      _badge(
        id: 'challenge_30',
        emoji: '📅',
        title: '30-Day Challenge',
        description: 'Complete 30 days of training',
        current: trainingDays.clamp(0, 30),
        target: 30,
        unit: 'days',
        forceCompleted: trainingDays >= 30,
      ),
      _badge(
        id: 'score_90',
        emoji: '🎯',
        title: 'Score Above 90',
        description: 'Receive a score of 90 or higher',
        current: best >= 90 ? 1 : (best > 0 ? best : 0),
        target: best >= 90 ? 1 : 90,
        unit: best >= 90 ? 'shot' : 'score',
        forceCompleted: best >= 90,
        displayCurrent: best >= 90 ? 1 : best,
        displayTarget: best >= 90 ? 1 : 90,
      ),
      _badge(
        id: 'improved_10',
        emoji: '📈',
        title: 'Improved 10 Points',
        description: 'Raise your average 10 points from baseline',
        current: improvedPoints.clamp(0, 10),
        target: 10,
        unit: 'points',
        forceCompleted: improvedPoints >= 10,
      ),
      _badge(
        id: 'shots_100',
        emoji: '💯',
        title: '100 Shots Analyzed',
        description: 'Analyze 100 shots',
        current: total.clamp(0, 100),
        target: 100,
        unit: 'shots',
      ),
      _badge(
        id: 'shots_500',
        emoji: '🚀',
        title: '500 Shots Analyzed',
        description: 'Analyze 500 shots',
        current: total.clamp(0, 500),
        target: 500,
        unit: 'shots',
      ),
      _badge(
        id: 'elite_shooter',
        emoji: '👑',
        title: 'Elite Shooter',
        description: 'Maintain a 90+ average for 30 days',
        current: eliteDays.clamp(0, 30),
        target: 30,
        unit: 'days',
        forceCompleted: eliteDays >= 30,
      ),
    ];
  }

  static List<ChallengeItem> _buildChallenges(
    List<ShotRecord> sorted,
    List<AiCoachMessage> coachMessages,
  ) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todayShots =
        sorted.where((s) => !s.createdAt.isBefore(todayStart)).toList();
    final weekShots =
        sorted.where((s) => !s.createdAt.isBefore(weekStart)).toList();
    final monthDays = _uniqueTrainingDays(
      sorted.where((s) => !s.createdAt.isBefore(monthStart)).toList(),
    ).length;

    final releaseToday = todayShots.isEmpty
        ? 0
        : _avg(todayShots.map((s) => s.releasePoint));
    final releasePrior = () {
      final prior = sorted.where((s) => s.createdAt.isBefore(todayStart)).toList();
      if (prior.isEmpty) return releaseToday;
      final recent = prior.length > 10 ? prior.sublist(prior.length - 10) : prior;
      return _avg(recent.map((s) => s.releasePoint));
    }();
    final releaseImproved = releaseToday > releasePrior
        ? 1
        : (todayShots.isEmpty ? 0 : 0);

    final weekAvg = weekShots.isEmpty
        ? 0
        : _avg(weekShots.map((s) => s.overallScore));
    final priorWeekShots = sorted
        .where(
          (s) =>
              !s.createdAt.isBefore(weekStart.subtract(const Duration(days: 7))) &&
              s.createdAt.isBefore(weekStart),
        )
        .toList();
    final priorWeekAvg = priorWeekShots.isEmpty
        ? weekAvg
        : _avg(priorWeekShots.map((s) => s.overallScore));
    final weekScoreGain = (weekAvg - priorWeekAvg).clamp(0, 99);

    final workoutsThisWeek = _workoutCount(coachMessages, since: weekStart);

    return [
      ChallengeItem(
        id: 'daily_analyze_5',
        period: ChallengePeriod.daily,
        title: 'Analyze 5 shots today',
        description: 'Build reps with five analyzed takes.',
        current: todayShots.length.clamp(0, 5),
        target: 5,
        unit: 'shots',
        reward: '⚡ Daily Grinder Badge',
      ),
      ChallengeItem(
        id: 'daily_practice_20',
        period: ChallengePeriod.daily,
        title: 'Complete 20 practice shots',
        description: 'Hit a high-volume practice day.',
        current: todayShots.length.clamp(0, 20),
        target: 20,
        unit: 'shots',
        reward: '🏀 Volume Shooter Badge',
      ),
      ChallengeItem(
        id: 'daily_release',
        period: ChallengePeriod.daily,
        title: 'Improve release timing',
        description: 'Beat your recent release timing average today.',
        current: releaseImproved,
        target: 1,
        unit: 'goal',
        reward: '⏱️ Quick Release Badge',
      ),
      ChallengeItem(
        id: 'weekly_analyze_25',
        period: ChallengePeriod.weekly,
        title: 'Analyze 25 shots',
        description: 'Stack a full week of film study.',
        current: weekShots.length.clamp(0, 25),
        target: 25,
        unit: 'shots',
        reward: '🎬 Film Room Badge',
      ),
      ChallengeItem(
        id: 'weekly_score_plus_3',
        period: ChallengePeriod.weekly,
        title: 'Increase score by 3 points',
        description: 'Raise this week’s average vs last week.',
        current: weekScoreGain.clamp(0, 3),
        target: 3,
        unit: 'points',
        reward: '📈 Hot Hand Badge',
      ),
      ChallengeItem(
        id: 'weekly_workouts_3',
        period: ChallengePeriod.weekly,
        title: 'Complete 3 AI workouts',
        description: 'Generate and complete AI Coach workouts.',
        current: workoutsThisWeek.clamp(0, 3),
        target: 3,
        unit: 'workouts',
        reward: '🧠 Coach’s Choice Badge',
      ),
      ChallengeItem(
        id: 'monthly_30_day',
        period: ChallengePeriod.monthly,
        title: '30-Day Shooting Challenge',
        description: 'Train on 30 different days this month.',
        current: monthDays.clamp(0, 30),
        target: 30,
        unit: 'days',
        reward: '🔥 Consistency Badge',
      ),
    ];
  }

  static List<ProgressionReminder> _buildReminders({
    required List<ShotRecord> sorted,
    required StreakInfo streak,
    required List<AchievementBadge> achievements,
    required List<ChallengeItem> challenges,
  }) {
    final reminders = <ProgressionReminder>[];
    final trainedToday = streak.lastTrainingDate != null &&
        _isSameDay(streak.lastTrainingDate!, DateTime.now());

    if (streak.currentDays > 0 && !trainedToday) {
      reminders.add(
        ProgressionReminder(
          id: 'streak_keep_alive',
          message:
              'Keep your ${streak.currentDays}-day streak alive. Analyze a shot today.',
          priority: 100,
        ),
      );
    } else if (streak.currentDays >= 3 && trainedToday) {
      reminders.add(
        ProgressionReminder(
          id: 'streak_strong',
          message:
              'Nice work — your ${streak.currentDays}-day streak is still burning.',
          priority: 40,
        ),
      );
    }

    for (final badge in achievements) {
      if (badge.status == AchievementStatus.completed) continue;
      final remaining = badge.target - badge.current;
      if (remaining <= 0) continue;
      if (badge.id == 'shots_100' && remaining <= 15) {
        reminders.add(
          ProgressionReminder(
            id: 'near_100',
            message:
                "You're $remaining shot${remaining == 1 ? '' : 's'} away from unlocking 100 Shot Master.",
            priority: 90,
          ),
        );
      } else if (badge.id == 'shots_500' && remaining <= 40) {
        reminders.add(
          ProgressionReminder(
            id: 'near_500',
            message:
                "You're $remaining shots away from the 500 Shots Analyzed badge.",
            priority: 70,
          ),
        );
      } else if (badge.id == 'streak_7' &&
          badge.current >= 4 &&
          badge.current < 7) {
        reminders.add(
          ProgressionReminder(
            id: 'near_streak_7',
            message:
                '${7 - badge.current} more day${7 - badge.current == 1 ? '' : 's'} to unlock 7-Day Streak.',
            priority: 85,
          ),
        );
      } else if (badge.id == 'score_90' &&
          badge.current >= 80 &&
          badge.current < 90) {
        reminders.add(
          ProgressionReminder(
            id: 'near_90',
            message:
                'You are ${90 - badge.current} points from a 90+ score unlock.',
            priority: 75,
          ),
        );
      }
    }

    final daily = challenges
        .where((c) => c.period == ChallengePeriod.daily && !c.completed)
        .toList();
    if (daily.isNotEmpty) {
      final top = daily.first;
      final left = top.target - top.current;
      if (left > 0) {
        reminders.add(
          ProgressionReminder(
            id: 'daily_challenge',
            message:
                'Daily challenge: ${top.current}/${top.target} ${top.unit}. $left to go.',
            priority: 60,
          ),
        );
      }
    }

    for (final monthly in challenges) {
      if (monthly.id != 'monthly_30_day') continue;
      if (!monthly.completed && monthly.current > 0) {
        reminders.add(
          ProgressionReminder(
            id: 'monthly_challenge',
            message:
                '30-Day Challenge: ${monthly.current}/30 days complete (${monthly.percentComplete}%).',
            priority: 50,
          ),
        );
      }
      break;
    }

    if (sorted.isEmpty) {
      reminders.add(
        const ProgressionReminder(
          id: 'start',
          message: 'Analyze your first shot to start unlocking achievements.',
          priority: 110,
        ),
      );
    }

    reminders.sort((a, b) => b.priority.compareTo(a.priority));
    final seen = <String>{};
    return reminders.where((r) => seen.add(r.id)).take(3).toList();
  }

  static List<ProgressionGoal> _buildGoals(
    List<ShotRecord> sorted,
    List<AchievementBadge> achievements,
    List<ChallengeItem> challenges,
  ) {
    final avg =
        sorted.isEmpty ? 0 : _avg(sorted.map((s) => s.overallScore));
    final goals = <ProgressionGoal>[
      ProgressionGoal(
        title: 'Reach 90 Average Score',
        current: avg,
        target: 90,
        unit: 'score',
      ),
      ProgressionGoal(
        title: 'Analyze 100 Shots',
        current: sorted.length.clamp(0, 100),
        target: 100,
        unit: 'shots',
      ),
    ];

    final selected = OnboardingService.selectedGoal;
    if (selected != null && selected.trim().isNotEmpty) {
      goals.insert(
        0,
        ProgressionGoal(
          title: selected,
          current: avg,
          target: 90,
          unit: 'score',
          isPrimary: true,
        ),
      );
    }

    ChallengeItem? monthly;
    for (final c in challenges) {
      if (c.id == 'monthly_30_day') {
        monthly = c;
        break;
      }
    }
    if (monthly != null) {
      goals.add(
        ProgressionGoal(
          title: monthly.title,
          current: monthly.current,
          target: monthly.target,
          unit: monthly.unit,
        ),
      );
    }

    final near = achievements
        .where((a) => a.status == AchievementStatus.inProgress)
        .toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    if (near.isNotEmpty) {
      final a = near.first;
      goals.add(
        ProgressionGoal(
          title: 'Unlock ${a.title}',
          current: a.current,
          target: a.target,
          unit: a.unit,
        ),
      );
    }

    return goals;
  }

  static AchievementBadge _badge({
    required String id,
    required String emoji,
    required String title,
    required String description,
    required int current,
    required int target,
    required String unit,
    bool forceCompleted = false,
    int? displayCurrent,
    int? displayTarget,
  }) {
    final c = displayCurrent ?? current;
    final t = displayTarget ?? target;
    final completed = forceCompleted || c >= t;
    final status = completed
        ? AchievementStatus.completed
        : c <= 0
            ? AchievementStatus.locked
            : AchievementStatus.inProgress;
    return AchievementBadge(
      id: id,
      emoji: emoji,
      title: title,
      description: description,
      current: c.clamp(0, t),
      target: t,
      unit: unit,
      status: status,
    );
  }

  static int? _baselineAverage(List<ShotRecord> sorted) {
    if (sorted.length < PersonalBaselineService.minSamples) return null;
    final first =
        sorted.take(PersonalBaselineService.minSamples).toList();
    return _avg(first.map((s) => s.overallScore));
  }

  /// Consecutive recent days where that day's average score was >= 90.
  static int _eliteAverageDays(List<ShotRecord> sorted) {
    if (sorted.isEmpty) return 0;
    final byDay = <DateTime, List<int>>{};
    for (final shot in sorted) {
      final day = DateTime(
        shot.createdAt.year,
        shot.createdAt.month,
        shot.createdAt.day,
      );
      byDay.putIfAbsent(day, () => <int>[]).add(shot.overallScore);
    }
    final days = byDay.keys.toList()..sort();
    var cursor = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (!byDay.containsKey(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (byDay.containsKey(cursor)) {
      final avg = _avg(byDay[cursor]!);
      if (avg < 90) break;
      count += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    // Also track best historical elite run for permanent unlock progress.
    var best = count;
    var run = 0;
    for (final day in days) {
      final avg = _avg(byDay[day]!);
      if (avg >= 90) {
        run += 1;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  static Set<DateTime> _uniqueTrainingDays(List<ShotRecord> shots) {
    return shots
        .map(
          (s) => DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day),
        )
        .toSet();
  }

  static int _currentStreakDays(List<DateTime> sortedDays) {
    if (sortedDays.isEmpty) return 0;
    var cursor = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final daySet = sortedDays.toSet();
    if (!daySet.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!daySet.contains(cursor)) return 0;
    }
    var streak = 0;
    while (daySet.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestConsecutiveDays(List<DateTime> sortedDays) {
    if (sortedDays.isEmpty) return 0;
    var best = 1;
    var run = 1;
    for (var i = 1; i < sortedDays.length; i++) {
      final prev = sortedDays[i - 1];
      final cur = sortedDays[i];
      if (cur.difference(prev).inDays == 1) {
        run += 1;
        if (run > best) best = run;
      } else if (cur != prev) {
        run = 1;
      }
    }
    return best;
  }

  static int _workoutCount(
    List<AiCoachMessage> messages, {
    required DateTime since,
  }) {
    var count = 0;
    for (final message in messages) {
      if (message.createdAt.isBefore(since)) continue;
      final text = message.text.toLowerCase();
      final isWorkout = text.contains('workout') ||
          text.contains('drill circuit') ||
          (message.isAssistant &&
              text.contains('###') &&
              text.contains('drill'));
      if (message.isUser &&
          (text.contains('create workout') || text == 'workout')) {
        count += 1;
      } else if (message.isAssistant && isWorkout) {
        // Count distinct assistant workout deliveries.
        count += 1;
      }
    }
    return count;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _avg(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return (list.reduce((a, b) => a + b) / list.length).round();
  }
}

class StreakInfo {
  const StreakInfo({
    required this.currentDays,
    required this.longestDays,
    required this.lastTrainingDate,
  });

  final int currentDays;
  final int longestDays;
  final DateTime? lastTrainingDate;

  String get lastTrainingLabel {
    final d = lastTrainingDate;
    if (d == null) return 'Never';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${d.month}/${d.day}/${d.year}';
  }
}

class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
    required this.unit,
    required this.status,
  });

  final String id;
  final String emoji;
  final String title;
  final String description;
  final int current;
  final int target;
  final String unit;
  final AchievementStatus status;

  bool get completed => status == AchievementStatus.completed;
  bool get locked => status == AchievementStatus.locked;
  bool get inProgress => status == AchievementStatus.inProgress;

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  int get percentComplete => (progress * 100).round();

  String get statusLabel => switch (status) {
        AchievementStatus.locked => 'Locked',
        AchievementStatus.inProgress => 'In Progress',
        AchievementStatus.completed => 'Completed',
      };

  String get progressLabel => '$current / $target $unit';
}

class ChallengeItem {
  const ChallengeItem({
    required this.id,
    required this.period,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
    required this.unit,
    required this.reward,
  });

  final String id;
  final ChallengePeriod period;
  final String title;
  final String description;
  final int current;
  final int target;
  final String unit;
  final String reward;

  bool get completed => current >= target;

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  int get percentComplete => (progress * 100).round();

  String get periodLabel => switch (period) {
        ChallengePeriod.daily => 'Daily',
        ChallengePeriod.weekly => 'Weekly',
        ChallengePeriod.monthly => 'Monthly',
      };

  String get progressLabel => '$current/$target $unit complete';
}

class ProgressionReminder {
  const ProgressionReminder({
    required this.id,
    required this.message,
    required this.priority,
  });

  final String id;
  final String message;
  final int priority;
}

class ProgressionGoal {
  const ProgressionGoal({
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

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  bool get completed => current >= target;
}

class PlayerProgression {
  const PlayerProgression({
    required this.shotsAnalyzed,
    required this.averageScore,
    required this.bestScore,
    required this.streak,
    required this.achievements,
    required this.challenges,
    required this.reminders,
    required this.goals,
  });

  final int shotsAnalyzed;
  final int averageScore;
  final int bestScore;
  final StreakInfo streak;
  final List<AchievementBadge> achievements;
  final List<ChallengeItem> challenges;
  final List<ProgressionReminder> reminders;
  final List<ProgressionGoal> goals;

  List<ChallengeItem> get dailyChallenges =>
      challenges.where((c) => c.period == ChallengePeriod.daily).toList();

  List<ChallengeItem> get weeklyChallenges =>
      challenges.where((c) => c.period == ChallengePeriod.weekly).toList();

  List<ChallengeItem> get monthlyChallenges =>
      challenges.where((c) => c.period == ChallengePeriod.monthly).toList();

  List<AchievementBadge> get completedAchievements =>
      achievements.where((a) => a.completed).toList();
}
