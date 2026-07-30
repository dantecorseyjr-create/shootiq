/// Loading UX for the "Analyzing Your Shot" screen.
///
/// Progress is driven by real AI completion. Stage copy matches the backend
/// pipeline percentages (upload → extract → pose → mechanics → report).
class AnalysisLoadingConfig {
  AnalysisLoadingConfig._();

  /// Soft ceiling while waiting on the network/AI (never blocks Results).
  static const Duration maxOptimisticDuration = Duration(seconds: 45);

  /// Pipeline stages shown in the UI (aligned with FastAPI progress).
  static const stages = <({double endProgress, String message, int percent})>[
    (endProgress: 0.18, message: 'Uploading video', percent: 100),
    (endProgress: 0.40, message: 'Detecting movement', percent: 25),
    (endProgress: 0.62, message: 'Evaluating mechanics', percent: 50),
    (endProgress: 0.84, message: 'Creating feedback', percent: 75),
    (endProgress: 1.0, message: 'Preparing results', percent: 100),
  ];

  static List<String> get stepLabels =>
      stages.map((stage) => stage.message).toList(growable: false);

  static String statusForProgress(double progress) {
    final p = progress.clamp(0.0, 1.0);
    for (final stage in stages) {
      if (p <= stage.endProgress) return stage.message;
    }
    return stages.last.message;
  }

  /// Only used for offline/demo paths — never for live video uploads.
  static Map<String, dynamic> placeholderResults() {
    return {
      'overall_score': 0,
      'metrics': {
        'elbow_alignment': 0,
        'knee_bend': 0,
        'balance': 0,
        'follow_through': 0,
      },
      'issues': ['No live analysis available'],
      'recommendations': ['Upload a shot to run real AI analysis'],
      'breakdown': <Map<String, dynamic>>[],
    };
  }
}
