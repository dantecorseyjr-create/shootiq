import 'package:flutter/material.dart';

/// One MediaPipe landmark point (normalized 0–1 coordinates).
class JointPoint {
  const JointPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  final double x;
  final double y;
  final double z;
  final double visibility;

  factory JointPoint.fromJson(Map<String, dynamic> json) {
    return JointPoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
      visibility: (json['visibility'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One frame from the backend `overlay_frames` list.
class OverlayFrame {
  const OverlayFrame({
    required this.frame,
    required this.timeSec,
    required this.landmarks,
    required this.isLoadFrame,
    required this.isReleaseFrame,
    required this.jointStatus,
  });

  final int frame;
  final double timeSec;
  final Map<String, JointPoint> landmarks;
  final bool isLoadFrame;
  final bool isReleaseFrame;

  /// Joint name → `"red"` or `"green"`.
  final Map<String, String> jointStatus;

  factory OverlayFrame.fromJson(Map<String, dynamic> json) {
    final rawLandmarks = (json['landmarks'] as Map?) ?? const {};
    final landmarks = <String, JointPoint>{};
    for (final entry in rawLandmarks.entries) {
      final value = entry.value;
      if (value is Map) {
        landmarks[entry.key.toString()] =
            JointPoint.fromJson(Map<String, dynamic>.from(value));
      }
    }

    final rawStatus = (json['joint_status'] as Map?) ?? const {};
    final jointStatus = <String, String>{};
    for (final entry in rawStatus.entries) {
      jointStatus[entry.key.toString()] = entry.value.toString();
    }

    return OverlayFrame(
      frame: (json['frame'] as num?)?.toInt() ?? 0,
      timeSec: (json['time_sec'] as num?)?.toDouble() ?? 0,
      landmarks: landmarks,
      isLoadFrame: json['is_load_frame'] == true,
      isReleaseFrame: json['is_release_frame'] == true,
      jointStatus: jointStatus,
    );
  }

  /// Nearest overlay frame to [timeSec] (seconds).
  ///
  /// Uses binary search (O(log n)) assuming frames are ordered by
  /// ascending [timeSec] — the backend writes them in frame order.
  /// Behavior matches a linear closest-time scan.
  static OverlayFrame? findClosest(List<OverlayFrame> frames, double timeSec) {
    if (frames.isEmpty) return null;
    if (frames.length == 1) return frames.first;

    var lo = 0;
    var hi = frames.length - 1;

    // Exact / bracket search on sorted time_sec.
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final midT = frames[mid].timeSec;
      if (midT < timeSec) {
        lo = mid + 1;
      } else if (midT > timeSec) {
        hi = mid - 1;
      } else {
        return frames[mid];
      }
    }

    // [lo] is the first index with time_sec > target (insertion point).
    if (lo <= 0) return frames.first;
    if (lo >= frames.length) return frames.last;

    final before = frames[lo - 1];
    final after = frames[lo];
    final dBefore = (timeSec - before.timeSec).abs();
    final dAfter = (after.timeSec - timeSec).abs();
    // Prefer earlier frame on exact ties (same as left-to-right linear scan).
    return dBefore <= dAfter ? before : after;
  }
}

/// Body-part focus sets for mistake-section highlighting (render-only).
class SkeletonHighlightSets {
  SkeletonHighlightSets._();

  static const dimOpacity = 0.30;

  /// Returns joint-name tokens to keep fully opaque for [section].
  /// Empty set means highlight the full body (no dimming).
  static Set<String> forSection(String section) {
    final key = section.trim().toLowerCase();
    switch (key) {
      case 'feet & stance':
      case 'feet_stance':
      case 'feet':
      case 'stance':
        return {
          'hip',
          'knee',
          'ankle',
          'foot',
          'heel',
        };
      case 'knee bend':
      case 'knee_bend':
      case 'knees':
        return {
          'hip',
          'knee',
          'ankle',
        };
      case 'ball position':
      case 'ball_position':
        return {
          'wrist',
          'index',
          'thumb',
          'pinky',
          'elbow',
        };
      case 'elbow alignment':
      case 'elbow_alignment':
      case 'elbow':
        return {
          'shoulder',
          'elbow',
          'wrist',
        };
      case 'shooting motion':
      case 'shooting_motion':
        return {
          'shoulder',
          'elbow',
          'wrist',
          'index',
        };
      case 'follow through':
      case 'follow_through':
      case 'follow-through':
        return {
          'wrist',
          'elbow',
          'shoulder',
        };
      case 'balance':
        return const {}; // full body
      default:
        return const {};
    }
  }

  static bool jointMatches(String jointName, Set<String> tokens) {
    if (tokens.isEmpty) return true;
    final lower = jointName.toLowerCase();
    for (final token in tokens) {
      if (lower.contains(token)) return true;
    }
    return false;
  }
}

/// Draws a MediaPipe-style skeleton using normalized landmark positions.
class SkeletonOverlayPainter extends CustomPainter {
  SkeletonOverlayPainter({
    required this.landmarks,
    required this.jointStatus,
    this.highlightTokens = const {},
    this.flashHighlight = false,
  });

  final Map<String, JointPoint> landmarks;
  final Map<String, String> jointStatus;

  /// Substring tokens (e.g. `elbow`, `wrist`) for focused joints.
  /// Empty = full-body opacity (no dimming).
  final Set<String> highlightTokens;

  /// When true, focused joints flash yellow instead of red/green.
  final bool flashHighlight;

  static const _flashYellow = Color(0xFFFFD60A);

  static const _bones = <(String, String)>[
    ('left_shoulder', 'right_shoulder'),
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('left_wrist', 'left_index'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('right_wrist', 'right_index'),
    ('left_shoulder', 'left_hip'),
    ('right_shoulder', 'right_hip'),
    ('left_hip', 'right_hip'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
    ('left_ankle', 'left_foot_index'),
    ('right_ankle', 'right_foot_index'),
  ];

  bool _isFocused(String joint) =>
      SkeletonHighlightSets.jointMatches(joint, highlightTokens);

  Color _colorFor(String joint) {
    if (flashHighlight && _isFocused(joint)) {
      return _flashYellow;
    }
    final status = jointStatus[joint]?.toLowerCase();
    if (status == 'red') return const Color(0xFFE63946);
    if (status == 'green') return const Color(0xFF2A9D8F);
    return const Color(0xFFE0E0E0);
  }

  double _opacityFor(String joint) {
    if (highlightTokens.isEmpty) return 1.0;
    return _isFocused(joint) ? 1.0 : SkeletonHighlightSets.dimOpacity;
  }

  Offset? _point(String name, Size size) {
    final joint = landmarks[name];
    if (joint == null || joint.visibility < 0.3) return null;
    return Offset(joint.x * size.width, joint.y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final bone in _bones) {
      final a = _point(bone.$1, size);
      final b = _point(bone.$2, size);
      if (a == null || b == null) continue;
      final opacity =
          (_opacityFor(bone.$1) + _opacityFor(bone.$2)) / 2.0 * 0.85;
      bonePaint.color = _colorFor(bone.$1).withValues(alpha: opacity);
      canvas.drawLine(a, b, bonePaint);
    }

    final jointPaint = Paint()..style = PaintingStyle.fill;
    for (final entry in landmarks.entries) {
      final point = _point(entry.key, size);
      if (point == null) continue;
      jointPaint.color =
          _colorFor(entry.key).withValues(alpha: _opacityFor(entry.key));
      final radius = flashHighlight && _isFocused(entry.key) ? 6.0 : 4.5;
      canvas.drawCircle(point, radius, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SkeletonOverlayPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.jointStatus != jointStatus ||
        oldDelegate.highlightTokens != highlightTokens ||
        oldDelegate.flashHighlight != flashHighlight;
  }
}
