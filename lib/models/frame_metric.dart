/// One sampled frame of biomechanics measurements from `/analyze`.
///
/// Loaded from saved analysis data — scrubbing never re-runs AI.
class FrameMetric {
  const FrameMetric({
    required this.t,
    required this.frame,
    required this.phase,
    required this.phaseLabel,
    required this.highlight,
    required this.metrics,
    this.elbowAngle,
    this.kneeAngle,
    this.shoulderTilt,
    this.sampleIndex,
    this.confidence,
  });

  final double t;
  final int frame;
  final int? sampleIndex;
  final String phase;
  final String phaseLabel;
  final List<String> highlight;
  final List<FrameMetricValue> metrics;
  final double? elbowAngle;
  final double? kneeAngle;
  final double? shoulderTilt;
  final double? confidence;

  factory FrameMetric.fromJson(Map<String, dynamic> json) {
    final metricsRaw = json['metrics'];
    List<FrameMetricValue> metrics;
    if (metricsRaw is List) {
      metrics = metricsRaw
          .whereType<Map>()
          .map((m) => FrameMetricValue.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } else if (metricsRaw is Map) {
      // Tolerate map-shaped payloads.
      metrics = metricsRaw.entries
          .where((e) => e.value is Map)
          .map(
            (e) => FrameMetricValue.fromJson({
              'key': e.key,
              ...Map<String, dynamic>.from(e.value as Map),
            }),
          )
          .toList();
    } else {
      metrics = const [];
    }

    return FrameMetric(
      t: (json['t'] as num?)?.toDouble() ?? 0,
      frame: (json['frame'] as num?)?.toInt() ?? 0,
      sampleIndex: (json['sample_index'] as num?)?.toInt(),
      phase: json['shot_phase'] as String? ??
          json['phase'] as String? ??
          'setup',
      phaseLabel: json['phase_label'] as String? ??
          json['phase'] as String? ??
          'Stance',
      highlight: (json['highlight'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      metrics: metrics,
      elbowAngle: (json['elbow_angle'] as num?)?.toDouble(),
      kneeAngle: (json['knee_angle'] as num?)?.toDouble(),
      shoulderTilt: (json['shoulder_tilt'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        't': t,
        'frame': frame,
        if (sampleIndex != null) 'sample_index': sampleIndex,
        'phase': phase,
        'shot_phase': phase,
        'phase_label': phaseLabel,
        'highlight': highlight,
        'metrics': metrics.map((m) => m.toJson()).toList(),
        if (elbowAngle != null) 'elbow_angle': elbowAngle,
        if (kneeAngle != null) 'knee_angle': kneeAngle,
        if (shoulderTilt != null) 'shoulder_tilt': shoulderTilt,
        if (confidence != null) 'confidence': confidence,
      };

  /// Friendly body-part labels for highlight chips.
  List<String> get highlightLabels {
    const map = <String, String>{
      'ankle': 'Ankles',
      'foot': 'Feet',
      'knee': 'Knees',
      'hip': 'Hips',
      'torso': 'Core',
      'shoulder': 'Shoulders',
      'elbow': 'Elbow',
      'forearm': 'Forearm',
      'wrist': 'Wrist',
      'arm': 'Shooting arm',
    };
    final labels = <String>[];
    for (final key in highlight) {
      final label = map[key.toLowerCase()] ?? key;
      if (!labels.contains(label)) labels.add(label);
    }
    return labels;
  }

  FrameMetricValue? metricFor(String key) {
    for (final m in metrics) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// A single live measurement row (Feet & Stance, Knee Bend, …).
class FrameMetricValue {
  const FrameMetricValue({
    required this.key,
    required this.label,
    required this.display,
    required this.color,
    this.value,
    this.unit,
  });

  final String key;
  final String label;
  final String display;
  final String color; // GREEN | YELLOW | RED
  final double? value;
  final String? unit;

  factory FrameMetricValue.fromJson(Map<String, dynamic> json) {
    return FrameMetricValue(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? json['key'] as String? ?? '',
      display: json['display'] as String? ?? '—',
      color: (json['color'] as String? ?? 'YELLOW').toUpperCase(),
      value: (json['value'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'display': display,
        'color': color,
        if (value != null) 'value': value,
        if (unit != null) 'unit': unit,
      };

  bool get isGreen => color == 'GREEN';
  bool get isRed => color == 'RED';
  bool get isYellow => !isGreen && !isRed;
}

/// Binary-search helper over a sorted [FrameMetric] series by timestamp.
class FrameMetricSeries {
  const FrameMetricSeries(this.frames);

  final List<FrameMetric> frames;

  bool get isEmpty => frames.isEmpty;
  bool get isNotEmpty => frames.isNotEmpty;

  factory FrameMetricSeries.fromJson(dynamic raw) {
    if (raw is! List || raw.isEmpty) {
      return const FrameMetricSeries([]);
    }
    final frames = raw
        .whereType<Map>()
        .map((item) => FrameMetric.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => a.t.compareTo(b.t));
    return FrameMetricSeries(frames);
  }

  List<Map<String, dynamic>> toJson() =>
      frames.map((f) => f.toJson()).toList();

  /// Nearest saved sample for [seconds] (O(log n)).
  FrameMetric? atSeconds(double seconds) {
    if (frames.isEmpty) return null;
    if (seconds <= frames.first.t) return frames.first;
    if (seconds >= frames.last.t) return frames.last;

    var lo = 0;
    var hi = frames.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = frames[mid].t;
      if (t < seconds) {
        lo = mid + 1;
      } else if (t > seconds) {
        hi = mid - 1;
      } else {
        return frames[mid];
      }
    }
    // lo is first index with t >= seconds; pick closer of lo-1 / lo.
    final right = lo.clamp(0, frames.length - 1);
    final left = (lo - 1).clamp(0, frames.length - 1);
    final a = frames[left];
    final b = frames[right];
    return (seconds - a.t).abs() <= (b.t - seconds).abs() ? a : b;
  }
}
