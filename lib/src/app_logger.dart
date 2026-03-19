import 'package:flutter/foundation.dart';

class AppLogger {
  const AppLogger._();

  static void info(
    String scope,
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _write('INFO', scope, message, data: data);
  }

  static void warn(
    String scope,
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _write('WARN', scope, message, data: data);
  }

  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final errorData = <String, Object?>{...data};
    if (error != null) {
      errorData['error'] = error;
    }

    _write('ERROR', scope, message, data: errorData);

    if (kDebugMode && stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static void _write(
    String level,
    String scope,
    String message, {
    required Map<String, Object?> data,
  }) {
    if (!kDebugMode) {
      return;
    }

    final buffer = StringBuffer('[OTPReader][$level][$scope] $message');
    if (data.isNotEmpty) {
      final details = data.entries
          .map((entry) => '${entry.key}=${_formatValue(entry.value)}')
          .join(', ');
      buffer.write(' | ');
      buffer.write(details);
    }

    debugPrint(buffer.toString());
  }

  static String _formatValue(Object? value) {
    if (value == null) {
      return 'null';
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is Iterable<Object?>) {
      return '[${value.map(_formatValue).join(', ')}]';
    }

    if (value is Map<Object?, Object?>) {
      return '{${value.entries.map((entry) => '${entry.key}:${_formatValue(entry.value)}').join(', ')}}';
    }

    return value.toString();
  }
}