/// File Transfer Model
/// 
/// Tracks the state of file transfers (both sending and receiving).
/// Supports resumable transfers with chunk tracking.

class FileTransfer {
  final int? id;
  final String transferId;         // Unique UUID for this transfer session
  final String deviceId;           // Foreign key to Device
  final String fileName;           // Original filename
  final int fileSize;             // Total file size in bytes
  final String? filePath;          // Local path (source for send, destination for receive)
  final String mimeType;
  final int direction;             // 0 = outgoing (sending), 1 = incoming (receiving)
  final int status;                // See AppConstants.TransferStatus
  final int bytesTransferred;     // Bytes completed so far
  final int lastChunkIndex;       // Last successfully transferred chunk index
  final int totalChunks;           // Total number of chunks
  final Set<int> receivedChunks;   // Set of chunk indices that have been received
  final String? checksum;          // Expected SHA-256 checksum
  final String? actualChecksum;    // Calculated checksum after completion
  final int currentSpeed;          // Current transfer speed in bytes/sec
  final int averageSpeed;         // Average speed in bytes/sec
  final DateTime? startedAt;       // When transfer started
  final DateTime? pausedAt;        // When transfer was paused
  final DateTime? resumedAt;       // When transfer was resumed
  final DateTime? completedAt;     // When transfer completed/failed
  final String? failureReason;     // Reason for failure if any
  final int retryCount;            // Number of retries attempted
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  FileTransfer({
    this.id,
    required this.transferId,
    required this.deviceId,
    required this.fileName,
    required this.fileSize,
    this.filePath,
    required this.mimeType,
    required this.direction,
    required this.status,
    this.bytesTransferred = 0,
    this.lastChunkIndex = -1,
    this.totalChunks = 0,
    Set<int>? receivedChunks,
    this.checksum,
    this.actualChecksum,
    this.currentSpeed = 0,
    this.averageSpeed = 0,
    this.startedAt,
    this.pausedAt,
    this.resumedAt,
    this.completedAt,
    this.failureReason,
    this.retryCount = 0,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : receivedChunks = receivedChunks ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from database map
  factory FileTransfer.fromMap(Map<String, dynamic> map) {
    return FileTransfer(
      id: map['id'] as int?,
      transferId: map['transfer_id'] as String,
      deviceId: map['device_id'] as String,
      fileName: map['file_name'] as String,
      fileSize: (map['file_size'] as num).toInt(),
      filePath: map['file_path'] as String?,
      mimeType: map['mime_type'] as String,
      direction: map['direction'] as int,
      status: map['status'] as int,
      bytesTransferred: (map['bytes_transferred'] as num?)?.toInt() ?? 0,
      lastChunkIndex: (map['last_chunk_index'] as num?)?.toInt() ?? -1,
      totalChunks: (map['total_chunks'] as num?)?.toInt() ?? 0,
      receivedChunks: (map['received_chunks'] as String?)
          ?.split(',')
          .where((s) => s.isNotEmpty)
          .map((s) => int.parse(s))
          .toSet(),
      checksum: map['checksum'] as String?,
      actualChecksum: map['actual_checksum'] as String?,
      currentSpeed: (map['current_speed'] as num?)?.toInt() ?? 0,
      averageSpeed: (map['average_speed'] as num?)?.toInt() ?? 0,
      startedAt: map['started_at'] != null
          ? DateTime.parse(map['started_at'] as String)
          : null,
      pausedAt: map['paused_at'] != null
          ? DateTime.parse(map['paused_at'] as String)
          : null,
      resumedAt: map['resumed_at'] != null
          ? DateTime.parse(map['resumed_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      failureReason: map['failure_reason'] as String?,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(
              jsonDecode(map['metadata']) as Map<String, dynamic>,
            )
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'transfer_id': transferId,
      'device_id': deviceId,
      'file_name': fileName,
      'file_size': fileSize,
      'file_path': filePath,
      'mime_type': mimeType,
      'direction': direction,
      'status': status,
      'bytes_transferred': bytesTransferred,
      'last_chunk_index': lastChunkIndex,
      'total_chunks': totalChunks,
      'received_chunks': receivedChunks.join(','),
      'checksum': checksum,
      'actual_checksum': actualChecksum,
      'current_speed': currentSpeed,
      'average_speed': averageSpeed,
      'started_at': startedAt?.toIso8601String(),
      'paused_at': pausedAt?.toIso8601String(),
      'resumed_at': resumedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'failure_reason': failureReason,
      'retry_count': retryCount,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get progress percentage (0.0 to 100.0)
  double get progress {
    if (fileSize <= 0) return 0.0;
    return (bytesTransferred / fileSize * 100).clamp(0.0, 100.0);
  }

  /// Get remaining bytes
  int get remainingBytes => max(0, fileSize - bytesTransferred);

  /// Check if transfer is active (in progress or paused)
  bool get isActive =>
      status == AppConstants.TransferStatus.transferring ||
      status == AppConstants.TransferStatus.paused;

  /// Check if transfer can be resumed
  bool get canResume =>
      status == AppConstants.TransferStatus.paused &&
      bytesTransferred < fileSize;

  /// Check if transfer is complete (success or failure)
  bool get isComplete =>
      status == AppConstants.TransferStatus.completed ||
      status == AppConstants.TransferStatus.failed ||
      status == AppConstants.TransferStatus.cancelled;

  /// Get estimated time remaining in seconds
  int? get estimatedTimeRemainingSeconds {
    if (!isActive || currentSpeed <= 0) return null;
    if (remainingBytes <= 0) return 0;
    return (remainingBytes / currentSpeed).ceil();
  }

  /// Get human-readable status text
  String getStatusText() {
    switch (status) {
      case AppConstants.TransferStatus.pending:
        return 'Waiting...';
      case AppConstants.TransferStatus.accepted:
        return 'Accepted';
      case AppConstants.TransferStatus.rejected:
        return 'Rejected';
      case AppConstants.TransferStatus.transferring:
        return 'Transferring...';
      case AppConstants.TransferStatus.paused:
        return 'Paused';
      case AppConstants.TransferStatus.completed:
        return 'Completed';
      case AppConstants.TransferStatus.failed:
        return 'Failed${failureReason != null ? ': $failureReason' : ''}';
      case AppConstants.TransferStatus.cancelled:
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  /// Copy with modified fields
  FileTransfer copyWith({
    int? id,
    String? transferId,
    String? deviceId,
    String? fileName,
    int? fileSize,
    String? filePath,
    String? mimeType,
    int? direction,
    int? status,
    int? bytesTransferred,
    int? lastChunkIndex,
    int? totalChunks,
    Set<int>? receivedChunks,
    String? checksum,
    String? actualChecksum,
    int? currentSpeed,
    int? averageSpeed,
    DateTime? startedAt,
    DateTime? pausedAt,
    DateTime? resumedAt,
    DateTime? completedAt,
    String? failureReason,
    int? retryCount,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FileTransfer(
      id: id ?? this.id,
      transferId: transferId ?? this.transferId,
      deviceId: deviceId ?? this.deviceId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      filePath: filePath ?? this.filePath,
      mimeType: mimeType ?? this.mimeType,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      lastChunkIndex: lastChunkIndex ?? this.lastChunkIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      receivedChunks: receivedChunks ?? this.receivedChunks,
      checksum: checksum ?? this.checksum,
      actualChecksum: actualChecksum ?? this.actualChecksum,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      startedAt: startedAt ?? this.startedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      resumedAt: resumedAt ?? this.resumedAt,
      completedAt: completedAt ?? this.completedAt,
      failureReason: failureReason ?? this.failureReason,
      retryCount: retryCount ?? this.retryCount,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

import 'dart:convert';
import '../utils/constants.dart';
import 'dart:math' show min, max;
