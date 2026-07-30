/// Player profile stored in Supabase `player_profiles` (+ local cache).
class PlayerProfile {
  const PlayerProfile({
    this.id,
    required this.userId,
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.height,
    this.weight,
    this.age,
    this.dominantHand,
    this.position,
    this.skillLevel,
    this.experience,
    this.favoriteTeam,
    this.bio,
    this.photoUrl,
    this.updatedAt,
  });

  final String? id;
  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final String? height;
  final int? weight;
  final int? age;
  final String? dominantHand;
  final String? position;
  final String? skillLevel;
  final int? experience;
  final String? favoriteTeam;
  final String? bio;
  final String? photoUrl;
  final DateTime? updatedAt;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    if (username.isNotEmpty) return username;
    return 'Player';
  }

  String get subtitle {
    final skill = skillLevel?.trim();
    final pos = position?.trim();
    if (skill != null &&
        skill.isNotEmpty &&
        pos != null &&
        pos.isNotEmpty) {
      return '$skill $pos';
    }
    return skill ?? pos ?? 'Complete your profile';
  }

  String get heightLabel =>
      (height != null && height!.trim().isNotEmpty) ? height!.trim() : '—';

  String get weightLabel => weight == null ? '—' : '$weight lbs';

  String get ageLabel => age == null ? '—' : '$age';

  String get experienceLabel {
    if (experience == null) return '—';
    if (experience == 1) return '1 Year';
    return '$experience Years';
  }

  String get dominantHandLabel =>
      (dominantHand != null && dominantHand!.trim().isNotEmpty)
          ? dominantHand!.trim()
          : '—';

  String get positionLabel =>
      (position != null && position!.trim().isNotEmpty)
          ? position!.trim()
          : '—';

  PlayerProfile copyWith({
    String? id,
    String? userId,
    String? firstName,
    String? lastName,
    String? username,
    String? height,
    int? weight,
    int? age,
    String? dominantHand,
    String? position,
    String? skillLevel,
    int? experience,
    String? favoriteTeam,
    String? bio,
    String? photoUrl,
    DateTime? updatedAt,
    bool clearFavoriteTeam = false,
    bool clearBio = false,
    bool clearPhotoUrl = false,
  }) {
    return PlayerProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      age: age ?? this.age,
      dominantHand: dominantHand ?? this.dominantHand,
      position: position ?? this.position,
      skillLevel: skillLevel ?? this.skillLevel,
      experience: experience ?? this.experience,
      favoriteTeam:
          clearFavoriteTeam ? null : (favoriteTeam ?? this.favoriteTeam),
      bio: clearBio ? null : (bio ?? this.bio),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      id: json['id'] as String?,
      userId: json['user_id'] as String? ?? '',
      firstName: (json['first_name'] as String?) ?? '',
      lastName: (json['last_name'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      height: json['height'] as String?,
      weight: _asInt(json['weight']),
      age: _asInt(json['age']),
      dominantHand: json['dominant_hand'] as String?,
      position: json['position'] as String?,
      skillLevel: json['skill_level'] as String?,
      experience: _asInt(json['experience']),
      favoriteTeam: json['favorite_team'] as String?,
      bio: json['bio'] as String?,
      photoUrl: json['photo_url'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'username': username.trim(),
      'height': height?.trim(),
      'weight': weight,
      'age': age,
      'dominant_hand': dominantHand?.trim(),
      'position': position?.trim(),
      'skill_level': skillLevel?.trim(),
      'experience': experience,
      'favorite_team': favoriteTeam?.trim().isEmpty == true
          ? null
          : favoriteTeam?.trim(),
      'bio': bio?.trim().isEmpty == true ? null : bio?.trim(),
      'photo_url': photoUrl,
      'updated_at': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
