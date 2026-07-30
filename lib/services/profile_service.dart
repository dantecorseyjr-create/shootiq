import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads and persists the authenticated user's [PlayerProfile].
///
/// Keeps a [profileListenable] so Profile UI can refresh instantly after edits.
class ProfileService {
  ProfileService._();

  static const _table = 'player_profiles';
  static const _bucket = 'shot-videos';

  static SupabaseClient get _client => Supabase.instance.client;

  /// Current in-memory profile. Null until [loadProfile] / [saveProfile].
  static final ValueNotifier<PlayerProfile?> profileListenable =
      ValueNotifier<PlayerProfile?>(null);

  static PlayerProfile? get current => profileListenable.value;

  /// Ensures a `player_profiles` row exists for the signed-in user.
  ///
  /// Returns `true` if a new row was created (first sign-in / profile create),
  /// `false` if one already existed.
  static Future<bool> ensureProfileForCurrentUser() async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to create a profile.');
    }

    try {
      final existing = await _client
          .from(_table)
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        await loadProfile(forceRefresh: true);
        return false;
      }
    } catch (error, stack) {
      debugPrint(
        'ProfileService.ensureProfileForCurrentUser lookup failed: '
        '$error\n$stack',
      );
      // Fall through and attempt create — insert may still succeed.
    }

    final seed = _seedFromLocal(user);
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final photoUrl = (meta['avatar_url'] as String?)?.trim().isNotEmpty == true
        ? (meta['avatar_url'] as String).trim()
        : (meta['picture'] as String?)?.trim();

    final displayName = () {
      final fromMeta = (meta['full_name'] as String?)?.trim() ??
          (meta['name'] as String?)?.trim() ??
          '';
      if (fromMeta.isNotEmpty) return fromMeta;
      if (seed.fullName != 'Player') return seed.fullName;
      return user.email?.split('@').first ?? 'Player';
    }();

    final parts = displayName.split(RegExp(r'\s+'));
    final firstName =
        seed.firstName.isNotEmpty ? seed.firstName : parts.first;
    final lastName = seed.lastName.isNotEmpty
        ? seed.lastName
        : (parts.length > 1 ? parts.sublist(1).join(' ') : '');

    final profile = seed.copyWith(
      userId: user.id,
      firstName: firstName,
      lastName: lastName,
      photoUrl: photoUrl ?? seed.photoUrl,
      updatedAt: DateTime.now().toUtc(),
    );

    try {
      final row = Map<String, dynamic>.from(
        await _client
            .from(_table)
            .upsert(profile.toJson(), onConflict: 'user_id')
            .select()
            .single(),
      );
      final saved = PlayerProfile.fromJson(row);
      profileListenable.value = saved;
      await _syncLocalCache(saved);
      return true;
    } catch (error, stack) {
      debugPrint(
        'ProfileService.ensureProfileForCurrentUser create failed: '
        '$error\n$stack',
      );
      // Keep a local seed so Player Setup can still proceed offline.
      profileListenable.value = profile;
      await _syncLocalCache(profile);
      return true;
    }
  }

  /// Fetches from Supabase, falling back to auth + local onboarding data.
  static Future<PlayerProfile> loadProfile({bool forceRefresh = false}) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to load a profile.');
    }

    if (!forceRefresh && profileListenable.value?.userId == user.id) {
      return profileListenable.value!;
    }

    PlayerProfile? remote;
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (row != null) {
        remote = PlayerProfile.fromJson(Map<String, dynamic>.from(row));
      }
    } catch (error, stack) {
      debugPrint('ProfileService.loadProfile remote failed: $error\n$stack');
    }

    final profile = remote ?? _seedFromLocal(user);
    profileListenable.value = profile;
    await _syncLocalCache(profile);
    return profile;
  }

  /// Validates and upserts the profile, optionally uploading a new photo.
  static Future<PlayerProfile> saveProfile(
    PlayerProfile profile, {
    File? photoFile,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to save a profile.');
    }

    var next = profile.copyWith(
      userId: user.id,
      updatedAt: DateTime.now().toUtc(),
    );

    if (photoFile != null) {
      final photoUrl = await uploadPhoto(photoFile);
      next = next.copyWith(photoUrl: photoUrl);
    }

    // Update local listeners first so Profile refreshes immediately.
    profileListenable.value = next;
    await _syncLocalCache(next);

    try {
      final savedRow = Map<String, dynamic>.from(
        await _client
            .from(_table)
            .upsert(next.toJson(), onConflict: 'user_id')
            .select()
            .single(),
      );
      final saved = PlayerProfile.fromJson(savedRow);
      profileListenable.value = saved;
      await _syncLocalCache(saved);

      try {
        await _client.auth.updateUser(
          UserAttributes(
            data: {
              'first_name': saved.firstName,
              'last_name': saved.lastName,
              'full_name': saved.fullName,
              'username': saved.username,
            },
          ),
        );
      } catch (error) {
        debugPrint('ProfileService auth metadata update failed: $error');
      }

      return saved;
    } catch (error) {
      debugPrint('ProfileService.saveProfile remote failed: $error');
      rethrow;
    }
  }

  /// Uploads an avatar to `users/{uid}/avatar/...` and returns a public URL.
  static Future<String> uploadPhoto(File file) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to upload a photo.');
    }

    final ext = p.extension(file.path).toLowerCase();
    final safeExt = (ext.isEmpty || ext.length > 5) ? '.jpg' : ext;
    final objectPath =
        'users/${user.id}/avatar/profile$safeExt';

    final contentType = switch (safeExt) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    await _client.storage.from(_bucket).upload(
          objectPath,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(objectPath);
    // Bust CDN/cache so Profile shows the new image immediately.
    return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  static PlayerProfile _seedFromLocal(User user) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final first = (meta['first_name'] as String?)?.trim() ?? '';
    final last = (meta['last_name'] as String?)?.trim() ?? '';
    final fullName = (meta['full_name'] as String?)?.trim() ?? '';

    var resolvedFirst = first;
    var resolvedLast = last;
    if (resolvedFirst.isEmpty && resolvedLast.isEmpty && fullName.isNotEmpty) {
      final parts = fullName.split(RegExp(r'\s+'));
      resolvedFirst = parts.first;
      if (parts.length > 1) {
        resolvedLast = parts.sublist(1).join(' ');
      }
    }

    if (resolvedFirst.isEmpty &&
        resolvedLast.isEmpty &&
        OnboardingService.userName != 'Player') {
      final parts = OnboardingService.userName.split(RegExp(r'\s+'));
      resolvedFirst = parts.first;
      if (parts.length > 1) {
        resolvedLast = parts.sublist(1).join(' ');
      }
    }

    final emailLocal = user.email?.split('@').first ?? 'player';
    final username = (meta['username'] as String?)?.trim().isNotEmpty == true
        ? (meta['username'] as String).trim()
        : emailLocal.replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '_').toLowerCase();

    final weightRaw = OnboardingService.weight;
    final weightMatch =
        weightRaw == null ? null : RegExp(r'(\d+)').firstMatch(weightRaw);
    final ageRaw = OnboardingService.age;

    // Map legacy "Competitive" setup value to Edit Profile "Elite".
    var skill = OnboardingService.skillLevel;
    if (skill == 'Competitive') skill = 'Elite';

    return PlayerProfile(
      userId: user.id,
      firstName: resolvedFirst,
      lastName: resolvedLast,
      username: username,
      height: OnboardingService.height,
      weight: weightMatch == null ? null : int.tryParse(weightMatch.group(1)!),
      age: ageRaw == null ? null : int.tryParse(ageRaw),
      dominantHand: OnboardingService.dominantHand == 'Ambidextrous'
          ? 'Right'
          : OnboardingService.dominantHand,
      position: OnboardingService.position,
      skillLevel: skill,
      experience: null,
      favoriteTeam: null,
      bio: null,
      photoUrl: user.userMetadata?['avatar_url'] as String?,
    );
  }

  static Future<void> _syncLocalCache(PlayerProfile profile) async {
    await OnboardingService.setUserName(profile.fullName);
    if (profile.height != null ||
        profile.weight != null ||
        profile.age != null ||
        profile.position != null ||
        profile.dominantHand != null ||
        profile.skillLevel != null) {
      await OnboardingService.savePlayerSetup(
        height: profile.height ?? OnboardingService.height ?? '',
        weight: profile.weight != null
            ? '${profile.weight} lbs'
            : (OnboardingService.weight ?? ''),
        age: profile.age?.toString() ?? OnboardingService.age ?? '',
        position: profile.position ?? OnboardingService.position ?? '',
        dominantHand:
            profile.dominantHand ?? OnboardingService.dominantHand ?? '',
        skillLevel: profile.skillLevel ?? OnboardingService.skillLevel ?? '',
      );
    }
  }

  static void clear() {
    profileListenable.value = null;
  }
}
