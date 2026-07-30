import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shootiq/config/supabase_config.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles Supabase email authentication and session state.
class AuthService {
  AuthService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static Session? get currentSession => _client.auth.currentSession;

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  static bool get isAuthenticated => currentUser != null;

  /// Deep-link used for email confirmation / password reset return.
  static const oauthRedirectTo = SupabaseConfig.authRedirectTo;

  /// Notifies listeners when auth session changes (for GoRouter refresh).
  static final ValueNotifier<bool> authListenable = ValueNotifier<bool>(false);

  static StreamSubscription<AuthState>? _authSub;

  static void initAuthListener() {
    authListenable.value = isAuthenticated;
    _authSub?.cancel();
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      authListenable.value = state.session != null;
      if (state.session == null) {
        ProfileService.clear();
      }
    });
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) {
    final trimmedFirst = firstName?.trim();
    final trimmedLast = lastName?.trim();

    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: oauthRedirectTo,
      data: {
        if (trimmedFirst != null && trimmedFirst.isNotEmpty)
          'first_name': trimmedFirst,
        if (trimmedLast != null && trimmedLast.isNotEmpty)
          'last_name': trimmedLast,
        if (trimmedFirst != null || trimmedLast != null)
          'full_name': [
            if (trimmedFirst != null && trimmedFirst.isNotEmpty) trimmedFirst,
            if (trimmedLast != null && trimmedLast.isNotEmpty) trimmedLast,
          ].join(' '),
      },
    );
  }

  static Future<void> resetPassword({required String email}) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: oauthRedirectTo,
    );
  }

  static Future<void> signOut() async {
    ProfileService.clear();
    await _client.auth.signOut();
  }

  /// After a successful sign-in, ensures a player profile exists and syncs
  /// local onboarding flags.
  ///
  /// Returns `true` when a **new** profile was created (send to Player Setup).
  /// Returns `false` when the profile already existed (send to Home).
  static Future<bool> completeSignIn() async {
    if (!isAuthenticated) {
      throw const AuthException('Authentication failed. Please try again.');
    }

    final created = await ProfileService.ensureProfileForCurrentUser();
    if (created) {
      await OnboardingService.setHasCompletedPlayerSetup(false);
      await OnboardingService.setHasCompletedOnboarding(false);
      return true;
    }

    await OnboardingService.setHasCompletedPlayerSetup(true);
    await OnboardingService.completeOnboarding(
      userName: ProfileService.current?.fullName,
    );
    return false;
  }

  /// Maps low-level failures into clear user-facing messages.
  static String friendlyAuthError(Object error) {
    final text = error.toString();

    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Operation not permitted') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection failed') ||
        text.contains('TimeoutException')) {
      return 'Server connection error. Cannot reach Supabase '
          '(${SupabaseConfig.url}). Check Wi‑Fi and try again.';
    }

    if (error is AuthException) {
      final message = error.message.trim();
      if (message.isEmpty) return 'Authentication failed. Please try again.';
      return message;
    }

    return 'Authentication failed. Please try again.';
  }
}
