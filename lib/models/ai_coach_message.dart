/// A single message in the AI Shooting Coach conversation.
enum AiCoachMessageRole { user, assistant }

class AiCoachMessage {
  const AiCoachMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final AiCoachMessageRole role;
  final String text;
  final DateTime createdAt;

  bool get isUser => role == AiCoachMessageRole.user;
  bool get isAssistant => role == AiCoachMessageRole.assistant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AiCoachMessage.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? 'assistant';
    return AiCoachMessage(
      id: json['id'] as String? ??
          'm_${DateTime.now().millisecondsSinceEpoch}',
      role: roleName == 'user'
          ? AiCoachMessageRole.user
          : AiCoachMessageRole.assistant,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
