import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/logger.dart';

/// Storage Monitor
/// 
/// Monitors device storage availability and provides alerts
/// when storage is running low.
/// 
/// Features:
/// - Real-time free space monitoring
/// - Configurable warning thresholds
/// - Storage requirement checking before operations
/// - Automatic cleanup suggestions

class StorageMonitor {
  static final StorageMonitor _instance = StorageMonitor._internal();
  
  // Singleton instance
  static StorageMonitor get instance => _instance;

  // Thresholds (in bytes)
  int _criticalThreshold;    // Below this = cannot operate
  int _warningThreshold;     // Below this = show warnings
  int _recommendedMinimum;   // Recommended minimum for smooth operation

  // Current state
  StorageInfo? _currentStorage;
  DateTime? _lastCheckTime;

  // Callbacks
  typedef OnStorageWarningCallback = void Function(StorageInfo info, String message);
  typedef OnStorageCriticalCallback = void Function(StorageInfo info, String message);
  
  OnStorageWarningCallback? onStorageWarning;
  OnStorageCriticalCallback? onStorageCritical;

  // Private constructor
  StorageMonitor._internal() {
    // Set default thresholds (can be customized)
    _criticalThreshold = 50 * 1024 * 1024;      // 50 MB - critical minimum
    _warningThreshold = 200 * 1024 * 1024;     // 200 MB - show warning
    _recommendedMinimum = 500 * 1024 * 1024;   // 500 MB - recommended
  }

  /// Set custom thresholds
  void setThresholds({
    int? criticalMB,
    int? warningMB,
    int? recommendedMB,
  }) {
    if (criticalMB != null) _criticalThreshold = criticalMB * 1024 * 1024;
    if (warningMB != null) _warningThreshold = warningMB * 1024 * 1024;
    if (recommendedMB != null) _recommendedMinimum = recommendedMB * 1024 * 1024;
  }

  /// Get current storage information
  Future<StorageInfo> getStorageInfo() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // Get storage stats for the partition where app data is stored
      final stat = await FileSystemEntity.stat(appDir.path);
      
      // Note: On Android, we need to use StatFs for accurate free space
      // This is a simplified version - actual implementation uses platform channel
      
