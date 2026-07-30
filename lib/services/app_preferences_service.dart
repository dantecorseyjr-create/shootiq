import 'package:shared_preferences/shared_preferences.dart';

/// Local training / notification / privacy preferences.
class AppPreferencesService {
  AppPreferencesService._();

  static const _pushKey = 'prefs_push_notifications';
  static const _emailKey = 'prefs_email_notifications';
  static const _trainingRemindersKey = 'prefs_training_reminders';
  static const _weeklyReportsKey = 'prefs_weekly_progress';
  static const _shareProgressKey = 'prefs_share_progress';
  static const _analyticsKey = 'prefs_analytics';
  static const _workoutLengthKey = 'prefs_default_workout_minutes';
  static const _focusHandKey = 'prefs_focus_dominant_hand_only';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<AppPreferences> load() async {
    final prefs = await _ensure();
    return AppPreferences(
      pushNotifications: prefs.getBool(_pushKey) ?? true,
      emailNotifications: prefs.getBool(_emailKey) ?? true,
      trainingReminders: prefs.getBool(_trainingRemindersKey) ?? true,
      weeklyProgressReports: prefs.getBool(_weeklyReportsKey) ?? false,
      shareProgressPublicly: prefs.getBool(_shareProgressKey) ?? false,
      analyticsEnabled: prefs.getBool(_analyticsKey) ?? true,
      defaultWorkoutMinutes: prefs.getInt(_workoutLengthKey) ?? 30,
      focusDominantHandOnly: prefs.getBool(_focusHandKey) ?? false,
    );
  }

  static Future<void> save(AppPreferences value) async {
    final prefs = await _ensure();
    await Future.wait([
      prefs.setBool(_pushKey, value.pushNotifications),
      prefs.setBool(_emailKey, value.emailNotifications),
      prefs.setBool(_trainingRemindersKey, value.trainingReminders),
      prefs.setBool(_weeklyReportsKey, value.weeklyProgressReports),
      prefs.setBool(_shareProgressKey, value.shareProgressPublicly),
      prefs.setBool(_analyticsKey, value.analyticsEnabled),
      prefs.setInt(_workoutLengthKey, value.defaultWorkoutMinutes),
      prefs.setBool(_focusHandKey, value.focusDominantHandOnly),
    ]);
  }
}

class AppPreferences {
  const AppPreferences({
    this.pushNotifications = true,
    this.emailNotifications = true,
    this.trainingReminders = true,
    this.weeklyProgressReports = false,
    this.shareProgressPublicly = false,
    this.analyticsEnabled = true,
    this.defaultWorkoutMinutes = 30,
    this.focusDominantHandOnly = false,
  });

  final bool pushNotifications;
  final bool emailNotifications;
  final bool trainingReminders;
  final bool weeklyProgressReports;
  final bool shareProgressPublicly;
  final bool analyticsEnabled;
  final int defaultWorkoutMinutes;
  final bool focusDominantHandOnly;

  AppPreferences copyWith({
    bool? pushNotifications,
    bool? emailNotifications,
    bool? trainingReminders,
    bool? weeklyProgressReports,
    bool? shareProgressPublicly,
    bool? analyticsEnabled,
    int? defaultWorkoutMinutes,
    bool? focusDominantHandOnly,
  }) {
    return AppPreferences(
      pushNotifications: pushNotifications ?? this.pushNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      trainingReminders: trainingReminders ?? this.trainingReminders,
      weeklyProgressReports:
          weeklyProgressReports ?? this.weeklyProgressReports,
      shareProgressPublicly:
          shareProgressPublicly ?? this.shareProgressPublicly,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      defaultWorkoutMinutes:
          defaultWorkoutMinutes ?? this.defaultWorkoutMinutes,
      focusDominantHandOnly:
          focusDominantHandOnly ?? this.focusDominantHandOnly,
    );
  }
}
