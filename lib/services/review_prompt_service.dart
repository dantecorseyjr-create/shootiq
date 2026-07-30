import 'package:shared_preferences/shared_preferences.dart';

/// Tracks meaningful usage so review prompts are not shown too early.
class ReviewPromptService {
  ReviewPromptService._();

  static const _analysesKey = 'shootiq_completed_analyses_count';
  static const _reviewRequestedKey = 'shootiq_review_requested';
  static const _minAnalysesBeforePrompt = 3;

  static Future<int> completedAnalyses() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_analysesKey) ?? 0;
  }

  static Future<void> recordAnalysisCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_analysesKey) ?? 0) + 1;
    await prefs.setInt(_analysesKey, next);
  }

  static Future<bool> hasRequestedReview() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reviewRequestedKey) ?? false;
  }

  static Future<void> markReviewRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reviewRequestedKey, true);
  }

  /// True when the user has enough meaningful usage to see a review ask.
  static Future<bool> shouldOfferReview() async {
    if (await hasRequestedReview()) return false;
    return (await completedAnalyses()) >= _minAnalysesBeforePrompt;
  }
}