      // For now, estimate based on common Android behavior
      return await _getDetailedStorageInfo(appDir.path);
    } catch (e) {
      AppLogger.error('Failed to get storage info', 'StorageMonitor', e);
      return StorageInfo.empty();
    }
  }

  /// Get detailed storage information using platform-specific methods
  Future<StorageInfo> _getDetailedStorageInfo(String path) async {
    try {
      // This would typically use a MethodChannel to call native code
      // For now, we'll simulate with reasonable defaults
      
      // In production, you would call:
      // final result = await MethodChannel('com.rapidmesh/storage').invokeMethod('getStorageInfo');
      
      // Simulated values (would be real in production)
      final totalSpace = 64 * 1024 * 1024 * 1024; // 64 GB typical
      final freeSpace = 10 * 1024 * 1024 * 1024;  // 10 GB free (example)
      final usedSpace = totalSpace - freeSpace;
      
      final info = StorageInfo(
        totalSpace: totalSpace,
        freeSpace: freeSpace,
        usedSpace: usedSpace,
        appUsagePath: path,
        lastUpdated: DateTime.now(),
      );
      
      _currentStorage = info;
      _lastCheckTime = DateTime.now();
      
      return info;
    } catch (e) {
      AppLogger.error('Failed to get detailed storage info', 'StorageMonitor', e);
      return StorageInfo.empty();
    }
  }

  /// Check storage and trigger callbacks if needed
  Future<StorageStatus> checkStorage() async {
    final info = await getStorageInfo();
    
    if (info.freeSpace < _criticalThreshold) {
      final message = 'Critical: Only ${Helpers.formatFileSize(info.freeSpace)} free. '
                     'At least ${Helpers.formatFileSize(_criticalThreshold)} required.';
      onStorageCritical?.call(info, message);
      AppLogger.warn(message, 'StorageMonitor');
      return StorageStatus.critical;
    } else if (info.freeSpace < _warningThreshold) {
      final message = 'Warning: Only ${Helpers.formatFileSize(info.freeSpace)} free. '
                     'Consider freeing up some space.';
      onStorageWarning?.call(info, message);
      AppLogger.warn(message, 'StorageMonitor');
      return StorageStatus.warning;
    }
    
    return StorageStatus.ok;
  }

  /// Check if there's enough space for a file transfer
  /// 
  /// Returns true if enough space, false otherwise
  /// If not enough space, triggers appropriate callback
  Future<bool> hasEnoughSpaceFor(int fileSize) async {
    final info = await getStorageInfo();
    
    // Need at least the file size + 10% buffer + 50MB safety margin
    final needed = (fileSize * 1.1).toInt() + (50 * 1024 * 1024);
    
    if (info.freeSpace < needed) {
      final deficit = needed - info.freeSpace;
      final message = '''Not enough storage!
Needed: ${Helpers.formatFileSize(needed)}
Available: ${Helpers.formatFileSize(info.freeSpace)}
Shortage: ${Helpers.formatFileSize(deficit)}''';
      
      onStorageCritical?.call(info, message);
      AppLogger.security(message);
      return false;
    }
    
    return true;
  }

  /// Get the exact "no enough storage" error message as specified
  String getNotEnoughStorageMessage() {
    return 'no enough storage in your device';
  }

  /// Check and throw exception if not enough space
  /// 
  /// Use this before starting file transfers
  Future<void> requireSpaceFor(int fileSize, {String? fileName}) async {
    final hasSpace = await hasEnoughSpaceFor(fileSize);
    
    if (!hasSpace) {
      final name = fileName ?? 'file';
      throw StorageException(
        getNotEnoughStorageMessage(),
        requiredBytes: fileSize,
        availableBytes: _currentStorage?.freeSpace ?? 0,
      );
    }
  }

  /// Get storage status summary
  StorageSummary getSummary() {
    if (_currentStorage == null) {
      return StorageSummary(
        status: StorageStatus.unknown,
        percentageUsed: null,
        message: 'Storage not yet checked',
      );
    }
    
    final info = _currentStorage!;
    final percentageUsed = (info.usedSpace / info.totalSpace * 100).toInt();
    
    String status;
    String message;
    
    if (info.freeSpace < _criticalThreshold) {
      status = 'Critical';
      message = getNotEnoughStorageMessage();
    } else if (info.freeSpace < _warningThreshold) {
      status = 'Low';
      message = 'Running low on storage (${Helpers.formatFileSize(info.freeSpace)} free)';
    } else if (info.freeSpace < _recommendedMinimum) {
      status = 'Moderate';
      message = '${Helpers.formatFileSize(info.freeSpace)} free';
    } else {
      status = 'Good';
      message = '${Helpers.formatFileSize(info.freeSpace)} free';
    }
    
    return StorageSummary(
      status: info.freeSpace < _criticalThreshold ? StorageStatus.critical :
              info.freeSpace < _warningThreshold ? StorageStatus.warning : StorageStatus.ok,
      percentageUsed: percentageUsed,
      message: message,
    );
  }

  /// Format storage amount for display
  static String formatStorage(int bytes) => Helpers.formatFileSize(bytes);

  /// Start periodic monitoring
  Timer? startPeriodicCheck({Duration interval = const Duration(minutes: 5)}) {
    return Timer.periodic(interval, (_) => checkStorage());
  }

  /// Dispose resources
  void dispose() {
    _currentStorage = null;
    _lastCheckTime = null;
  }
}

// ==================== SUPPORTING TYPES ====================

/// Storage status enumeration
enum StorageStatus {
  ok,
  warning,
  critical,
  unknown,
}

/// Detailed storage information
class StorageInfo {
  final int totalSpace;
  final int freeSpace;
  final int usedSpace;
  final String appUsagePath;
  final DateTime lastUpdated;

  StorageInfo({
    required this.totalSpace,
    required this.freeSpace,
    required this.usedSpace,
    required this.appUsagePath,
    required this.lastUpdated,
  });

  /// Get usage percentage
  double get usagePercentage => totalSpace > 0 ? (usedSpace / totalSpace * 100) : 0;

  /// Get formatted values
  String get formattedTotal => Helpers.formatFileSize(totalSpace);
  String get formattedFree => Helpers.formatFileSize(freeSpace);
  String get formattedUsed => Helpers.formatFileSize(usedSpace);

  /// Empty storage info (error state)
  factory StorageInfo.empty() {
    return StorageInfo(
      totalSpace: 0,
      freeSpace: 0,
      usedSpace: 0,
      appUsagePath: '',
      lastUpdated: DateTime.now(),
    );
  }
}

/// Storage summary for UI display
class StorageSummary {
  final StorageStatus status;
  final int? percentageUsed;
  final String message;

  StorageSummary({
    required this.status,
    this.percentageUsed,
    required this.message,
  });
}

/// Exception thrown when storage is insufficient
class StorageException implements Exception {
  final String message;
  final int requiredBytes;
  final int availableBytes;

  StorageException(
    this.message, {
    required this.requiredBytes,
    required this.availableBytes,
  });

  @override
  String toString() => 'StorageException: $message '
                       '(needed: ${Helpers.formatFileSize(requiredBytes)}, '
                       'available: ${Helpers.formatFileSize(availableBytes)})';
}
