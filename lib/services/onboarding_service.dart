import 'package:shared_preferences/shared_preferences.dart';

/// Persists onboarding completion and lightweight player profile placeholders.
class OnboardingService {
  OnboardingService._();

  static const _completedKey = 'hasCompletedOnboarding';
  static const _playerSetupKey = 'hasCompletedPlayerSetup';
  static const _userNameKey = 'shootiq_user_name';
  static const _lastScoreKey = 'shootiq_last_score';
  static const _streakKey = 'shootiq_current_streak';
  static const _longestStreakKey = 'shootiq_longest_streak';
  static const _heightKey = 'shootiq_height';
  static const _weightKey = 'shootiq_weight';
  static const _ageKey = 'shootiq_age';
  static const _positionKey = 'shootiq_position';
  static const _dominantHandKey = 'shootiq_dominant_hand';
  static const _skillLevelKey = 'shootiq_skill_level';

  static SharedPreferences? _prefs;

  /// In-memory onboarding selections (current session).
  static String? selectedGoal;
  static int? selectedGoalIndex;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _requirePrefs {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('OnboardingService.init() must be called before use.');
    }
    return prefs;
  }

  /// Whether the user has finished the first-time onboarding flow.
  static bool get hasCompletedOnboarding =>
      _prefs?.getBool(_completedKey) ?? false;

  static Future<void> setHasCompletedOnboarding(bool value) async {
    await init();
    await _requirePrefs.setBool(_completedKey, value);
  }

  /// Whether the post-signup player setup form was completed.
  static bool get hasCompletedPlayerSetup =>
      _prefs?.getBool(_playerSetupKey) ?? false;

  static Future<void> setHasCompletedPlayerSetup(bool value) async {
    await init();
    await _requirePrefs.setBool(_playerSetupKey, value);
  }

  static String get userName =>
      _prefs?.getString(_userNameKey) ?? 'Player';

  static Future<void> setUserName(String name) async {
    await init();
    await _requirePrefs.setString(_userNameKey, name);
  }

  static int get lastScore => _prefs?.getInt(_lastScoreKey) ?? 0;

  static Future<void> setLastScore(int score) async {
    await init();
    await _requirePrefs.setInt(_lastScoreKey, score);
  }

  static int get currentStreakDays => _prefs?.getInt(_streakKey) ?? 0;

  static Future<void> setCurrentStreakDays(int days) async {
    await init();
    await _requirePrefs.setInt(_streakKey, days);
    final longest = longestStreakDays;
    if (days > longest) {
      await _requirePrefs.setInt(_longestStreakKey, days);
    }
  }

  static int get longestStreakDays => _prefs?.getInt(_longestStreakKey) ?? 0;

  static Future<void> setLongestStreakDays(int days) async {
    await init();
    final current = longestStreakDays;
    if (days > current) {
      await _requirePrefs.setInt(_longestStreakKey, days);
    }
  }

  static String? get height => _prefs?.getString(_heightKey);
  static String? get weight => _prefs?.getString(_weightKey);
  static String? get age => _prefs?.getString(_ageKey);
  static String? get position => _prefs?.getString(_positionKey);
  static String? get dominantHand => _prefs?.getString(_dominantHandKey);
  static String? get skillLevel => _prefs?.getString(_skillLevelKey);

  /// Saves local player profile fields from the setup screen.
  static Future<void> savePlayerSetup({
    required String height,
    required String weight,
    required String age,
    required String position,
    required String dominantHand,
    required String skillLevel,
  }) async {
    await init();
    final prefs = _requirePrefs;
    await prefs.setString(_heightKey, height.trim());
    await prefs.setString(_weightKey, weight.trim());
    await prefs.setString(_ageKey, age.trim());
    await prefs.setString(_positionKey, position);
    await prefs.setString(_dominantHandKey, dominantHand);
    await prefs.setString(_skillLevelKey, skillLevel);
    await prefs.setBool(_playerSetupKey, true);
  }

  /// Marks onboarding complete. Score/streak stay at 0 until real analyses sync.
  static Future<void> completeOnboarding({
    String? userName,
    int lastScore = 0,
    int streakDays = 0,
  }) async {
    await init();
    await _requirePrefs.setBool(_completedKey, true);
    await _requirePrefs.setString(
      _userNameKey,
      userName ?? OnboardingService.userName,
    );
    await _requirePrefs.setInt(_lastScoreKey, lastScore);
    await _requirePrefs.setInt(_streakKey, streakDays);
  }
}
