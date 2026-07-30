/// ShootIQ FastAPI backend configuration.
///
/// Override at build/run time with:
/// `--dart-define=API_URL=http://YOUR_MAC_LAN_IP:8000` (local dev only)
///
/// Defaults to the production server (Hetzner, behind nginx + Let's
/// Encrypt HTTPS). For local backend development on a physical iPhone,
/// pass your Mac's LAN IP via `--dart-define` instead.
class ApiConfig {
  ApiConfig._();

  /// Base URL of the ShootIQ AI server (no trailing slash).
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.shootiqapp.com',
  );

  /// Shared-secret sent as `X-API-Key` on protected backend requests.
  /// Must be supplied at build time via `--dart-define=API_KEY=...` —
  /// never hardcode a real key here or commit one to source control.
  static const String apiKey = String.fromEnvironment('API_KEY');

  /// `POST` endpoint for shot analysis.
  static String get analyzeUrl => '$baseUrl/analyze';

  /// Host portion of [baseUrl] (used when rewriting media URLs).
  static String get host {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return '127.0.0.1';
    return uri.host;
  }
}
