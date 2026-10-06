// App configuration — the one place environment-specific values live.
//
// Overridable at build/run time via `--dart-define`, so the same code
// points at a local backend during development and a real deployment in
// staging/production without an `if` anywhere else in the app.
//
//   flutter run --dart-define=API_BASE_URL=https://api.phlio.app/api/v1

abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // 10.0.2.2 is how the Android emulator reaches the host machine's
    // localhost; iOS simulators and desktop can use localhost directly.
    // Override with --dart-define for a physical device or real backend.
    // switch to 'http://192.168.1.6:8000/api/v1' for actual Androi device
    defaultValue: 'http://localhost:8000/api/v1',
  );

  static const bool enableRequestLogging = bool.fromEnvironment(
    'ENABLE_REQUEST_LOGGING',
    defaultValue: true,
  );

  /// Origin the API is served from (apiBaseUrl minus the `/api/v1` prefix).
  /// Uploaded room files come back as origin-relative `/media/...` urls;
  /// join them here before handing them to image loaders.
  static String get apiOrigin {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return base.replaceAll(RegExp(r'/api/v1$'), '');
  }

  static String mediaUrl(String relativeUrl) =>
      relativeUrl.startsWith('http') ? relativeUrl : '$apiOrigin$relativeUrl';
}
