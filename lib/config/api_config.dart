/// ShootIQ FastAPI backend configuration.
///
/// Override at build/run time with:
/// `--dart-define=API_URL=http://YOUR_MAC_LAN_IP:8000`
///
/// Defaults to localhost for Mac / iOS Simulator development.
/// For a physical iPhone, pass your Mac's LAN IP so the phone can reach
/// the FastAPI server (must be bound with `--host 0.0.0.0`).
class ApiConfig {
  ApiConfig._();

  /// Base URL of the ShootIQ AI server (no trailing slash).
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://192.168.1.197:8000',
  );

  /// `POST` endpoint for shot analysis.
  static String get analyzeUrl => '$baseUrl/analyze';

  /// Host portion of [baseUrl] (used when rewriting media URLs).
  static String get host {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return '127.0.0.1';
    return uri.host;
  }
}
