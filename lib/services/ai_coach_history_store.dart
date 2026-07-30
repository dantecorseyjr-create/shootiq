import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shootiq/models/ai_coach_message.dart';

/// Persists the AI Coach conversation locally across app launches.
class AiCoachHistoryStore {
  AiCoachHistoryStore._();

  static const _key = 'shootiq_ai_coach_messages_v1';

  static Future<List<AiCoachMessage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => AiCoachMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<AiCoachMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Cap history so prefs stay small.
    final trimmed = messages.length > 120
        ? messages.sublist(messages.length - 120)
        : messages;
    final encoded = jsonEncode(trimmed.map((m) => m.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
