import 'dart:io';

import 'package:shootiq/models/breakdown_item.dart';
import 'package:shootiq/models/frame_metric.dart';

/// One interactive movement card in the AI analysis breakdown.
class MovementIssue {
  const MovementIssue({
    required this.title,
    required this.score,
    required this.description,
    required this.startTime,
    required this.peakTime,
    required this.endTime,
    required this.affectedBodyParts,
    this.correction = '',
    this.explanation = '',
    this.status = 'WARN',
    this.color = 'YELLOW',
    this.phaseKey,
    this.phase,
    this.playbackSpeed = 0.5,
    this.poseLandmarkKeys = const [],
    this.measurement,
    this.sourceCategory,
  });

  /// Padding applied around detected start/end for clip review.
  static const segmentBufferSec = 0.45;

  /// Max mistake-window length (before buffer) so clips stay tight.
  static const maxDetectedSpanSec = 1.8;

  final String title;
  final int score;

  /// Short mistake / observation shown as "Mistake".
  final String description;

  /// Inclusive clip start (detectedStart − buffer, floored at 0).
  final double startTime;

  /// Key mistake / phase peak frame within the clip.
  final double peakTime;

  /// Inclusive clip end (detectedEnd + buffer).
  final double endTime;

  final List<String> affectedBodyParts;

  final String correction;

  /// Longer coaching explanation (why it matters / what the AI saw).
  final String explanation;

  final String status;
  final String color;
  final String? phaseKey;
  final String? phase;
  final double playbackSpeed;

  /// MediaPipe landmark keys reserved for future skeleton highlighting.
  final List<String> poseLandmarkKeys;

  final String? measurement;
  final String? sourceCategory;

  /// Alias for UI copy that says "Mistake".
  String get mistake => description;

  bool get isPass => status == 'PASS' || color == 'GREEN';
  bool get isFail => status == 'FAIL' || color == 'RED';

  String get displayColor {
    if (color.isNotEmpty) return color.toUpperCase();
    if (isPass) return 'GREEN';
    if (isFail) return 'RED';
    return 'YELLOW';
  }

  Duration get startPosition => Duration(
        milliseconds: (startTime * 1000).round().clamp(0, 1 << 31),
      );

  Duration get peakPosition => Duration(
        milliseconds: (peakTime * 1000).round().clamp(0, 1 << 31),
      );

  Duration get endPosition => Duration(
        milliseconds: (endTime * 1000).round().clamp(0, 1 << 31),
      );

