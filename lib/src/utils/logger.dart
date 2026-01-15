/// Logging utility for the resilient middleware
library;

/// Log levels
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// Simple logger for resilient middleware
class Logger {
  static bool _enabled = true;
  static LogLevel _minLevel = LogLevel.info;

  /// Enable or disable logging
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Set minimum log level
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Log debug message
  static void debug(String message, [Object? error]) {
    _log(LogLevel.debug, message, error);
  }

  /// Log info message
  static void info(String message, [Object? error]) {
    _log(LogLevel.info, message, error);
  }

  /// Log warning message
  static void warning(String message, [Object? error]) {
    _log(LogLevel.warning, message, error);
  }

  /// Log error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }

  /// Internal log method
  static void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!_enabled || level.index < _minLevel.index) return;

    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase().padRight(7);

    // ignore: avoid_print
    print('[$timestamp] $levelStr: $message');

    if (error != null) {
      // ignore: avoid_print
      print('  Error: $error');
    }

    if (stackTrace != null) {
      // ignore: avoid_print
      print('  StackTrace: $stackTrace');
    }
  }
}
