import 'dart:developer' as developer;
import 'package:logger/logger.dart';

/// Rapid Mesh Logger Utility
/// 
/// Provides structured logging throughout the application.
/// In release builds, verbose logs are suppressed.

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  // Prevent instantiation
  AppLogger._();

  /// Log debug information (development only)
  static void debug(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    if (tag != null) {
      _logger.d('[$tag] $message', error: error, stackTrace: stackTrace);
    } else {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
    
    // Also log to developer console for debugging
    developer.log(message, name: tag ?? 'RapidMesh', level: 500, error: error, stackTrace: stackTrace);
  }

  /// Log informational messages
  static void info(String message, [String? tag]) {
    if (tag != null) {
      _logger.i('[$tag] $message');
    } else {
      _logger.i(message);
    }
    
    developer.log(message, name: tag ?? 'RapidMesh', level: 800);
  }

  /// Log warnings
  static void warn(String message, [String? tag, Object? error]) {
    if (tag != null) {
      _logger.w('[$tag] $message', error: error);
    } else {
      _logger.w(message, error: error);
    }
    
    developer.log(message, name: tag ?? 'RapidMesh', level: 900, error: error);
  }

  /// Log errors
  static void error(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    if (tag != null) {
      _logger.e('[$tag] $message', error: error, stackTrace: stackTrace);
    } else {
      _logger.e(message, error: error, stackTrace: stackTrace);
    }
    
    developer.log(message, name: tag ?? 'RapidMesh', level: 1000, error: error, stackTrace: stackTrace);
  }

  /// Log fatal errors
  static void fatal(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    if (tag != null) {
      _logger.f('[$tag] $message', error: error, stackTrace: stackTrace);
    } else {
      _logger.f(message, error: error, stackTrace: stackTrace);
    }
    
    developer.log(message, name: tag ?? 'RapidMesh', level: 1200, error: error, stackTrace: stackTrace);
  }

  /// Log Bluetooth-specific events
  static void bluetooth(String message, {Object? data}) {
    _logger.i('[🔵 BT] $message');
    if (data != null) {
      _logger.d('[🔵 BT] Data: $data');
    }
  }

  /// Log file transfer events
  static void transfer(String message, {Object? data}) {
    _logger.i('[📁 Transfer] $message');
    if (data != null) {
      _logger.d('[📁 Transfer] Data: $data');
    }
  }

  /// Log security-related events
  static void security(String message) {
    _logger.w('🔒 [Security] $message');
    developer.log('🔒 Security: $message', name: 'RapidMesh-Security', level: 950);
  }

  /// Log encryption/decryption operations
  static void crypto(String message) {
    _logger.d('🔐 [Crypto] $message');
  }
}