  String get timestampLabel {
    final total = peakTime.round().clamp(0, 99999);
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  /// Build a buffered [startTime, peakTime, endTime] window for clip review.
  static ({double startTime, double peakTime, double endTime}) bufferedSegment({
    required double detectedStart,
    required double peak,
    required double detectedEnd,
  }) {
    var start = detectedStart;
    var end = detectedEnd;
    var peakTime = peak;

    if (end < start) {
      final swap = start;
      start = end;
      end = swap;
    }
    if (peakTime < start) peakTime = start;
    if (peakTime > end) peakTime = end;

    // Keep detected span tight around the peak so long phases don't become
    // full-video clips (e.g. Follow Through → landing).
    if (end - start > maxDetectedSpanSec) {
      start = (peakTime - maxDetectedSpanSec / 2).clamp(start, peakTime);
      end = (peakTime + maxDetectedSpanSec / 2).clamp(peakTime, end);
      if (end - start < 0.35) {
        start = (peakTime - 0.35).clamp(0.0, peakTime);
        end = peakTime + 0.35;
      }
    }

    final startTime = (start - segmentBufferSec).clamp(0.0, double.infinity);
    final endTime = end + segmentBufferSec;
    return (startTime: startTime, peakTime: peakTime, endTime: endTime);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'score': score,
        'description': description,
        'startTime': startTime,
        'peakTime': peakTime,
        'endTime': endTime,
        'affectedBodyParts': affectedBodyParts,
        'correction': correction,
        'explanation': explanation,
        'status': status,
        'color': displayColor,
        if (phaseKey != null) 'phaseKey': phaseKey,
        if (phase != null) 'phase': phase,
        'playbackSpeed': playbackSpeed,
        'poseLandmarkKeys': poseLandmarkKeys,
        if (measurement != null) 'measurement': measurement,
        if (sourceCategory != null) 'sourceCategory': sourceCategory,
      };

  factory MovementIssue.fromJson(Map<String, dynamic> json) {
    final start = (json['startTime'] as num?)?.toDouble() ??
        (json['start_time'] as num?)?.toDouble() ??
        0;
    final end = (json['endTime'] as num?)?.toDouble() ??
        (json['end_time'] as num?)?.toDouble() ??
        start;
    final peak = (json['peakTime'] as num?)?.toDouble() ??
        (json['peak_time'] as num?)?.toDouble() ??
        ((start + end) / 2);
    return MovementIssue(
      title: json['title'] as String? ?? 'Movement',
      score: (json['score'] as num?)?.toInt() ?? 0,
      description: json['description'] as String? ??
          json['mistake'] as String? ??
          '',
      startTime: start,
      peakTime: peak,
      endTime: end,
      affectedBodyParts: (json['affectedBodyParts'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['affected_body_parts'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      correction: json['correction'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      status: (json['status'] as String? ?? 'WARN').toUpperCase(),
      color: (json['color'] as String? ?? 'YELLOW').toUpperCase(),
      phaseKey: json['phaseKey'] as String? ?? json['phase_key'] as String?,
      phase: json['phase'] as String?,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ??
          (json['playback_speed'] as num?)?.toDouble() ??
          0.5,
      poseLandmarkKeys: (json['poseLandmarkKeys'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['pose_landmark_keys'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      measurement: json['measurement'] as String?,
      sourceCategory: json['sourceCategory'] as String? ??
          json['source_category'] as String?,
    );
  }

  /// Fixed AI Analyzer movement order + source category aliases.
  static const catalog = <_MovementSlot>[
    _MovementSlot(
      title: 'Feet & Stance',
      aliases: ['Stance', 'Feet & Stance', 'Feet'],
      defaultBodyParts: ['Feet', 'Ankles', 'Core'],
      poseLandmarkKeys: [
        'left_ankle',
        'right_ankle',
        'left_foot_index',
        'right_foot_index',
        'left_hip',
        'right_hip',
      ],
      phaseKeys: ['setup'],
      metricKeys: ['feet_stance', 'stance'],
    ),
    _MovementSlot(
      title: 'Knee Bend',
      aliases: ['Load', 'Knee Bend', 'Knees'],
      defaultBodyParts: ['Knees', 'Hips'],
      poseLandmarkKeys: [
        'left_knee',
        'right_knee',
        'left_hip',
        'right_hip',
        'left_ankle',
        'right_ankle',
      ],
      phaseKeys: ['knee_load', 'gather'],
      metricKeys: ['knee_bend', 'load'],
    ),
    _MovementSlot(
      title: 'Ball Position',
      aliases: ['Ball Position', 'Hand Position', 'Wrist'],
      defaultBodyParts: ['Wrists', 'Hands'],
      poseLandmarkKeys: [
        'left_wrist',
        'right_wrist',
        'left_index',
        'right_index',
      ],
      phaseKeys: ['set_point', 'release'],
      metricKeys: ['release_position', 'release_point'],
    ),
    _MovementSlot(
      title: 'Elbow Alignment',
      aliases: ['Set Point', 'Elbow Alignment', 'Elbow'],
      defaultBodyParts: ['Elbow', 'Forearm', 'Wrist'],
      poseLandmarkKeys: [
        'left_elbow',
        'right_elbow',
        'left_shoulder',
        'right_shoulder',
        'left_wrist',
        'right_wrist',
      ],
      phaseKeys: ['set_point'],
      metricKeys: ['elbow_alignment', 'set_point'],
    ),
    _MovementSlot(
      title: 'Shooting Motion',
      aliases: ['Release', 'Shooting Motion', 'Release Point', 'Release Position'],
      defaultBodyParts: ['Elbow', 'Wrist', 'Shoulders'],
      poseLandmarkKeys: [
        'left_elbow',
        'right_elbow',
        'left_wrist',
        'right_wrist',
        'left_shoulder',
        'right_shoulder',
      ],
      phaseKeys: ['release', 'upward_motion'],
      metricKeys: ['release', 'release_point'],
    ),
    _MovementSlot(
      title: 'Follow Through',
      aliases: ['Follow Through', 'Follow-Through'],
      defaultBodyParts: ['Shooting arm', 'Wrist', 'Core'],
      poseLandmarkKeys: [
        'left_elbow',
        'right_elbow',
        'left_wrist',
        'right_wrist',
        'left_shoulder',
        'right_shoulder',
      ],
      phaseKeys: ['follow_through'],
      metricKeys: ['follow_through'],
    ),
    _MovementSlot(
      title: 'Balance',
      aliases: ['Balance'],
      defaultBodyParts: ['Core', 'Hips', 'Ankles'],
      poseLandmarkKeys: [
        'left_hip',
        'right_hip',
        'left_shoulder',
        'right_shoulder',
        'left_ankle',
        'right_ankle',
      ],
      phaseKeys: ['gather', 'landing', 'setup'],
      metricKeys: ['balance'],
    ),
  ];

  /// Build the seven interactive cards from `/analyze` biomechanics + timeline.
  ///
  /// When [frameMetrics] are present, the peak timestamp is refined to the
  /// worst sample inside the phase window for tighter clip accuracy.
  ///
  /// When [improvements] includes Shot Scorer v4 rows with
  /// `start_time_sec` / `end_time_sec`, those windows win for matching
  /// sections (already padded by the backend).
  static List<MovementIssue> fromAnalysis({
    required List<BreakdownItem> breakdown,
    List<TimelineItem> timeline = const [],
    Map<String, dynamic>? metrics,
    FrameMetricSeries frameMetrics = const FrameMetricSeries([]),
    List<Map<String, dynamic>> improvements = const [],
  }) {
    return catalog.map((slot) {
      final source = _matchBreakdown(breakdown, slot);
      final phase = _matchTimeline(timeline, slot, source);
      final improvement = _matchImprovement(improvements, slot);

      var peak = phase?.keySeconds ??
          source?.seconds ??
          phase?.seconds ??
          phase?.startSeconds ??
          0.0;
      var detectedStart =
          phase?.startSeconds ?? (peak - 0.45).clamp(0.0, peak);
      final detectedEndRaw = phase?.endSeconds;
      var detectedEnd = (detectedEndRaw != null && detectedEndRaw > peak)
          ? detectedEndRaw
          : peak + 0.55;

      // Follow-through / landing often needs a slightly longer window.
      final isFollowThrough = slot.phaseKeys.contains('follow_through');
      if (isFollowThrough && detectedEnd - detectedStart < 0.9) {
        detectedEnd = peak + 0.75;
        detectedStart = (peak - 0.35).clamp(0.0, peak);
      }

      final refinedPeak = _refinePeakFromFrames(
        frames: frameMetrics,
        slot: slot,
        windowStart: detectedStart,
        windowEnd: detectedEnd,
        fallback: peak,
      );
      if (refinedPeak != null) {
        peak = refinedPeak;
        // Keep the window anchored around the refined mistake frame.
        if (peak < detectedStart) detectedStart = (peak - 0.35).clamp(0.0, peak);
        if (peak > detectedEnd) detectedEnd = peak + 0.45;
      }

      // Prefer backend mistake windows when present (already time-padded).
      late final ({double startTime, double peakTime, double endTime}) segment;
      final impStart = (improvement?['start_time_sec'] as num?)?.toDouble();
      final impEnd = (improvement?['end_time_sec'] as num?)?.toDouble();
      final impPeak = (improvement?['time_sec'] as num?)?.toDouble();
      if (impStart != null && impEnd != null) {
        final peakTime = (impPeak ?? ((impStart + impEnd) / 2))
            .clamp(impStart, impEnd)
            .toDouble();
        segment = (
          startTime: impStart,
          peakTime: peakTime,
          endTime: impEnd < impStart ? impStart + 0.3 : impEnd,
        );
      } else {
        segment = bufferedSegment(
          detectedStart: detectedStart,
          peak: peak,
          detectedEnd: detectedEnd,
        );
      }

      if (source != null) {
        final bodyParts = source.highlightLabels.isNotEmpty
            ? source.highlightLabels
            : slot.defaultBodyParts;
        final impExplanation =
            (improvement?['explanation'] as String?)?.trim() ?? '';
        final impFix = (improvement?['fix'] as String?)?.trim() ?? '';
        return MovementIssue(
          title: slot.title,
          score: source.score,
          description: impExplanation.isNotEmpty
              ? impExplanation
              : source.coachingObservation,
          explanation: _buildExplanation(
            title: slot.title,
            phase: source.phase ?? phase?.phase,
            measurement: source.measurement,
            score: source.score,
            isPass: source.isPass,
            frameNote: _frameNoteAt(frameMetrics, segment.peakTime, slot),
          ),
          startTime: segment.startTime,
          peakTime: segment.peakTime,
          endTime: segment.endTime,
          affectedBodyParts: bodyParts,
          correction: impFix.isNotEmpty ? impFix : source.coachingFix,
          status: source.status,
          color: source.displayColor,
          phaseKey: source.phaseKey ?? phase?.phaseKey ?? slot.phaseKeys.first,
          phase: source.phase ?? phase?.phase,
          playbackSpeed: source.reviewPlaybackSpeed,
          poseLandmarkKeys: slot.poseLandmarkKeys,
          measurement: source.measurement,
          sourceCategory: source.category,
        );
      }

      final metricScore = _metricScore(metrics, slot.metricKeys);
      final isPass = metricScore >= 80;
      final phaseLabel = phase?.phase ?? slot.title;
      final frameNote = _frameNoteAt(frameMetrics, segment.peakTime, slot);
      final description = isPass
          ? 'Solid $phaseLabel mechanics — keep this pattern repeatable.'
          : _fallbackDescription(slot.title, phaseLabel, metricScore);
      final correction = isPass
          ? 'Keep repeating this form under game speed.'
          : _fallbackCorrection(slot.title, segment.peakTime);
      return MovementIssue(
        title: slot.title,
        score: metricScore,
        description: description,
        explanation: _buildExplanation(
          title: slot.title,
          phase: phase?.phase,
          measurement: frameNote,
          score: metricScore,
          isPass: isPass,
          frameNote: frameNote,
        ),
        startTime: segment.startTime,
        peakTime: segment.peakTime,
        endTime: segment.endTime,
        affectedBodyParts: slot.defaultBodyParts,
        correction: correction,
        status: isPass
            ? 'PASS'
            : metricScore >= 65
                ? 'WARN'
                : 'FAIL',
        color: isPass
            ? 'GREEN'
            : metricScore >= 65
                ? 'YELLOW'
                : 'RED',
        phaseKey: phase?.phaseKey ?? slot.phaseKeys.first,
        phase: phase?.phase,
        playbackSpeed: 0.5,
        poseLandmarkKeys: slot.poseLandmarkKeys,
        sourceCategory: slot.aliases.first,
      );
    }).toList();
  }

  static String _fallbackDescription(
    String title,
    String phaseLabel,
    int score,
  ) {
    final lower = title.toLowerCase();
    if (lower.contains('elbow')) {
      return 'Your elbow path during $phaseLabel is costing alignment '
          '(score $score). Keep the shooting elbow under the ball.';
    }
    if (lower.contains('release')) {
      return 'Release timing in $phaseLabel looks late relative to your jump '
          '(score $score). Snap earlier near the peak.';
    }
    if (lower.contains('follow')) {
      return 'Your finish in $phaseLabel is cutting short (score $score). '
          'Hold the follow-through until the ball reaches the rim.';
    }
    if (lower.contains('balance') || lower.contains('stance') || lower.contains('feet')) {
      return 'Base stability in $phaseLabel is inconsistent (score $score). '
          'Quiet feet, same footprint on the landing.';
    }
    if (lower.contains('knee') || lower.contains('load')) {
      return 'Lower-body load timing in $phaseLabel is off (score $score). '
          'Legs start the shot — arms finish it.';
    }
    return 'Form in $phaseLabel scored $score — this is one of your top fix areas.';
  }

  static String _fallbackCorrection(String title, double peakTime) {
    final lower = title.toLowerCase();
    if (lower.contains('elbow')) {
      return 'Cue: “Elbow to the rim.” Rewatch ${peakTime.toStringAsFixed(1)}s.';
    }
    if (lower.contains('release')) {
      return 'Cue: “Up and through at the peak.” Rewatch ${peakTime.toStringAsFixed(1)}s.';
    }
    if (lower.contains('follow')) {
      return 'Cue: “Hold the finish.” Freeze until the ball hits.';
    }
    if (lower.contains('balance') || lower.contains('stance') || lower.contains('feet')) {
      return 'Cue: “Quiet feet.” Land where you jumped from.';
    }
    return 'Rewatch ${peakTime.toStringAsFixed(1)}s and own one short cue before the next set.';
  }

  static String _buildExplanation({
    required String title,
    required String? phase,
    required String? measurement,
    required int score,
    required bool isPass,
    String? frameNote,
  }) {
    final parts = <String>[];
    if (phase != null && phase.trim().isNotEmpty) {
      parts.add('Flagged during the $phase phase.');
    } else {
      parts.add('Evaluated as part of your $title mechanics.');
    }
    if (measurement != null && measurement.trim().isNotEmpty) {
      parts.add(measurement.trim());
    }
    if (frameNote != null && frameNote.isNotEmpty) {
      parts.add(frameNote);
    }
    if (isPass) {
      parts.add('Score $score — keep this pattern consistent.');
    } else {
      parts.add(
        'Score $score — correcting this cue will lift your overall form.',
      );
    }
    return parts.join(' ');
  }

  static String? _frameNoteAt(
    FrameMetricSeries frames,
    double peak,
    _MovementSlot slot,
  ) {
    final sample = frames.atSeconds(peak);
    if (sample == null) return null;
    for (final key in slot.metricKeys) {
      FrameMetricValue? metric = sample.metricFor(key);
      if (metric == null) {
        for (final candidate in sample.metrics) {
          final ck = candidate.key.toLowerCase();
          final sk = key.toLowerCase();
          if (ck.contains(sk) || sk.contains(ck)) {
            metric = candidate;
            break;
          }
        }
      }
      if (metric != null &&
          metric.display.isNotEmpty &&
          metric.display != '—') {
        return 'At the key frame: ${metric.label} ${metric.display}.';
      }
    }
    if (sample.elbowAngle != null &&
        slot.metricKeys.any((k) => k.contains('elbow'))) {
      return 'At the key frame: elbow ≈ ${sample.elbowAngle!.round()}°.';
    }
    if (sample.kneeAngle != null &&
        slot.metricKeys.any((k) => k.contains('knee') || k.contains('load'))) {
      return 'At the key frame: knee ≈ ${sample.kneeAngle!.round()}°.';
    }
    return null;
  }

  /// Prefer the worst (RED/YELLOW) metric sample inside the phase window.
  static double? _refinePeakFromFrames({
    required FrameMetricSeries frames,
    required _MovementSlot slot,
    required double windowStart,
    required double windowEnd,
    required double fallback,
  }) {
    if (frames.isEmpty) return null;
    FrameMetric? worst;
    var worstRank = -1;

    for (final frame in frames.frames) {
      if (frame.t < windowStart - 0.08 || frame.t > windowEnd + 0.08) {
        continue;
      }

      final phaseHit = slot.phaseKeys.any((key) {
        final p = frame.phase.toLowerCase();
        final label = frame.phaseLabel.toLowerCase();
        return p.contains(key.toLowerCase()) ||
            label.contains(key.replaceAll('_', ' ')) ||
            key.contains(p);
      });

      var frameRank = phaseHit ? 0 : -1;
      for (final metric in frame.metrics) {
        final keyHit = slot.metricKeys.any(
          (k) =>
              metric.key.toLowerCase().contains(k.toLowerCase()) ||
              k.toLowerCase().contains(metric.key.toLowerCase()),
        );
        if (!keyHit && !phaseHit) continue;
        final rank = metric.isRed
            ? 3
            : metric.isYellow
                ? 2
                : phaseHit
                    ? 1
                    : 0;
        if (rank > frameRank) frameRank = rank;
      }

      // Prefer frames that highlight this slot's joints.
      final highlightHit = frame.highlight.any((h) {
        final lower = h.toLowerCase();
        return slot.defaultBodyParts.any(
              (b) => b.toLowerCase().contains(lower) || lower.contains(b.toLowerCase().split(' ').first),
            ) ||
            slot.poseLandmarkKeys.any((k) => k.contains(lower));
      });
      if (highlightHit && frameRank < 2) frameRank = 2;

      if (frameRank > worstRank) {
        worstRank = frameRank;
        worst = frame;
      }
    }

    if (worst == null || worstRank <= 0) return null;
    // Ignore tiny adjustments that don't improve accuracy.
    if ((worst.t - fallback).abs() < 0.05) return null;
    return worst.t;
  }

  /// Match a Shot Scorer v4 `improvements[]` row to a movement catalog slot
  /// by `section` label (e.g. "Elbow Alignment").
  static Map<String, dynamic>? _matchImprovement(
    List<Map<String, dynamic>> improvements,
    _MovementSlot slot,
  ) {
    Map<String, dynamic>? best;
    var bestSeverity = 99;
    for (final item in improvements) {
      final section = (item['section'] as String? ?? '').toLowerCase();
      final matched = slot.aliases.any(
            (alias) => section == alias.toLowerCase(),
          ) ||
          slot.aliases.any(
            (alias) => section.contains(alias.toLowerCase()),
          ) ||
          section == slot.title.toLowerCase();
      if (!matched) continue;
      final severity = switch ((item['severity'] as String? ?? '').toLowerCase()) {
        'high' => 0,
        'medium' => 1,
        'low' => 2,
        _ => 3,
      };
      if (severity < bestSeverity) {
        bestSeverity = severity;
        best = item;
      }
    }
    return best;
  }

  static BreakdownItem? _matchBreakdown(
    List<BreakdownItem> breakdown,
    _MovementSlot slot,
  ) {
    for (final alias in slot.aliases) {
      for (final item in breakdown) {
        if (item.category.toLowerCase() == alias.toLowerCase()) {
          return item;
        }
      }
    }
    for (final alias in slot.aliases) {
      for (final item in breakdown) {
        if (item.category.toLowerCase().contains(alias.toLowerCase())) {
          return item;
        }
      }
    }
    return null;
  }

  static TimelineItem? _matchTimeline(
    List<TimelineItem> timeline,
    _MovementSlot slot,
    BreakdownItem? source,
  ) {
    final preferredKeys = <String>[
      if (source?.phaseKey != null) source!.phaseKey!,
      ...slot.phaseKeys,
    ];
    for (final key in preferredKeys) {
      for (final item in timeline) {
        final itemKey = (item.phaseKey ?? '').toLowerCase();
        if (itemKey == key.toLowerCase()) return item;
      }
    }
    if (source != null) {
      for (final item in timeline) {
        if (item.phase.toLowerCase() ==
            (source.phase ?? source.category).toLowerCase()) {
          return item;
        }
      }
    }
    return null;
  }

  static int _metricScore(
    Map<String, dynamic>? metrics,
    List<String> keys,
  ) {
    if (metrics == null) return 70;
    for (final key in keys) {
      final value = metrics[key];
      if (value is num) return value.round().clamp(0, 100);
    }
    return 70;
  }
}

class _MovementSlot {
  const _MovementSlot({
    required this.title,
    required this.aliases,
    required this.defaultBodyParts,
    required this.poseLandmarkKeys,
    required this.phaseKeys,
    required this.metricKeys,
  });

  final String title;
  final List<String> aliases;
  final List<String> defaultBodyParts;
  final List<String> poseLandmarkKeys;
  final List<String> phaseKeys;
  final List<String> metricKeys;
}

/// Route args for [MovementDetailPage].
class MovementDetailArgs {
  const MovementDetailArgs({
    required this.issue,
    this.networkUrl,
    this.fallbackUrls = const [],
    this.file,
    this.preferLocalFile = true,
  });

  final MovementIssue issue;
  final String? networkUrl;
  final List<String> fallbackUrls;
  final File? file;
  final bool preferLocalFile;

  Map<String, dynamic> toExtra() => {
        'issue': issue.toJson(),
        if (networkUrl != null) 'networkUrl': networkUrl,
        'fallbackUrls': fallbackUrls,
        if (file != null) 'filePath': file!.path,
        'preferLocalFile': preferLocalFile,
      };

  static MovementDetailArgs? fromExtra(Object? extra) {
    if (extra is MovementDetailArgs) return extra;
    if (extra is! Map) return null;
    final map = Map<String, dynamic>.from(extra);
    final issueRaw = map['issue'];
    if (issueRaw is! Map) return null;
    final path = map['filePath'] as String? ?? map['file'] as String?;
    return MovementDetailArgs(
      issue: MovementIssue.fromJson(Map<String, dynamic>.from(issueRaw)),
      networkUrl: map['networkUrl'] as String? ?? map['network_url'] as String?,
      fallbackUrls: (map['fallbackUrls'] as List? ?? map['fallback_urls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      file: path != null && path.isNotEmpty ? File(path) : null,
      preferLocalFile: map['preferLocalFile'] as bool? ??
          map['prefer_local_file'] as bool? ??
          true,
    );
  }
}
