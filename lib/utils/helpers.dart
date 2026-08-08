import 'dart:typed_data';
import 'dart:convert';
import 'package:intl/intl.dart';

/// Rapid Mesh Helper Utilities
/// 
/// Common utility functions used throughout the application.

class Helpers {
  // Prevent instantiation
  Helpers._();

  // ==================== FORMATTING ====================

  /// Format file size to human-readable string
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.log() / 1024.log()).floor();
    i = i.clamp(0, suffixes.length - 1);
    
    final value = bytes / (1024.pow(i));
    
    if (i == 0) {
      return '${bytes.toStringAsFixed(0)} ${suffixes[i]}';
    }
    return '${value.toStringAsFixed(i > 1 ? 2 : 1)} ${suffixes[i]}';
  }

  /// Format transfer speed
  static String formatTransferSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${formatFileSize(bytesPerSecond)}/s';
  }

  /// Format duration in seconds to human-readable
  static String formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final mins = seconds ~/ 60;
      final secs = seconds % 60;
      return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
    } else {
      final hours = seconds ~/ 3600;
      final mins = (seconds % 3600) ~/ 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }

  /// Format timestamp for display
  static String formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      // Today - show time only
      return DateFormat('HH:mm').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(messageDate).inDays < 7) {
      // This week - show day name
      return DateFormat('EEEE').format(dateTime);
    } else {
      // Older - show date
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
  }

  /// Format full date and time
  static String formatDateTimeFull(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
  }

  /// Get relative time string (e.g., "5 minutes ago")
  static String getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return mins == 1 ? '1 minute ago' : '$mins minutes ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    } else if (difference.inDays < 30) {
      final days = difference.inDays;
      return days == 1 ? 'Yesterday' : '$days days ago';
    } else if (difference.inDays < 365) {
      final months = difference.inDays ~/ 30;
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = difference.inDays ~/ 365;
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }

  // ==================== FILE UTILITIES ====================

  /// Get file extension from filename
  static String getFileExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) {
      return '';
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }

  /// Get MIME type from file extension
  static String getMimeType(String filename) {
    final ext = getFileExtension(filename);
    const mimeTypes = {
      // Images
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      
      // Videos
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mkv': 'video/x-matroska',
      'mov': 'video/quicktime',
      'wmv': 'video/x-ms-wmv',
      'flv': 'video/x-flv',
      'webm': 'video/webm',
      
      // Audio
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'm4a': 'audio/mp4',
      'opus': 'audio/opus',
      
      // Documents
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'rtf': 'application/rtf',
      'odt': 'application/vnd.oasis.opendocument.text',
      
      // Archives
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
      
      // APKs
      'apk': 'application/vnd.android.package-archive',
      
      // Other
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'dart': 'application/dart',
    };
    
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  /// Check if file is an image
  static bool isImageFile(String filename) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];
    return imageExtensions.contains(getFileExtension(filename));
  }

  /// Check if file is a video
  static bool isVideoFile(String filename) {
    const videoExtensions = ['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'];
    return videoExtensions.contains(getFileExtension(filename));
  }

  /// Check if file is audio
  static bool isAudioFile(String filename) {
    const audioExtensions = ['mp3', 'wav', 'ogg', 'aac', 'flac', 'm4a', 'opus'];
    return audioExtensions.contains(getFileExtension(filename));
  }

  /// Generate unique filename with timestamp
  static String generateUniqueFilename(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = getFileExtension(originalName);
    final baseName = originalName.replaceAll('.$ext', '');
    final sanitizedBase = baseName.replaceAll(RegExp(r'[^\w\s-]'), '_');
    return '${sanitizedBase}_$timestamp.$ext';
  }

  // ==================== DATA CONVERSION ====================

  /// Convert bytes to hex string
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convert hex string to bytes
  static Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Convert int to bytes (big-endian)
  static Uint8List intToBytes(int value, {int byteLength = 4}) {
    final result = Uint8List(byteLength);
    for (var i = byteLength - 1; i >= 0; i--) {
      result[i] = value & 0xFF;
      value >>= 8;
    }
    return result;
  }

  /// Convert bytes to int (big-endian)
  static int bytesToInt(Uint8List bytes) {
    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
    }
    return value;
  }

  /// Encode string to UTF-8 bytes
  static Uint8List stringToBytes(String str) => utf8.encode(str);

  /// Decode UTF-8 bytes to string
  static String bytesToString(Uint8List bytes) => utf8.decode(bytes);

  // ==================== VALIDATION ====================

  /// Validate nickname
  static bool isValidNickname(String nickname) {
    if (nickname.isEmpty || nickname.length > 30) return false;
    // Allow letters, numbers, spaces, underscores, hyphens
    final regex = RegExp(r'^[\w\s\-]+$');
    return regex.hasMatch(nickname);
  }

  /// Sanitize input string
  static String sanitizeInput(String input) {
    // Remove control characters but keep newlines and tabs
    return input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  }

  /// Truncate text with ellipsis
  static String truncate(String text, {int maxLength = 50}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  // ==================== MATH EXTENSIONS ====================
}

/// Extension on num for logarithm
extension NumExtension on num {
  double log() => this == 0 ? 0 : (this > 0 ? _ln(this) : double.nan);
  
  static double _ln(double x) {
    // Natural logarithm approximation using Taylor series
    if (x <= 0) return double.nan;
    double sum = 0.0;
    double term = (x - 1) / (x + 1);
    double termSquared = term * term;
    var n = 1;
    while (n < 1000) {
      sum += term / n;
      term *= termSquared;
      n += 2;
      if (term.abs() < 1e-15) break;
    }
    return 2 * sum;
  }
  
  int pow(int exponent) {
    return this.toInt().pow(exponent);
  }
}

/// Extension on int for power operation
extension IntPowExtension on int {
  int pow(int exponent) {
    if (exponent == 0) return 1;
    if (exponent < 0) throw ArgumentError('Negative exponent not supported');
    int result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
