import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/session_dashboard_service.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Home tab — Today's Session dashboard from saved analyses.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SessionDashboardSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await SessionDashboardService.load();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
    final recent = snap.recent;
    if (recent != null) {
      await OnboardingService.setLastScore(recent.overallScore);
    }
  }

  void _openRecent(ShotRecord shot) {
    context.push(AppRoutes.results, extra: shot.toResultsMap());
  }

  void _analyzeNew() => context.go(AppRoutes.analyze);

  void _viewProgress() => context.go(AppRoutes.progress);

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final name = OnboardingService.userName;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: SafeArea(
        child: RefreshIndicator(
          color: ShootIQTheme.basketballOrange,
          onRefresh: _load,
          child: _loading && snap == null
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Text(
                      name.isEmpty ? 'Welcome back' : 'Hey, $name',
                      style: TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Today's Session",
                      style: TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (snap == null || !snap.hasTodaySession)
                      _EmptySession(onAnalyze: _analyzeNew)
                    else ...[
                      _StatGrid(snapshot: snap),
                      const SizedBox(height: 20),
                      const _SectionTitle('Category Averages'),
                      const SizedBox(height: 10),
                      _CategoryAverages(averages: snap.categoryAverages),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _InsightCard(
                              title: 'Most Improved',
                              value: snap.mostImprovedCategory ?? '—',
                              subtitle: snap.mostImprovedDelta == null
                                  ? 'Need more shots'
                                  : snap.mostImprovedDelta! >= 0
                                      ? '+${snap.mostImprovedDelta} vs prior'
                                      : '${snap.mostImprovedDelta} vs prior',
                              accent: const Color(0xFF22C55E),
                              icon: Icons.trending_up_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InsightCard(
                              title: 'Lowest Performing',
                              value: snap.lowestCategory ?? '—',
                              subtitle: snap.lowestCategoryScore == null
                                  ? '—'
                                  : 'Avg ${snap.lowestCategoryScore}',
                              accent: const Color(0xFFF59E0B),
                              icon: Icons.trending_down_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle('Most Recent Analysis'),
                      const SizedBox(height: 10),
                      if (snap.recent != null)
                        _RecentAnalysisCard(
                          shot: snap.recent!,
                          onTap: () => _openRecent(snap.recent!),
                        ),
                    ],
                    if (snap != null &&
                        !snap.hasTodaySession &&
                        snap.recent != null) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle('Last Analysis'),
                      const SizedBox(height: 10),
                      _RecentAnalysisCard(
                        shot: snap.recent!,
                        onTap: () => _openRecent(snap.recent!),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _analyzeNew,
                        icon: const Icon(Icons.videocam_rounded),
                        label: const Text('Analyze New Shot'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ShootIQTheme.buttonBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          side: const BorderSide(
                            color: ShootIQTheme.redBorder,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _viewProgress,
                        icon: const Icon(Icons.show_chart_rounded),
                        label: const Text('View Progress'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ShootIQTheme.primaryBlue,
                          side: const BorderSide(
                            color: ShootIQTheme.primaryBlue,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
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

class _EmptySession extends StatelessWidget {
  const _EmptySession({required this.onAnalyze});
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          Icon(
            Icons.sports_basketball_outlined,
            size: 44,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          const Text(
            'No shots analyzed today',
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start your practice session by analyzing a shot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ShootIQTheme.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onAnalyze,
            style: FilledButton.styleFrom(
              backgroundColor: ShootIQTheme.buttonBlue,
              foregroundColor: Colors.white,
              side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Analyze New Shot'),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.snapshot});
  final SessionDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Shots Analyzed',
        '${snapshot.shotsAnalyzed}',
        Icons.sports_basketball_outlined
      ),
      (
        'Average Score',
        '${snapshot.averageOverall}',
        Icons.analytics_outlined
      ),
      (
        'Best Score',
        '${snapshot.bestOverall}',
        Icons.emoji_events_outlined
      ),
      (
        'Lowest Score',
        '${snapshot.lowestOverall}',
        Icons.arrow_downward_rounded
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 50) / 2,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShootIQTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.$3, color: ShootIQTheme.basketballOrange, size: 20),
                const SizedBox(height: 10),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$1,
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

class _CategoryAverages extends StatelessWidget {
  const _CategoryAverages({required this.averages});
  final Map<String, int> averages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: SessionDashboardService.categoryOrder.map((label) {
          final score = averages[label] ?? 0;
          final color = score >= 80
              ? const Color(0xFF22C55E)
              : score >= 65
                  ? const Color(0xFFEAB308)
                  : const Color(0xFFEF4444);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (score / 100).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: ShootIQTheme.cardBorder,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$score',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
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

class _RecentAnalysisCard extends StatefulWidget {
  const _RecentAnalysisCard({
    required this.shot,
    required this.onTap,
  });

  final ShotRecord shot;
  final VoidCallback onTap;

  @override
  State<_RecentAnalysisCard> createState() => _RecentAnalysisCardState();
}

class _RecentAnalysisCardState extends State<_RecentAnalysisCard> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(covariant _RecentAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shot.id != widget.shot.id ||
        oldWidget.shot.comparePlaybackUrl != widget.shot.comparePlaybackUrl) {
      _thumb = null;
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final url = widget.shot.comparePlaybackUrl;
    if (url == null || url.isEmpty) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 65,
        timeMs: 400,
      );
      if (!mounted || bytes == null) return;
      setState(() => _thumb = bytes);
    } catch (e) {
      // ignore: avoid_print
      print('Session dashboard thumbnail skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ShootIQTheme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 96,
                  child: _thumb != null
                      ? Image.memory(_thumb!, fit: BoxFit.cover)
                      : Container(
                          color: ShootIQTheme.basketballOrange
                              .withValues(alpha: 0.16),
                          alignment: Alignment.center,
                          child: Text(
                            '${shot.overallScore}',
                            style: const TextStyle(
                              color: ShootIQTheme.basketballOrange,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shot.formattedDate,
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Score ${shot.overallScore}',
                      style: const TextStyle(
                        color: ShootIQTheme.basketballOrange,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (shot.strongestCategory != null)
                      Text(
                        'Strongest: ${shot.strongestCategory}',
                        style: TextStyle(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to reopen',
                      style: TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: ShootIQTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
