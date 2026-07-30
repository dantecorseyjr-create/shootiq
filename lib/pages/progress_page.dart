import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/achievements_service.dart';
import 'package:shootiq/services/progress_analytics_service.dart';

/// Player development dashboard powered by historical shot analyses.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with SingleTickerProviderStateMixin {
  ProgressSnapshot? _snapshot;
  bool _loading = true;
  ProgressRange _range = ProgressRange.days30;

  late final AnimationController _enterController;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await ProgressAnalyticsService.load(range: _range);
    await snap.syncProfileCache();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
    _enterController.forward(from: 0);
  }

  Future<void> _setRange(ProgressRange range) async {
    setState(() => _range = range);
    final all = _snapshot?.allShots;
    final baseline = _snapshot?.baselinePayload;
    if (all == null) {
      await _load();
      return;
    }
    setState(() {
      _snapshot = ProgressAnalyticsService.fromShots(
        all,
        range: range,
        baseline: baseline,
        session: _snapshot?.session,
        progression: _snapshot?.progression,
      );
    });
  }

  Widget _stagger({
    required double start,
    required double end,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _enterController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _enterController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: SafeArea(
        child: RefreshIndicator(
          color: ShootIQTheme.basketballOrange,
          onRefresh: _load,
          child: _loading
              ? ListView(
                  children: const [
                    SizedBox(height: 180),
                    Center(
                      child: CircularProgressIndicator(
                        color: ShootIQTheme.basketballOrange,
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  children: [
                    _stagger(
                      start: 0.0,
                      end: 0.25,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Progress',
                            style: TextStyle(
                              color: ShootIQTheme.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your basketball development dashboard.',
                            style: TextStyle(
                              color: ShootIQTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (snap == null || snap.isEmpty)
                      _EmptyProgress(
                        onAnalyze: () => context.go(AppRoutes.analyze),
                      )
                    else ...[
                      _stagger(
                        start: 0.02,
                        end: 0.28,
                        child: _RangeChips(
                          selected: _range,
                          onSelected: _setRange,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _stagger(
                        start: 0.05,
                        end: 0.35,
                        child: _TrendStatsRow(stats: snap.trendStats),
                      ),
                      const SizedBox(height: 14),
                      _stagger(
                        start: 0.08,
                        end: 0.4,
                        child: const _SectionTitle(
                          'Average Shooting Score Over Time',
                        ),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.1,
                        end: 0.45,
                        child: _ScoreOverTimeChart(
                          points: snap.series(ProgressMetric.overall),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.14,
                        end: 0.5,
                        child: const _SectionTitle('Category Improvement'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.16,
                        end: 0.55,
                        child: _CategoryImprovementChart(
                          shots: snap.shotsInRange,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (snap.progression.reminders.isNotEmpty) ...[
                        _stagger(
                          start: 0.18,
                          end: 0.52,
                          child: _RemindersBanner(
                            reminders: snap.progression.reminders,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _stagger(
                        start: 0.2,
                        end: 0.55,
                        child: _PlayerImprovementCard(snapshot: snap),
                      ),
                      const SizedBox(height: 16),
                      _stagger(
                        start: 0.22,
                        end: 0.58,
                        child: _StreakCard(streak: snap.progression.streak),
                      ),
                      const SizedBox(height: 20),
                      _stagger(
                        start: 0.24,
                        end: 0.6,
                        child: const _SectionTitle('Category Progress'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.26,
                        end: 0.64,
                        child: _CategoryProgressList(
                          items: snap.categoryProgress,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.38,
                        end: 0.72,
                        child: const _SectionTitle('Personal Baseline'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.4,
                        end: 0.75,
                        child: _BaselineCard(compare: snap.baselineCompare),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.45,
                        end: 0.78,
                        child: const _SectionTitle('AI Insights'),
                      ),
                      const SizedBox(height: 10),
                      ...snap.aiInsights.asMap().entries.map(
                        (entry) => _stagger(
                          start: 0.48 + entry.key * 0.03,
                          end: 0.82,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _InsightCard(text: entry.value),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _stagger(
                        start: 0.55,
                        end: 0.85,
                        child: const _SectionTitle('Goals'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.58,
                        end: 0.88,
                        child: _GoalsProgressList(goals: snap.goals),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.6,
                        end: 0.86,
                        child: const _SectionTitle('Challenges'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.62,
                        end: 0.9,
                        child: _ChallengesSection(
                          challenges: snap.progression.challenges,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.66,
                        end: 0.92,
                        child: const _SectionTitle('Achievements'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.68,
                        end: 0.95,
                        child: _AchievementsSection(
                          achievements: snap.progression.achievements,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _stagger(
                        start: 0.72,
                        end: 0.96,
                        child: const _SectionTitle('Career Snapshot'),
                      ),
                      const SizedBox(height: 10),
                      _stagger(
                        start: 0.74,
                        end: 0.98,
                        child: _CareerSnapshot(stats: snap.profileStats),
                      ),
                      const SizedBox(height: 14),
                      _stagger(
                        start: 0.8,
                        end: 1.0,
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: snap.allShots.length < 2
                                ? null
                                : () => context.push(AppRoutes.sessionCompare),
                            icon: const Icon(Icons.compare_arrows_rounded),
                            label: const Text('Compare Shots'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ShootIQTheme.textPrimary,
                              side: BorderSide(
                                color: ShootIQTheme.surfaceElevated,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ShootIQTheme.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress({required this.onAnalyze});
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ShootIQTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.show_chart_rounded,
              size: 34,
              color: ShootIQTheme.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Complete your first shot analysis to see your progress.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAnalyze,
              style: ShootIQTheme.primaryButtonStyle(),
              child: const Text('Analyze My Shot'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerImprovementCard extends StatelessWidget {
  const _PlayerImprovementCard({required this.snapshot});
  final ProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot.currentAverageScore;
    final previous = snapshot.previousAverageScore;
    final delta = snapshot.improvementDelta;
    final hasDelta = previous != null && current != null;
    final deltaColor = !hasDelta
        ? ShootIQTheme.textSecondary
        : delta > 0
            ? const Color(0xFF22C55E)
            : delta < 0
                ? const Color(0xFFEF4444)
                : ShootIQTheme.textSecondary;
    final deltaLabel = !hasDelta
        ? 'Building history'
        : delta > 0
            ? '+$delta points ↑'
            : delta < 0
                ? '$delta points ↓'
                : 'No change';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShootIQTheme.surfaceElevated,
            ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: ShootIQTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Player Improvement',
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _ScoreBlock(
                  label: 'Current Average',
                  value: current == null ? '—' : '$current',
                  large: true,
                ),
              ),
              Expanded(
                child: _ScoreBlock(
                  label: 'Previous Average',
                  value: previous == null ? '—' : '$previous',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  delta > 0
                      ? Icons.trending_up_rounded
                      : delta < 0
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                  color: deltaColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Improvement: $deltaLabel',
                  style: TextStyle(
                    color: deltaColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.label,
    required this.value,
    this.large = false,
  });
  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: large ? 40 : 28,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _CategoryProgressList extends StatelessWidget {
  const _CategoryProgressList({required this.items});
  final List<CategoryProgress> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _MutedBox('Not enough category history yet.');
    }

    return Column(
      children: [
        for (final item in items) ...[
          _CategoryProgressTile(item: item),
          if (item != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CategoryProgressTile extends StatelessWidget {
  const _CategoryProgressTile({required this.item});
  final CategoryProgress item;

  @override
  Widget build(BuildContext context) {
    final positive = item.delta > 0;
    final negative = item.delta < 0;
    final deltaColor = positive
        ? const Color(0xFF22C55E)
        : negative
            ? const Color(0xFFEF4444)
            : ShootIQTheme.textSecondary;
    final deltaText = positive
        ? '+${item.delta}'
        : '${item.delta}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                deltaText,
                style: TextStyle(
                  color: deltaColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(label: 'Before', value: '${item.before}'),
              const SizedBox(width: 18),
              _MiniStat(label: 'Current', value: '${item.current}'),
              const Spacer(),
              SizedBox(
                width: 88,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (item.current / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: ShootIQTheme.cardBorder,
                    valueColor: AlwaysStoppedAnimation(
                      positive
                          ? ShootIQTheme.primaryBlue
                          : negative
                              ? ShootIQTheme.redAccent
                              : ShootIQTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.selected, required this.onSelected});
  final ProgressRange selected;
  final ValueChanged<ProgressRange> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ProgressRange value) {
      final active = selected == value;
      return ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onSelected(value),
        selectedColor: ShootIQTheme.primaryBlue.withValues(alpha: 0.14),
        labelStyle: TextStyle(
          color: active ? ShootIQTheme.primaryBlue : ShootIQTheme.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        side: BorderSide(
          color: active
              ? ShootIQTheme.primaryBlue
              : ShootIQTheme.cardBorder,
        ),
        backgroundColor: ShootIQTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('7 Days', ProgressRange.days7),
          const SizedBox(width: 8),
          chip('30 Days', ProgressRange.days30),
          const SizedBox(width: 8),
          chip('90 Days', ProgressRange.days90),
          const SizedBox(width: 8),
          chip('All Time', ProgressRange.allTime),
        ],
      ),
    );
  }
}

class _TrendStatsRow extends StatelessWidget {
  const _TrendStatsRow({required this.stats});
  final ProgressTrendStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TrendStatTile(
            label: 'Average Score',
            value: stats.shotsAnalyzed == 0 ? '—' : '${stats.averageScore}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TrendStatTile(
            label: 'Shots Analyzed',
            value: '${stats.shotsAnalyzed}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TrendStatTile(
            label: 'Consistency',
            value: stats.shotsAnalyzed == 0 ? '—' : '${stats.consistency}%',
          ),
        ),
      ],
    );
  }
}

class _TrendStatTile extends StatelessWidget {
  const _TrendStatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: ShootIQTheme.basketballOrange,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreOverTimeChart extends StatelessWidget {
  const _ScoreOverTimeChart({required this.points});
  final List<ProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    // Highlight the latest / peak session in red when it beats the prior point.
    final highlightIndex = spots.isEmpty
        ? -1
        : () {
            var peak = 0;
            for (var i = 1; i < spots.length; i++) {
              if (spots[i].y >= spots[peak].y) peak = i;
            }
            return peak;
          }();

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = (constraints.maxWidth * 0.58).clamp(200.0, 280.0);
        return Container(
          height: chartHeight,
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ShootIQTheme.cardBorder),
            boxShadow: ShootIQTheme.cardShadow,
          ),
          child: spots.isEmpty
              ? const Center(
                  child: Text(
                    'No shots in this date range',
                    style: TextStyle(color: ShootIQTheme.textSecondary),
                  ),
                )
              : LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: ShootIQTheme.cardBorder,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: spots.length <= 1
                              ? 1
                              : (spots.length / 4).ceilToDouble().clamp(1, 999),
                          getTitlesWidget: (value, meta) {
                            final i = value.round();
                            if (i < 0 || i >= points.length) {
                              return const SizedBox.shrink();
                            }
                            // Prefer session index labels for dense histories.
                            final label = points.length >= 8
                                ? 'S${i + 1}'
                                : '${points[i].date.month}/${points[i].date.day}';
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: ShootIQTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 25,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: ShootIQTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => ShootIQTheme.primaryBlue,
                        getTooltipItems: (touched) => touched.map((spot) {
                          final i = spot.x.round().clamp(0, points.length - 1);
                          final d = points[i].date;
                          return LineTooltipItem(
                            'Shot ${i + 1}\n'
                            '${spot.y.toInt()}  ·  ${d.month}/${d.day}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.28,
                        color: ShootIQTheme.primaryBlue,
                        barWidth: 3.2,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) {
                            final highlight = index == highlightIndex;
                            return FlDotCirclePainter(
                              radius: highlight ? 5 : 3.2,
                              color: highlight
                                  ? ShootIQTheme.redAccent
                                  : ShootIQTheme.primaryBlue,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            );
                          },
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              ShootIQTheme.primaryBlue.withValues(alpha: 0.22),
                              ShootIQTheme.primaryBlue.withValues(alpha: 0.02),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                ),
        );
      },
    );
  }
}

class _CategoryImprovementChart extends StatelessWidget {
  const _CategoryImprovementChart({required this.shots});
  final List<ShotRecord> shots;

  static const _metrics = ProgressAnalyticsService.categoryProgressOrder;

  static Color _colorFor(ProgressMetric metric) {
    return switch (metric) {
      ProgressMetric.release => ShootIQTheme.primaryBlue,
      ProgressMetric.balance => const Color(0xFF2563EB),
      ProgressMetric.elbow => ShootIQTheme.redAccent,
      ProgressMetric.followThrough => const Color(0xFF7C3AED),
      ProgressMetric.footwork => const Color(0xFF0891B2),
      _ => ShootIQTheme.primaryBlue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bars = <LineChartBarData>[];
    for (final metric in _metrics) {
      final spots = <FlSpot>[
        for (var i = 0; i < shots.length; i++)
          FlSpot(
            i.toDouble(),
            ProgressAnalyticsService.metricValue(shots[i], metric).toDouble(),
          ),
      ];
      if (spots.isEmpty) continue;
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: _colorFor(metric),
          barWidth: 2.4,
          isStrokeCapRound: true,
          dotData: FlDotData(show: shots.length <= 8),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = (constraints.maxWidth * 0.62).clamp(220.0, 300.0);
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ShootIQTheme.cardBorder),
            boxShadow: ShootIQTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final metric in _metrics)
                    _LegendDot(
                      color: _colorFor(metric),
                      label: ProgressAnalyticsService.metricLabel(metric),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: chartHeight - 48,
                child: bars.isEmpty
                    ? const Center(
                        child: Text(
                          'No shots in this date range',
                          style: TextStyle(color: ShootIQTheme.textSecondary),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: 100,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 25,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: ShootIQTheme.cardBorder,
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: shots.length <= 1
                                    ? 1
                                    : (shots.length / 4)
                                        .ceilToDouble()
                                        .clamp(1, 999),
                                getTitlesWidget: (value, meta) {
                                  final i = value.round();
                                  if (i < 0 || i >= shots.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = shots[i].createdAt;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      shots.length >= 8
                                          ? 'S${i + 1}'
                                          : '${d.month}/${d.day}',
                                      style: const TextStyle(
                                        color: ShootIQTheme.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: 25,
                                getTitlesWidget: (value, meta) => Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(
                                    color: ShootIQTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) =>
                                  ShootIQTheme.surfaceElevated,
                              getTooltipItems: (touched) => touched.map((spot) {
                                final metric = _metrics[spot.barIndex.clamp(
                                  0,
                                  _metrics.length - 1,
                                )];
                                return LineTooltipItem(
                                  '${ProgressAnalyticsService.metricLabel(metric)}\n'
                                  '${spot.y.toInt()}',
                                  TextStyle(
                                    color: _colorFor(metric),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          lineBarsData: bars,
                        ),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.compare});
  final PersonalBaselineCompare? compare;

  @override
  Widget build(BuildContext context) {
    final data = compare;
    if (data == null) {
      return const _MutedBox('Baseline unavailable.');
    }

    return Container(
      width: double.infinity,
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.person_pin_circle_outlined,
                  color: ShootIQTheme.basketballOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.ready
                      ? 'Baseline unlocked'
                      : '${data.sampleCount}/${data.minSamples} shots',
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (data.highlight != null) ...[
            const SizedBox(height: 12),
            Text(
              data.highlight!,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (data.ready) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _BaselineChip(
                  label: 'User Avg',
                  value: '${data.userAverage ?? '—'}',
                ),
                const SizedBox(width: 8),
                _BaselineChip(
                  label: 'Best Shot',
                  value: '${data.bestShot ?? '—'}',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BaselineChip(
                    label: 'Weakest',
                    value: data.weakestCategory ?? '—',
                    compact: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BaselineChip extends StatelessWidget {
  const _BaselineChip({
    required this.label,
    required this.value,
    this.compact = false,
  });
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: ShootIQTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontSize: compact ? 12 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: ShootIQTheme.basketballOrange,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsProgressList extends StatelessWidget {
  const _GoalsProgressList({required this.goals});
  final List<ProgressGoal> goals;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final goal in goals) ...[
          _GoalProgressTile(goal: goal),
          if (goal != goals.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _GoalProgressTile extends StatelessWidget {
  const _GoalProgressTile({required this.goal});
  final ProgressGoal goal;

  @override
  Widget build(BuildContext context) {
    final accent = goal.completed
        ? const Color(0xFF22C55E)
        : ShootIQTheme.basketballOrange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: goal.isPrimary
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.35)
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
                  'Goal: ${goal.title}',
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${goal.current} / ${goal.target}',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 8,
              backgroundColor: ShootIQTheme.cardBorder,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemindersBanner extends StatelessWidget {
  const _RemindersBanner({required this.reminders});
  final List<ProgressionReminder> reminders;

  @override
  Widget build(BuildContext context) {
    final items = reminders.take(2).toList();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  ShootIQTheme.basketballOrange.withValues(alpha: 0.22),
                  ShootIQTheme.surfaceElevated,
                ],
              ),
              border: Border.all(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: ShootIQTheme.basketballOrange,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[i].message,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final StreakInfo streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Row(
        children: [
          _ProgressRing(
            progress: (streak.currentDays / 7).clamp(0.0, 1.0),
            centerLabel: '${streak.currentDays}',
            subtitle: 'streak',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training Streak',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current: ${streak.currentDays} day${streak.currentDays == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Longest: ${streak.longestDays} day${streak.longestDays == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last training: ${streak.lastTrainingLabel}',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.centerLabel,
    required this.subtitle,
  });

  final double progress;
  final String centerLabel;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RingPainter(progress: value),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerLabel,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      height: 1,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bg = Paint()
      ..color = ShootIQTheme.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final fg = Paint()
      ..color = ShootIQTheme.basketballOrange
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.28318 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ChallengesSection extends StatelessWidget {
  const _ChallengesSection({required this.challenges});
  final List<ChallengeItem> challenges;

  @override
  Widget build(BuildContext context) {
    final daily =
        challenges.where((c) => c.period == ChallengePeriod.daily).toList();
    final weekly =
        challenges.where((c) => c.period == ChallengePeriod.weekly).toList();
    final monthly =
        challenges.where((c) => c.period == ChallengePeriod.monthly).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (daily.isNotEmpty) ...[
          const _ChallengeGroupLabel('Daily Challenges'),
          const SizedBox(height: 8),
          for (final c in daily) ...[
            _ChallengeCard(challenge: c),
            const SizedBox(height: 8),
          ],
        ],
        if (weekly.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _ChallengeGroupLabel('Weekly Challenges'),
          const SizedBox(height: 8),
          for (final c in weekly) ...[
            _ChallengeCard(challenge: c),
            const SizedBox(height: 8),
          ],
        ],
        if (monthly.isNotEmpty) ...[
          const SizedBox(height: 6),
          const _ChallengeGroupLabel('Monthly Challenge'),
          const SizedBox(height: 8),
          for (final c in monthly) ...[
            _ChallengeCard(challenge: c, emphasize: true),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _ChallengeGroupLabel extends StatelessWidget {
  const _ChallengeGroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: ShootIQTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    this.emphasize = false,
  });
  final ChallengeItem challenge;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final accent = challenge.completed
        ? const Color(0xFF22C55E)
        : ShootIQTheme.basketballOrange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasize
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.4)
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
                  challenge.title,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${challenge.percentComplete}%',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            challenge.description,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: challenge.progress,
              minHeight: 8,
              backgroundColor: ShootIQTheme.cardBorder,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                challenge.progressLabel,
                style: const TextStyle(
                  color: ShootIQTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Reward: ${challenge.reward}',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({required this.achievements});
  final List<AchievementBadge> achievements;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final badge in achievements) ...[
          _AchievementCard(badge: badge),
          if (badge != achievements.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AchievementCard extends StatefulWidget {
  const _AchievementCard({required this.badge});
  final AchievementBadge badge;

  @override
  State<_AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<_AchievementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.badge.completed) {
      _pulse.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _AchievementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.badge.completed && !oldWidget.badge.completed) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    final accent = badge.completed
        ? ShootIQTheme.basketballOrange
        : badge.inProgress
            ? const Color(0xFFFBBF24)
            : ShootIQTheme.textSecondary;

    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeOutBack),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: badge.completed
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.12)
              : ShootIQTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badge.completed
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.45)
                : ShootIQTheme.cardBorder,
          ),
        ),
        child: Row(
          children: [
            _ProgressRing(
              progress: badge.progress,
              centerLabel: badge.emoji,
              subtitle: '${badge.percentComplete}%',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          badge.title,
                          style: TextStyle(
                            color: badge.locked
                                ? ShootIQTheme.textSecondary
                                : ShootIQTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge.statusLabel,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    badge.description,
                    style: const TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badge.progressLabel,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerSnapshot extends StatelessWidget {
  const _CareerSnapshot({required this.stats});
  final PlayerCareerStats stats;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Shots Analyzed', '${stats.shotsAnalyzed}'),
      ('Average Score', stats.shotsAnalyzed == 0 ? '—' : '${stats.averageScore}'),
      ('Best Score', stats.shotsAnalyzed == 0 ? '—' : '${stats.bestScore}'),
      (
        'Current Streak',
        stats.currentStreakDays == 0
            ? '0 Days'
            : '${stats.currentStreakDays} Day${stats.currentStreakDays == 1 ? '' : 's'}',
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tiles.map((tile) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48) / 2,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShootIQTheme.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tile.$2,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.$1,
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MutedBox extends StatelessWidget {
  const _MutedBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Text(
        text,
        style: const TextStyle(color: ShootIQTheme.textSecondary),
      ),
    );
  }
}
