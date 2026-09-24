// A small, dependency-free logging utility built on `dart:developer`'s
// `log()` — which integrates natively with `flutter run`'s console output
// and DevTools' Logging view, so no extra package is needed for something
// this app only needs to do well, not elaborately.
//
// Every layer that logs (the API client, controllers, `main.dart`) uses a
// named `AppLogger` instance rather than calling `print()` — `print()` is
// stripped in release builds' default configuration and gives no way to
// filter by source, which defeats the point of logging at all.

import 'dart:developer' as developer;

enum LogLevel {
  debug(500),
  info(800),
  warning(900),
  error(1000);

  const LogLevel(this.severity);

  /// Matches `dart:developer`'s `log(level: ...)` severity scale, so
  /// DevTools' built-in level filter works correctly on these records.
  final int severity;
}

class AppLogger {
  const AppLogger(this._name);

  final String _name;

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.debug, message, error: error, stackTrace: stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.info, message, error: error, stackTrace: stackTrace);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.warning, message, error: error, stackTrace: stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.error, message, error: error, stackTrace: stackTrace);

  void _log(LogLevel level, String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: _name,
      level: level.severity,
      error: error,
      stackTrace: stackTrace,
      time: DateTime.now(),
    );
  }
}

/// Creates a logger tagged with `name` — by convention, the owning
/// feature/module, e.g. `AppLogger('phlio.api')`, `AppLogger('phlio.auth')`.
/// Matches the backend's logger-per-module convention
/// (`logging.getLogger("phlio.social")` etc.) so a log line's origin reads
/// the same way across both halves of the stack.
AppLogger createLogger(String name) => AppLogger(name);
