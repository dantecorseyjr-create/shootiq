import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/shot_comparison_service.dart';
import 'package:shootiq/services/shot_history_service.dart';
import 'package:shootiq/widgets/empty_state.dart';
import 'package:shootiq/widgets/shot_video_player.dart';

/// Side-by-side NBA-style shot evolution comparison.
///
/// Loads only persisted history — no MediaPipe / re-analysis.
class SessionComparePage extends StatefulWidget {
  const SessionComparePage({
    super.key,
    this.initialLeftId,
    this.initialRightId,
  });

  final String? initialLeftId;
  final String? initialRightId;

  @override
  State<SessionComparePage> createState() => _SessionComparePageState();
}

class _SessionComparePageState extends State<SessionComparePage>
    with SingleTickerProviderStateMixin {
  final _leftPlayerKey = GlobalKey<ShotVideoPlayerState>();
  final _rightPlayerKey = GlobalKey<ShotVideoPlayerState>();

  List<ShotRecord> _shots = const [];
  bool _loading = true;
  ShotRecord? _shotA;
  ShotRecord? _shotB;
  int? _careerDevelopment;

  bool _playing = false;
  double _speed = 0.5;
  double _progress = 0;
  bool _scrubbing = false;
  VoidCallback? _leftTick;
  VoidCallback? _rightTick;

  late final AnimationController _scoreAnim;

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
  }

  @override
  void dispose() {
    _detachListeners();
    _scoreAnim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final shots = await ShotHistoryService.getUserShots(limit: 100);
    if (!mounted) return;

    ShotRecord? findById(String? id) {
      if (id == null) return null;
      for (final shot in shots) {
        if (shot.id == id) return shot;
      }
      return null;
    }

    ShotRecord? a = findById(widget.initialLeftId);
    ShotRecord? b = findById(widget.initialRightId);
    a ??= shots.length >= 2 ? shots[1] : (shots.isNotEmpty ? shots.first : null);
    b ??= shots.isNotEmpty ? shots.first : null;
    if (a != null && b != null && a.id == b.id && shots.length >= 2) {
      b = shots.firstWhere((s) => s.id != a!.id, orElse: () => shots.first);
    }

    int? career;
    if (shots.isNotEmpty && b != null) {
      // History is newest-first; last item is the earliest analyzed shot.
      final first = shots.last;
      career = ShotComparison.careerDevelopmentPercent(
        firstShot: first,
        currentShot: b.createdAt.isAfter(a?.createdAt ?? b.createdAt) ? b : (a ?? b),
      );
    }

    setState(() {
      _shots = shots;
      _shotA = a;
      _shotB = b;
      _careerDevelopment = career;
      _loading = false;
    });
    _scoreAnim.forward(from: 0);
  }

  ShotComparison? get _comparison {
    final a = _shotA;
    final b = _shotB;
    if (a == null || b == null) return null;
    return ShotComparison.compare(a, b);
  }

  void _detachListeners() {
    if (_leftTick != null) {
      _leftPlayerKey.currentState?.removePlaybackListener(_leftTick!);
      _leftTick = null;
    }
    if (_rightTick != null) {
      _rightPlayerKey.currentState?.removePlaybackListener(_rightTick!);
      _rightTick = null;
    }
  }

  void _attachListeners() {
    _detachListeners();
    _leftTick = () {
      if (_scrubbing || !mounted) return;
      final left = _leftPlayerKey.currentState;
      if (left == null || !left.isReady) return;
      final dur = left.duration.inMilliseconds;
      if (dur <= 0) return;
      setState(() {
        _progress = (left.position.inMilliseconds / dur).clamp(0.0, 1.0);
        _playing = left.isPlaying;
      });
    };
    _leftPlayerKey.currentState?.addPlaybackListener(_leftTick!);
  }

  Future<void> _onPlayersReady() async {
    _attachListeners();
    await _applySpeed(_speed);
    if (_playing) {
      await _playBoth();
    } else {
      await _pauseBoth();
    }
  }

  Future<void> _playBoth() async {
    setState(() => _playing = true);
    await Future.wait([
      _leftPlayerKey.currentState?.play() ?? Future.value(),
      _rightPlayerKey.currentState?.play() ?? Future.value(),
    ]);
  }

  Future<void> _pauseBoth() async {
    setState(() => _playing = false);
    await Future.wait([
      _leftPlayerKey.currentState?.pause() ?? Future.value(),
      _rightPlayerKey.currentState?.pause() ?? Future.value(),
    ]);
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _pauseBoth();
    } else {
      await _playBoth();
    }
  }

  Future<void> _applySpeed(double speed) async {
    setState(() => _speed = speed);
    await Future.wait([
      _leftPlayerKey.currentState?.setSpeed(speed) ?? Future.value(),
      _rightPlayerKey.currentState?.setSpeed(speed) ?? Future.value(),
    ]);
  }

  Future<void> _seekBoth(double fraction) async {
    final wasPlaying = _playing;
    Future<void> seekOne(GlobalKey<ShotVideoPlayerState> key) async {
      final state = key.currentState;
      if (state == null || !state.isReady) return;
      final ms = (state.duration.inMilliseconds * fraction).round();
      await state.seekTo(
        Duration(milliseconds: ms),
        autoPlay: wasPlaying,
      );
    }

    await Future.wait([
      seekOne(_leftPlayerKey),
      seekOne(_rightPlayerKey),
    ]);
  }

  Future<void> _seekPhase(ComparisonPhaseMarker phase) async {
    Future<void> seekPlayer(
      GlobalKey<ShotVideoPlayerState> key,
      double? seconds,
    ) async {
      if (seconds == null) return;
      final state = key.currentState;
      if (state == null || !state.isReady) return;
      await state.seekTo(
        Duration(milliseconds: (seconds * 1000).round()),
        autoPlay: false,
      );
    }

    setState(() => _playing = false);
    await Future.wait([
      seekPlayer(_leftPlayerKey, phase.beforeSeconds),
      seekPlayer(_rightPlayerKey, phase.afterSeconds),
    ]);
  }

  Future<void> _replayBoth() async {
    await _seekBoth(0);
    await _playBoth();
  }

  Future<void> _pickShot({required bool isA}) async {
    final selected = await showModalBottomSheet<ShotRecord>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (context, controller) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    isA ? 'Select Shot A' : 'Select Shot B',
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: _shots.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final shot = _shots[index];
                      final other = isA ? _shotB : _shotA;
                      final disabled = other?.id == shot.id;
                      return ListTile(
                        enabled: !disabled,
                        title: Text(
                          shot.formattedDate,
                          style: TextStyle(
                            color: disabled
                                ? ShootIQTheme.textSecondary
                                : ShootIQTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          'Score ${shot.overallScore}'
                          '${disabled ? ' · already selected' : ''}',
                          style: const TextStyle(
                            color: ShootIQTheme.textSecondary,
                          ),
                        ),
                        trailing: Text(
                          '${shot.overallScore}',
                          style: const TextStyle(
                            color: ShootIQTheme.basketballOrange,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        onTap: disabled
                            ? null
                            : () => Navigator.of(context).pop(shot),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() {
      _playing = false;
      _progress = 0;
      if (isA) {
        _shotA = selected;
      } else {
        _shotB = selected;
      }
      if (_shots.isNotEmpty) {
        final first = _shots.last;
        final newer = (_shotA != null && _shotB != null)
            ? (_shotA!.createdAt.isAfter(_shotB!.createdAt) ? _shotA! : _shotB!)
            : selected;
        _careerDevelopment = ShotComparison.careerDevelopmentPercent(
          firstShot: first,
          currentShot: newer,
        );
      }
    });
    _scoreAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: ShootIQTheme.darkBackground,
        foregroundColor: ShootIQTheme.textPrimary,
        elevation: 0,
        title: const Text(
          'Shot Evolution',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: ShootIQTheme.basketballOrange,
              ),
            )
          : _shots.length < 2
              ? EmptyState(
                  icon: Icons.compare_arrows_rounded,
                  title: 'Need two shots to compare',
                  message:
                      'Analyze at least two basketball shots to unlock Shot Evolution.',
                  actionLabel: 'Analyze a Shot',
                  onAction: () => Navigator.of(context).maybePop(),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ShotPickerChip(
                            label: 'Shot A',
                            shot: _shotA,
                            onTap: () => _pickShot(isA: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ShotPickerChip(
                            label: 'Shot B',
                            shot: _shotB,
                            onTap: () => _pickShot(isA: false),
                          ),
                        ),
                      ],
                    ),
                    if (comparison != null) ...[
                      const SizedBox(height: 18),
                      _EvolutionHeader(comparison: comparison),
                      const SizedBox(height: 16),
                      _OverallScoreCard(
                        comparison: comparison,
                        animation: _scoreAnim,
                      ),
                      if (_careerDevelopment != null) ...[
                        const SizedBox(height: 12),
                        _DevelopmentScoreCard(percent: _careerDevelopment!),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _SyncVideoPane(
                              playerKey: _leftPlayerKey,
                              label:
                                  'Older · ${comparison.older.formattedDate}',
                              shot: comparison.older,
                              onReady: _onPlayersReady,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SyncVideoPane(
                              playerKey: _rightPlayerKey,
                              label:
                                  'Newer · ${comparison.newer.formattedDate}',
                              shot: comparison.newer,
                              onReady: _onPlayersReady,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SyncControls(
                        playing: _playing,
                        speed: _speed,
                        progress: _progress,
                        onTogglePlay: _togglePlay,
                        onReplay: _replayBoth,
                        onSpeed: _applySpeed,
                        onSeekStart: () => setState(() => _scrubbing = true),
                        onSeek: (value) => setState(() => _progress = value),
                        onSeekEnd: (value) async {
                          setState(() {
                            _progress = value;
                            _scrubbing = false;
                          });
                          await _seekBoth(value);
                        },
                      ),
                      const SizedBox(height: 14),
                      _PhaseScrubber(
                        phases: comparison.phases,
                        onPhase: _seekPhase,
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Compare Categories',
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...comparison.metrics
                          .where((m) => m.label != 'Overall Score')
                          .map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CategoryCompareCard(metric: m),
                            ),
                          ),
                      const SizedBox(height: 12),
                      const Text(
                        'AI Summary',
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SummaryCard(text: comparison.narrativeSummary),
                    ],
                  ],
                ),
    );
  }
}

class _EvolutionHeader extends StatelessWidget {
  const _EvolutionHeader({required this.comparison});
  final ShotComparison comparison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
            ShootIQTheme.cardBackground,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  'Older Shot',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comparison.older.formattedDate,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: ShootIQTheme.basketballOrange,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Newer Shot',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comparison.newer.formattedDate,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w700,
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

class _OverallScoreCard extends StatelessWidget {
  const _OverallScoreCard({
    required this.comparison,
    required this.animation,
  });

  final ShotComparison comparison;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final overall = comparison.metrics.firstWhere(
      (m) => m.label == 'Overall Score',
      orElse: () => ComparisonMetric(
        label: 'Overall Score',
        before: comparison.older.overallScore,
        after: comparison.newer.overallScore,
      ),
    );
    final deltaColor = overall.improved
        ? const Color(0xFF22C55E)
        : overall.declined
            ? const Color(0xFFEF4444)
            : ShootIQTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(animation.value);
          final beforeShown = (overall.before * t).round();
          final afterShown = (overall.after * t).round();
          final deltaShown = (overall.delta * t).round();
          final deltaLabel =
              deltaShown > 0 ? '+$deltaShown' : '$deltaShown';

          return Column(
            children: [
              const Text(
                'Overall Score',
                style: TextStyle(
                  color: ShootIQTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ScoreBlock(
                      caption: 'Before',
                      value: '$beforeShown',
                      color: ShootIQTheme.textPrimary,
                    ),
                  ),
                  Expanded(
                    child: _ScoreBlock(
                      caption: 'After',
                      value: '$afterShown',
                      color: ShootIQTheme.basketballOrange,
                    ),
                  ),
                  Expanded(
                    child: _ScoreBlock(
                      caption: 'Improvement',
                      value: deltaLabel,
                      color: deltaColor,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.caption,
    required this.value,
    required this.color,
  });

  final String caption;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          caption,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _DevelopmentScoreCard extends StatelessWidget {
  const _DevelopmentScoreCard({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final positive = percent >= 0;
    final color =
        positive ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final label = positive ? '+$percent%' : '$percent%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            positive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Player Development Score',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label ${positive ? 'better' : 'below'} than your first analyzed shot',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
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

class _CategoryCompareCard extends StatelessWidget {
  const _CategoryCompareCard({required this.metric});
  final ComparisonMetric metric;

  @override
  Widget build(BuildContext context) {
    final color = metric.improved
        ? const Color(0xFF22C55E)
        : metric.declined
            ? const Color(0xFFEF4444)
            : ShootIQTheme.textSecondary;

    return Container(
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
            metric.label,
            style: const TextStyle(
              color: ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Before', value: '${metric.before}'),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'After',
                  value: '${metric.after}',
                  valueColor: ShootIQTheme.basketballOrange,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Change',
                  value: metric.changeLabel,
                  valueColor: color,
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
  const _MiniStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

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
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? ShootIQTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ],
    );
  }
}

class _PhaseScrubber extends StatelessWidget {
  const _PhaseScrubber({
    required this.phases,
    required this.onPhase,
  });

  final List<ComparisonPhaseMarker> phases;
  final ValueChanged<ComparisonPhaseMarker> onPhase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key Body Positions',
          style: TextStyle(
            color: ShootIQTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a phase to sync both skeleton videos',
          style: TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < phases.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _PhaseChip(
                  phase: phases[i],
                  onTap: () => onPhase(phases[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, required this.onTap});

  final ComparisonPhaseMarker phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = phase.hasBefore || phase.hasAfter;
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: available
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: available
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.45)
                : ShootIQTheme.cardBorder,
          ),
        ),
        child: Text(
          phase.label,
          style: TextStyle(
            color: available
                ? ShootIQTheme.basketballOrange
                : ShootIQTheme.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ShotPickerChip extends StatelessWidget {
  const _ShotPickerChip({
    required this.label,
    required this.shot,
    required this.onTap,
  });

  final String label;
  final ShotRecord? shot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
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
              label,
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shot?.formattedDate ?? 'Select shot',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              shot == null ? 'Tap to choose' : 'Score ${shot!.overallScore}',
              style: const TextStyle(
                color: ShootIQTheme.basketballOrange,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncVideoPane extends StatelessWidget {
  const _SyncVideoPane({
    required this.playerKey,
    required this.label,
    required this.shot,
    required this.onReady,
  });

  final GlobalKey<ShotVideoPlayerState> playerKey;
  final String label;
  final ShotRecord shot;
  final VoidCallback onReady;

  static File? _existingLocal(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return null;
    final file = path.startsWith('file://')
        ? File(Uri.parse(path).toFilePath())
        : File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    // Skeleton overlay first, then analysis/slow-mo, raw original last —
    // matches the priority documented on [ShotRecord.comparePlaybackUrl].
    final candidates = <String>[
      if (shot.skeletonVideoUrl != null) shot.skeletonVideoUrl!,
      if (shot.analysisVideoUrl != null) shot.analysisVideoUrl!,
      if (shot.slowMotionVideoUrl != null) shot.slowMotionVideoUrl!,
      if (shot.videoUrl != null) shot.videoUrl!,
    ];
    final unique = <String>[];
    for (final path in candidates) {
      if (path.isNotEmpty && !unique.contains(path)) unique.add(path);
    }

    // Prefer playable on-device files over temporary AI-server URLs.
    final localPaths = unique
        .where((p) => _existingLocal(p) != null)
        .toList(growable: false);
    final remotePaths = unique
        .where((p) => p.startsWith('http://') || p.startsWith('https://'))
        .toList(growable: false);
    final ordered = <String>[...localPaths, ...remotePaths];

    final localFile =
        localPaths.isEmpty ? null : _existingLocal(localPaths.first);
    final networkUrl = ordered.isEmpty ? null : ordered.first;
    final fallbacks = ordered.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ShootIQTheme.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: localFile == null &&
                  (networkUrl == null || networkUrl.isEmpty)
              ? Container(
                  height: 180,
                  alignment: Alignment.center,
                  color: ShootIQTheme.cardBackground,
                  child: const Text(
                    'No video',
                    style: TextStyle(color: ShootIQTheme.textSecondary),
                  ),
                )
              : ShotVideoPlayer(
                  key: playerKey,
                  file: localFile,
                  networkUrl: networkUrl,
                  fallbackUrls: fallbacks,
                  preferLocalFile: true,
                  autoPlay: false,
                  showControls: false,
                  aspectRatio: 9 / 16,
                  onReady: onReady,
                ),
        ),
        if (localFile == null && !shot.hasLocalVideoCandidate) ...[
          const SizedBox(height: 6),
          const Text(
            'Video was only on the AI server and is no longer available. Re-analyze to keep a local copy.',
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

class _SyncControls extends StatelessWidget {
  const _SyncControls({
    required this.playing,
    required this.speed,
    required this.progress,
    required this.onTogglePlay,
    required this.onReplay,
    required this.onSpeed,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final bool playing;
  final double speed;
  final double progress;
  final VoidCallback onTogglePlay;
  final VoidCallback onReplay;
  final ValueChanged<double> onSpeed;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: ShootIQTheme.basketballOrange,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChangeStart: (_) => onSeekStart(),
              onChanged: onSeek,
              onChangeEnd: onSeekEnd,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onTogglePlay,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: ShootIQTheme.textPrimary,
                ),
              ),
              IconButton(
                onPressed: onReplay,
                icon: const Icon(
                  Icons.replay_rounded,
                  color: ShootIQTheme.textPrimary,
                ),
              ),
              const Spacer(),
              const Text(
                'Skeleton synced',
                style: TextStyle(
                  color: ShootIQTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              _SpeedChip(
                label: '0.5x',
                active: speed == 0.5,
                onTap: () => onSpeed(0.5),
              ),
              const SizedBox(width: 6),
              _SpeedChip(
                label: '1x',
                active: speed == 1.0,
                onTap: () => onSpeed(1.0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.22)
              : ShootIQTheme.cardBorder,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.55)
                : ShootIQTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? ShootIQTheme.basketballOrange
                : ShootIQTheme.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.text});
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
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
