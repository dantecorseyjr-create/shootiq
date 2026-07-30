import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/frame_metric.dart';

/// Horizontal phase strip + frame scrubber synced to the analyzed video.
class BiomechanicsTimeline extends StatelessWidget {
  const BiomechanicsTimeline({
    super.key,
    required this.phases,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.onPhaseSelected,
    required this.onScrub,
    this.selectedPhaseKey,
    this.activeFrame,
  });

  final List<TimelineItem> phases;
  final double positionSeconds;
  final double durationSeconds;
  final String? selectedPhaseKey;
  final FrameMetric? activeFrame;
  final ValueChanged<TimelineItem> onPhaseSelected;
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    final duration = durationSeconds <= 0 ? 1.0 : durationSeconds;
    final progress = (positionSeconds / duration).clamp(0.0, 1.0);
    final activePhase = activeFrame?.phase ?? selectedPhaseKey;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Biomechanics Timeline',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (activeFrame != null)
                Text(
                  activeFrame!.phaseLabel,
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a phase to jump there — flagged phases auto-play the clip.',
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: phases.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = phases[index];
                final selected = (item.phaseKey ?? item.phase) == activePhase ||
                    (selectedPhaseKey != null &&
                        (item.phaseKey ?? item.phase) == selectedPhaseKey);
                final color = _phaseColor(item);
                return _PhaseChip(
                  label: item.phase,
                  color: color,
                  selected: selected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onPhaseSelected(item);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Column(
                children: [
                  SizedBox(
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Phase span bands
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PhaseBandPainter(
                              phases: phases,
                              duration: duration,
                              width: width,
                            ),
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                            thumbColor: Colors.white,
                            overlayColor: ShootIQTheme.basketballOrange
                                .withValues(alpha: 0.25),
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (value) {
                              onScrub(value * duration);
                            },
                          ),
                        ),
                        // Playhead
                        Positioned(
                          left: (width * progress).clamp(0.0, width) - 1,
                          top: 2,
                          bottom: 2,
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _format(positionSeconds),
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _format(durationSeconds),
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          if (activeFrame != null && activeFrame!.highlightLabels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text(
                  'Evaluating:',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...activeFrame!.highlightLabels.map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ShootIQTheme.basketballOrange.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: ShootIQTheme.basketballOrange.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: ShootIQTheme.basketballOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _phaseColor(TimelineItem item) {
    final hex = item.color;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      final value = int.tryParse(hex.substring(1), radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    }
    return switch (item.status) {
      'PASS' => const Color(0xFF22C55E),
      'FAIL' => const Color(0xFFEF4444),
      _ => const Color(0xFFEAB308),
    };
  }

  static String _format(double seconds) {
    final total = seconds.round().clamp(0, 99999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.22) : ShootIQTheme.cardBorder,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : ShootIQTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseBandPainter extends CustomPainter {
  _PhaseBandPainter({
    required this.phases,
    required this.duration,
    required this.width,
  });

  final List<TimelineItem> phases;
  final double duration;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (phases.isEmpty || duration <= 0) return;
    final trackY = size.height / 2;
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, trackY), Offset(size.width, trackY), trackPaint);

    for (final phase in phases) {
      final start = (phase.startSeconds ?? phase.seconds).clamp(0.0, duration);
      final end = (phase.endSeconds ?? phase.seconds).clamp(start, duration);
      final left = (start / duration) * size.width;
      final right = (end / duration) * size.width;
      final color = BiomechanicsTimeline._phaseColor(phase);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final span = (right - left).abs();
      if (span < 3) {
        canvas.drawCircle(Offset(left, trackY), 3.5, Paint()..color = color);
      } else {
        canvas.drawLine(Offset(left, trackY), Offset(right, trackY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PhaseBandPainter oldDelegate) {
    return oldDelegate.phases != phases ||
        oldDelegate.duration != duration ||
        oldDelegate.width != width;
  }
}

/// Live measurements panel that updates as the selected frame changes.
class DynamicAnalysisPanel extends StatelessWidget {
  const DynamicAnalysisPanel({
    super.key,
    required this.frame,
  });

  final FrameMetric? frame;

  @override
  Widget build(BuildContext context) {
    if (frame == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShootIQTheme.cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
        ),
        child: Text(
          'Scrub the timeline to inspect live biomechanics for each frame.',
          style: TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    final f = frame!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Live Analysis',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                f.phaseLabel,
                style: TextStyle(
                  color: ShootIQTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AnglePill(
                label: 'Elbow Angle',
                value: f.elbowAngle != null ? '${f.elbowAngle!.round()}°' : '—',
                color: f.metricFor('set_point')?.color ??
                    f.metricFor('elbow_alignment')?.color ??
                    'YELLOW',
              ),
              const SizedBox(width: 8),
              _AnglePill(
                label: 'Knee Angle',
                value: f.kneeAngle != null ? '${f.kneeAngle!.round()}°' : '—',
                color: f.metricFor('load')?.color ??
                    f.metricFor('knee_bend')?.color ??
                    'YELLOW',
              ),
              const SizedBox(width: 8),
              _AnglePill(
                label: 'Shoulder Tilt',
                value:
                    f.shoulderTilt != null ? '${f.shoulderTilt!.round()}°' : '—',
                color: f.metricFor('stance')?.color ??
                    f.metricFor('balance')?.color ??
                    'YELLOW',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...f.metrics.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MetricRow(metric: m),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnglePill extends StatelessWidget {
  const _AnglePill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final String color;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(color);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric});

  final FrameMetricValue metric;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(metric.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metric.label,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            metric.display,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (metric.unit != null) ...[
            const SizedBox(width: 4),
            Text(
              metric.unit!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(String color) {
  return switch (color.toUpperCase()) {
    'GREEN' => const Color(0xFF22C55E),
    'RED' => const Color(0xFFEF4444),
    _ => const Color(0xFFEAB308),
  };
}
