/// Supabase project configuration.
///
/// Override at build time with:
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
class SupabaseConfig {
  SupabaseConfig._();

  /// Must match Project Settings → API → Project URL (no typos).
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rwvwxlextydfxuaiehcu.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_rnwwYkIukL6EKKu4m0tS0Q_3xbl9KtP',
  );

  /// Used for email confirmation and password-reset deep links.
  /// Must also be listed in Supabase → Authentication → URL Configuration.
  static const String authRedirectTo = 'shootiq://login-callback/';
}
