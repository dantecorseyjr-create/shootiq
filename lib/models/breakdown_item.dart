/// One coaching row from FastAPI `/analyze` `biomechanics` / `breakdown`.
class BreakdownItem {
  const BreakdownItem({
    required this.category,
    required this.score,
    required this.status,
    required this.timestamp,
    required this.issue,
    required this.correction,
    this.color,
    this.measurement,
    this.seconds = 0,
    this.confidence,
    this.highlight = const [],
    this.phase,
    this.phaseKey,
    this.playbackSpeed,
    this.autoPlay,
    this.features = const {},
  });

  final String category;
  final int score;
  final String status; // PASS | WARN | NEEDS_WORK | FAIL
  final String timestamp; // MM:SS
  final String issue;
  final String correction;
  final String? color; // GREEN | YELLOW | RED
  final String? measurement;
  final double seconds;
  final double? confidence;

  /// Internal numeric features for personal baseline (not shown in UI).
  final Map<String, double> features;

  /// Joint/segment keys for overlay highlight (elbow, knee, etc.).
  final List<String> highlight;

  /// Human phase label, e.g. "Release".
  final String? phase;

  /// Machine phase key, e.g. "release".
  final String? phaseKey;

  /// Preferred playback speed when reviewing this category.
  final double? playbackSpeed;

  /// Whether review should auto-play (false = pause on key frame).
  final bool? autoPlay;

  bool get isPass => status == 'PASS' || color == 'GREEN';
  bool get isFail => status == 'FAIL' || color == 'RED';
  bool get needsWork =>
      status == 'WARN' ||
      status == 'NEEDS_WORK' ||
      color == 'YELLOW' ||
      (!isPass && !isFail);

  String get displayColor {
    if (color != null && color!.isNotEmpty) return color!.toUpperCase();
    if (isPass) return 'GREEN';
    if (isFail) return 'RED';
    return 'YELLOW';
  }

  /// Coach-facing status label (PASS / WARN / FAIL style).
  String get coachingStatusLabel {
    if (isPass) return 'PASS';
    if (isFail) return 'FAIL';
    return 'WARN';
  }

  /// Observation in coaching language.
  String get coachingObservation {
    final text = issue.trim();
    if (text.isEmpty) {
      return isPass ? 'Solid mechanics here.' : 'This area needs attention.';
    }
    return text
        .replaceAll('threshold', 'ideal range')
        .replaceAll('Exceeded', 'Opened past')
        .replaceAll('exceeded', 'opened past');
  }

  /// Actionable fix in coaching language.
  String get coachingFix {
    final text = correction.trim();
    if (text.isEmpty) {
      return isPass
          ? 'Keep repeating this form.'
          : 'Adjust this movement and try again.';
    }
    return text;
  }

