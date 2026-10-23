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
    // Physical Android development uses an explicit IPv4 USB tunnel:
    // adb reverse tcp:8000 tcp:8000. Use a hosted URL for standalone builds.
    defaultValue: 'http://127.0.0.1:8000/api/v1',
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
