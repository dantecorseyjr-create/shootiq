import 'package:shootiq/models/breakdown_item.dart';

/// Typed alias for a Step 5/6 biomechanics category result from `/analyze`.
typedef BiomechanicsResult = BreakdownItem;

/// Coaching feedback pair attached to a biomechanics category.
class FeedbackIssue {
  const FeedbackIssue({
    required this.observation,
    required this.fix,
    this.category,
    this.seconds = 0,
    this.color,
  });

  /// What the player is doing wrong / right (coach observation).
  final String observation;

  /// How to fix it.
  final String fix;

  final String? category;
  final double seconds;
  final String? color;

  factory FeedbackIssue.fromBiomechanics(BiomechanicsResult item) {
    return FeedbackIssue(
      observation: item.coachingObservation,
      fix: item.coachingFix,
      category: item.category,
      seconds: item.seconds,
      color: item.displayColor,
    );
  }

  factory FeedbackIssue.fromJson(Map<String, dynamic> json) {
    return FeedbackIssue(
      observation: json['issue'] as String? ??
          json['observation'] as String? ??
          '',
      fix: json['correction'] as String? ?? json['fix'] as String? ?? '',
      category: json['category'] as String?,
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      color: (json['color'] as String?)?.toUpperCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'issue': observation,
        'correction': fix,
        if (category != null) 'category': category,
        'seconds': seconds,
        if (color != null) 'color': color,
      };
}