  /// Friendly body-part labels for the selected category.
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
    if (labels.isEmpty) {
      // Sensible defaults by category / phase rubric.
      final cat = category.toLowerCase();
      if (cat.contains('feet') || cat == 'stance') {
        return const ['Feet', 'Ankles', 'Core'];
      }
      if (cat == 'load' || cat.contains('knee')) {
        return const ['Knees', 'Hips', 'Core'];
      }
      if (cat.contains('set')) {
        return const ['Elbow', 'Forearm', 'Wrist'];
      }
      if (cat.contains('balance')) return const ['Core', 'Hips'];
      if (cat.contains('elbow')) return const ['Upper arm', 'Forearm'];
      if (cat.contains('follow')) {
        return const ['Shooting arm', 'Wrist', 'Core'];
      }
      if (cat.contains('release')) {
        return const ['Elbow', 'Wrist', 'Core'];
      }
    }
    return labels;
  }

  double get reviewPlaybackSpeed {
    if (playbackSpeed != null) return playbackSpeed!;
    final key = (phaseKey ?? '').toLowerCase();
    if (key == 'setup' || key == 'knee_load') return 1.0;
    return 0.5;
  }

  bool get reviewAutoPlay {
    if (autoPlay != null) return autoPlay!;
    final key = (phaseKey ?? '').toLowerCase();
    // Pause on setup / load key frames; play slow for release mechanics.
    return key != 'setup' && key != 'knee_load';
  }

  factory BreakdownItem.fromJson(Map<String, dynamic> json) {
    final seconds = _parseSeconds(json);
    return BreakdownItem(
      category: json['category'] as String? ?? 'Mechanic',
      score: (json['score'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String? ?? 'NEEDS_WORK').toUpperCase(),
      timestamp: json['timestamp'] as String? ??
          _formatTimestamp(seconds),
      issue: json['issue'] as String? ?? '',
      correction: json['correction'] as String? ?? '',
      color: (json['color'] as String?)?.toUpperCase(),
      measurement: json['measurement'] as String?,
      seconds: seconds,
      confidence: (json['confidence'] as num?)?.toDouble(),
      highlight: (json['highlight'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      phase: json['phase'] as String?,
      phaseKey: json['phase_key'] as String?,
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble(),
      autoPlay: json['auto_play'] as bool?,
      features: {
        for (final entry
            in ((json['features'] as Map?) ?? const {}).entries)
          if (entry.value is num) entry.key.toString(): (entry.value as num).toDouble(),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'score': score,
        'status': status,
        'color': displayColor,
        'measurement': measurement,
        'timestamp': timestamp,
        'issue': issue,
        'correction': correction,
        'seconds': seconds,
        if (confidence != null) 'confidence': confidence,
        if (highlight.isNotEmpty) 'highlight': highlight,
        if (phase != null) 'phase': phase,
        if (phaseKey != null) 'phase_key': phaseKey,
        if (playbackSpeed != null) 'playback_speed': playbackSpeed,
        if (autoPlay != null) 'auto_play': autoPlay,
        if (features.isNotEmpty) 'features': features,
      };

  Duration get seekPosition => Duration(
        milliseconds: (seconds * 1000).round(),
      );

  static double _parseSeconds(Map<String, dynamic> json) {
    final rawSeconds = json['seconds'];
    if (rawSeconds is num) return rawSeconds.toDouble();

    // Some payloads send timestamp as a bare number (e.g. 3.2).
    final rawTs = json['timestamp'];
    if (rawTs is num) return rawTs.toDouble();
    if (rawTs is String) {
      if (rawTs.contains(':')) return _parseTimestampSeconds(rawTs);
      return double.tryParse(rawTs) ?? 0;
    }
    return 0;
  }

  static double _parseTimestampSeconds(String? stamp) {
    if (stamp == null || stamp.isEmpty) return 0;
    final parts = stamp.split(':');
    if (parts.length != 2) return 0;
    final minutes = int.tryParse(parts[0]) ?? 0;
    final secs = double.tryParse(parts[1]) ?? 0;
    return minutes * 60 + secs;
  }

  static String _formatTimestamp(double seconds) {
    final total = seconds.round().clamp(0, 99999);
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}

/// Shot phase row for the Results timeline.
class TimelineItem {
  const TimelineItem({
    required this.phase,
    required this.timestamp,
    required this.status,
    this.seconds = 0,
    this.startSeconds,
    this.endSeconds,
    this.keySeconds,
    this.phaseKey,
    this.color,
  });

  final String phase;
  final String timestamp;
  final String status;

  /// Seek target — beginning of the phase when available.
  final double seconds;

  /// Explicit phase span (seconds). Falls back to [seconds].
  final double? startSeconds;
  final double? endSeconds;

  /// Peak / keyframe within the phase (for markers).
  final double? keySeconds;

  final String? phaseKey;
  final String? color;

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    final startSeconds = (json['start_seconds'] as num?)?.toDouble();
    final seconds = startSeconds ??
        (json['seconds'] as num?)?.toDouble() ??
        BreakdownItem._parseTimestampSeconds(json['timestamp'] as String?);
    return TimelineItem(
      phase: json['phase'] as String? ?? json['label'] as String? ?? '',
      timestamp: json['timestamp'] as String? ??
          BreakdownItem._formatTimestamp(seconds),
      status: (json['status'] as String? ?? 'PASS').toUpperCase(),
      seconds: seconds,
      startSeconds: startSeconds,
      endSeconds: (json['end_seconds'] as num?)?.toDouble(),
      keySeconds: (json['key_seconds'] as num?)?.toDouble() ??
          (json['seconds'] as num?)?.toDouble(),
      phaseKey: json['phase_key'] as String?,
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'timestamp': timestamp,
        'status': status,
        'seconds': seconds,
        if (startSeconds != null) 'start_seconds': startSeconds,
        if (endSeconds != null) 'end_seconds': endSeconds,
        if (keySeconds != null) 'key_seconds': keySeconds,
        if (phaseKey != null) 'phase_key': phaseKey,
        if (color != null) 'color': color,
      };

  /// Seek to the beginning of this phase.
  Duration get seekPosition => Duration(
        milliseconds: ((startSeconds ?? seconds) * 1000).round(),
      );

  String get statusEmoji {
    switch (status) {
      case 'PASS':
        return '🟢';
      case 'FAIL':
        return '🔴';
      default:
        return '🟡';
    }
  }
}

/// Marker drawn on the video scrubber for a biomechanics / phase moment.
class VideoTimelineMarker {
  const VideoTimelineMarker({
    required this.seconds,
    required this.color,
    this.label,
    this.hexColor,
  });

  final double seconds;
  final String color; // GREEN | YELLOW | RED | PHASE
  final String? label;

  /// Optional explicit hex (e.g. phase colors from the API).
  final String? hexColor;
}
