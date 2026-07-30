import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/training_drill.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/ai_coach_personalization.dart';
import 'package:shootiq/services/app_preferences_service.dart';
import 'package:shootiq/services/training_drills_service.dart';
import 'package:shootiq/widgets/empty_state.dart';

/// Personalized AI training drills + workout builder.
class DrillsPage extends StatefulWidget {
  const DrillsPage({super.key});

  @override
  State<DrillsPage> createState() => _DrillsPageState();
}

class _DrillsPageState extends State<DrillsPage>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _staggerController;
  late final Animation<double> _fadeAnimation;

  AiCoachPersonalization _personalization = const AiCoachPersonalization();
  bool _loading = true;
  DrillCategory? _selectedCategory;
  int _workoutMinutes = 30;
  TrainingWorkout? _workout;
  TrainingDrill? _expandedDrill;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fadeController.forward();
    _staggerController.forward();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      AiCoachPersonalization.load(),
      AppPreferencesService.load(),
    ]);
    if (!mounted) return;
    final personalization = results[0] as AiCoachPersonalization;
    final prefs = results[1] as AppPreferences;
    setState(() {
      _personalization = personalization;
      _workoutMinutes = prefs.defaultWorkoutMinutes;
      _workout = TrainingDrillsService.buildWorkout(
        personalization: personalization,
        minutes: prefs.defaultWorkoutMinutes,
      );
      _loading = false;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  Future<void> _rebuildWorkout(int minutes) async {
    setState(() {
      _workoutMinutes = minutes;
      _workout = TrainingDrillsService.buildWorkout(
        personalization: _personalization,
        minutes: minutes,
      );
    });
    final prefs = await AppPreferencesService.load();
    await AppPreferencesService.save(
      prefs.copyWith(defaultWorkoutMinutes: minutes),
    );
  }

  Widget _staggered({
    required double start,
    required double end,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      ),
    );
  }

  List<TrainingDrill> get _visibleDrills {
    if (_selectedCategory != null) {
      return TrainingDrillsService.drillsForCategory(_selectedCategory!);
    }
    return TrainingDrillsService.personalizedDrills(
      _personalization,
      limit: 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = _loading
        ? null
        : TrainingDrillsService.primaryAiDrill(_personalization);
    final focus = _personalization.weaknesses.isNotEmpty
        ? _personalization.weaknesses.first
        : 'Release Timing';

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: ShootIQTheme.basketballOrange,
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    if (context.canPop()) {
                                      context.pop();
                                    } else {
                                      context.go(AppRoutes.aiCoach);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    color: ShootIQTheme.textPrimary,
                                  ),
                                ),
                                const Expanded(
                                  child: Text(
                                    'AI Training Drills',
                                    style: TextStyle(
                                      color: ShootIQTheme.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _personalization.hasAnalyses
                                  ? 'Personalized from your latest analysis, weaknesses, and goals.'
                                  : 'Analyze shots to unlock fully personalized workouts.',
                              style: const TextStyle(
                                color: ShootIQTheme.textSecondary,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (primary != null)
                              _staggered(
                                start: 0.0,
                                end: 0.3,
                                child: _AiDrillHero(
                                  drill: primary,
                                  focus: focus,
                                  onOpen: () => setState(
                                    () => _expandedDrill = primary,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 28),
                            _staggered(
                              start: 0.1,
                              end: 0.4,
                              child: const Text(
                                'Workout Builder',
                                style: TextStyle(
                                  color: ShootIQTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _staggered(
                              start: 0.14,
                              end: 0.45,
                              child: _WorkoutDurationPicker(
                                selected: _workoutMinutes,
                                onSelected: _rebuildWorkout,
                              ),
                            ),
                            if (_workout != null) ...[
                              const SizedBox(height: 14),
                              _staggered(
                                start: 0.2,
                                end: 0.52,
                                child: _WorkoutCard(workout: _workout!),
                              ),
                            ],
                            const SizedBox(height: 28),
                            _staggered(
                              start: 0.28,
                              end: 0.58,
                              child: const Text(
                                'Drill Categories',
                                style: TextStyle(
                                  color: ShootIQTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _staggered(
                              start: 0.32,
                              end: 0.62,
                              child: _CategoryRow(
                                selected: _selectedCategory,
                                onSelected: (cat) {
                                  setState(() {
                                    _selectedCategory =
                                        _selectedCategory == cat ? null : cat;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 18),
                            _staggered(
                              start: 0.38,
                              end: 0.7,
                              child: Text(
                                _selectedCategory == null
                                    ? 'Recommended For You'
                                    : _selectedCategory!.label,
                                style: const TextStyle(
                                  color: ShootIQTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_visibleDrills.isEmpty)
                              const EmptyState(
                                icon: Icons.fitness_center_rounded,
                                title: 'No drills in this category',
                                message:
                                    'Pick another category or rebuild your workout.',
                              )
                            else
                              ..._visibleDrills.map(
                                (drill) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _DrillCard(
                                    drill: drill,
                                    expanded: _expandedDrill?.id == drill.id,
                                    onTap: () {
                                      setState(() {
                                        _expandedDrill =
                                            _expandedDrill?.id == drill.id
                                                ? null
                                                : drill;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => context.push(AppRoutes.aiCoach),
                              icon: const Icon(Icons.psychology_rounded),
                              label: const Text('Ask AI Coach what to practice'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ShootIQTheme.basketballOrange,
                                side: BorderSide(
                                  color: ShootIQTheme.basketballOrange
                                      .withValues(alpha: 0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AiDrillHero extends StatelessWidget {
  const _AiDrillHero({
    required this.drill,
    required this.focus,
    required this.onOpen,
  });

  final TrainingDrill drill;
  final String focus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ShootIQTheme.basketballOrange.withValues(alpha: 0.28),
              ShootIQTheme.cardBackground,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ShootIQTheme.basketballOrange.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TODAY\'S AI DRILL',
              style: TextStyle(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.95),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Problem: $focus',
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              drill.title,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetaChip(icon: Icons.timer_outlined, label: drill.durationLabel),
                const SizedBox(width: 8),
                _MetaChip(icon: Icons.signal_cellular_alt_rounded, label: drill.difficulty),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              drill.reps,
              style: const TextStyle(
                color: ShootIQTheme.basketballOrange,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ShootIQTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutDurationPicker extends StatelessWidget {
  const _WorkoutDurationPicker({
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final minutes in const [15, 30, 60]) ...[
          Expanded(
            child: InkWell(
              onTap: () => onSelected(minutes),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected == minutes
                      ? ShootIQTheme.basketballOrange
                      : ShootIQTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected == minutes
                        ? ShootIQTheme.basketballOrange
                        : ShootIQTheme.cardBorder,
                  ),
                ),
                child: Text(
                  '$minutes min',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected == minutes
                        ? Colors.white
                        : ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          if (minutes != 60) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout});
  final TrainingWorkout workout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workout.title,
            style: const TextStyle(
              color: ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            workout.summary,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _WorkoutSection(
            title: 'Warmup',
            drills: workout.warmup,
            color: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 12),
          _WorkoutSection(
            title: 'Main Drills',
            drills: workout.mainDrills,
            color: ShootIQTheme.basketballOrange,
          ),
          const SizedBox(height: 12),
          _WorkoutSection(
            title: 'Cool Down',
            drills: workout.cooldown,
            color: const Color(0xFF60A5FA),
          ),
        ],
      ),
    );
  }
}

class _WorkoutSection extends StatelessWidget {
  const _WorkoutSection({
    required this.title,
    required this.drills,
    required this.color,
  });

  final String title;
  final List<TrainingDrill> drills;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        for (final drill in drills)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    drill.title,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  drill.durationLabel,
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.selected,
    required this.onSelected,
  });

  final DrillCategory? selected;
  final ValueChanged<DrillCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final cats = TrainingDrillsService.primaryCategories;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < cats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            InkWell(
              onTap: () => onSelected(cats[i]),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected == cats[i]
                      ? ShootIQTheme.basketballOrange.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected == cats[i]
                        ? ShootIQTheme.basketballOrange
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  cats[i].shortLabel,
                  style: TextStyle(
                    color: selected == cats[i]
                        ? ShootIQTheme.basketballOrange
                        : ShootIQTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrillCard extends StatelessWidget {
  const _DrillCard({
    required this.drill,
    required this.expanded,
    required this.onTap,
  });

  final TrainingDrill drill;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShootIQTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: expanded
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.5)
                : ShootIQTheme.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    drill.title,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  drill.durationLabel,
                  style: const TextStyle(
                    color: ShootIQTheme.basketballOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Problem: ${drill.problem}',
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 14),
              const Text(
                'Instructions',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < drill.instructions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${i + 1}. ${drill.instructions[i]}',
                    style: const TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Reps: ${drill.reps}',
                style: const TextStyle(
                  color: ShootIQTheme.basketballOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (drill.focusCue != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Cue: "${drill.focusCue}"',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
