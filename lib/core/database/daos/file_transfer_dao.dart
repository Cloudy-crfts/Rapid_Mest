import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../models/file_transfer.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

/// Data Access Object for File Transfer operations
/// 
/// Handles all database CRUD operations for file transfers.
/// Tracks transfer state, progress, and chunk information for resumable transfers.

class FileTransferDao {
  // Get database instance
  Future<Database> get _db async => AppDatabase.instance.database;

  // ==================== CREATE ====================

  /// Insert a new file transfer record
  Future<FileTransfer> insert(FileTransfer transfer) async {
    final db = await _db;
    
    try {
      final id = await db.insert(
        'file_transfers',
        transfer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      AppLogger.debug('FileTransfer inserted: ${transfer.transferId}', 'TransferDAO');
      return transfer.copyWith(id: id);
    } catch (e) {
      AppLogger.error('Failed to insert file transfer', 'TransferDAO', e);
      rethrow;
    }
  }

  // ==================== READ ====================

  /// Get transfer by ID
  Future<FileTransfer?> getById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return FileTransfer.fromMap(maps.first);
  }

  /// Get transfer by unique transfer ID
  Future<FileTransfer?> getByTransferId(String transferId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: 'transfer_id = ?',
      whereArgs: [transferId],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return FileTransfer.fromMap(maps.first);
  }

  /// Get all transfers for a device
  Future<List<FileTransfer>> getByDevice(String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => FileTransfer.fromMap(map)).toList();
  }

  /// Get active (in-progress or paused) transfers
  Future<List<FileTransfer>> getActiveTransfers() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: '''status IN (?, ?)''',
      whereArgs: [
        AppConstants.TransferStatus.transferring,
        AppConstants.TransferStatus.paused,
      ],
      orderBy: 'created_at ASC',
    );
    
    return maps.map((map) => FileTransfer.fromMap(map)).toList();
  }

  /// Get active transfers for a specific device
  Future<List<FileTransfer>> getActiveTransfersForDevice(String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: '''device_id = ? AND status IN (?, ?)''',
      whereArgs: [
        deviceId,
        AppConstants.TransferStatus.transferring,
        AppConstants.TransferStatus.paused,
      ],
      orderBy: 'created_at ASC',
    );
    
    return maps.map((map) => FileTransfer.fromMap(map)).toList();
  }

  /// Get completed transfers (for history)
  Future<List<FileTransfer>> getCompletedTransfers({
    String? deviceId,
    int? limit,
  }) async {
    final db = await _db;
    
    String whereClause = '''status IN (?, ?, ?, ?)''';
    List<dynamic> whereArgs = [
      AppConstants.TransferStatus.completed,
      AppConstants.TransferStatus.failed,
      AppConstants.TransferStatus.cancelled,
      AppConstants.TransferStatus.rejected,
    ];
    
    if (deviceId != null) {
      whereClause += ' AND device_id = ?';
      whereArgs.add(deviceId);
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'completed_at DESC NULLS LAST',
      limit: limit,
    );
    
    return maps.map((map) => FileTransfer.fromMap(map)).toList();
  }

  /// Get pending transfers waiting for acceptance
  Future<List<FileTransfer>> getPendingTransfers() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: 'status = ?',
      whereArgs: [AppConstants.TransferStatus.pending],
      orderBy: 'created_at ASC',
    );
    
    return maps.map((map) => FileTransfer.fromMap(map)).toList();
  }

  /// Get paused transfers that can be resumed
  Future<List<FileTransfer>> getResumableTransfers() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: '''status = ?''',
      whereArgs: [AppConstants.TransferStatus.paused],
      orderBy: 'updated_at DESC',
    );
    
    // Filter to only those that can actually be resumed
    return maps
        .map((map) => FileTransfer.fromMap(map))
        .where((t) => t.canResume)
        .toList();
  }

  /// Check if there's an existing incomplete transfer for a file
  Future<FileTransfer?> getIncompleteTransfer(String fileName, String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'file_transfers',
      where: '''file_name = ? 
                AND device_id = ? 
                AND status IN (?, ?)
                AND bytes_transferred < file_size''',
      whereArgs: [
        fileName,
        deviceId,
        AppConstants.TransferStatus.transferring,
        AppConstants.TransferStatus.paused,
      ],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return FileTransfer.fromMap(maps.first);
  }

  // ==================== UPDATE ====================

  /// Update a file transfer record
  Future<FileTransfer> update(FileTransfer transfer) async {
    final db = await _db;
    
    await db.update(
      'file_transfers',
      transfer.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [transfer.id],
    );
    
    return transfer;
  }

  /// Update transfer status
  Future<void> updateStatus(int transferId, int newStatus, {String? failureReason}) async {
    final db = await _db;
    
    Map<String, dynamic> updates = {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    // Set timestamp based on status
    switch (newStatus) {
      case AppConstants.TransferStatus.transferring:
        updates['started_at'] ??= DateTime.now().toIso8601String();
        break;
      case AppConstants.TransferStatus.paused:
        updates['paused_at'] = DateTime.now().toIso8601String();
        break;
      case AppConstants.TransferStatus.transferring: // Resuming from pause
        updates['resumed_at'] = DateTime.now().toIso8601String();
        break;
      case AppConstants.TransferStatus.completed:
      case AppConstants.TransferStatus.failed:
      case AppConstants.TransferStatus.cancelled:
      case AppConstants.TransferStatus.rejected:
        updates['completed_at'] = DateTime.now().toIso8601String();
        if (failureReason != null) {
          updates['failure_reason'] = failureReason;
        }
        break;
    }
    
    await db.update(
      'file_transfers',
      updates,
      where: 'id = ?',
      whereArgs: [transferId],
    );
  }

  /// Update transfer progress
  Future<void> updateProgress({
    required int transferId,
    required long bytesTransferred,
    required long lastChunkIndex,
    Set<int>? receivedChunks,
    int? currentSpeed,
    long? averageSpeed,
  }) async {
    final db = await _db;
    
    Map<String, dynamic> updates = {
      'bytes_transferred': bytesTransferred,
      'last_chunk_index': lastChunkIndex,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (receivedChunks != null) {
      updates['received_chunks'] = receivedChunks.join(',');
    }
    if (currentSpeed != null) {
      updates['current_speed'] = currentSpeed;
    }
    if (averageSpeed != null) {
      updates['average_speed'] = averageSpeed;
    }
    
    await db.update(
      'file_transfers',
      updates,
      where: 'id = ?',
      whereArgs: [transferId],
    );
  }

  /// Record a received chunk
  Future<void> recordChunkReceived({
    required int transferId,
    required int chunkIndex,
    Set<int> allReceivedChunks,
    long totalBytesSoFar,
  }) async {
    final db = await _db;
    
    await db.update(
      'file_transfers',
      {
        'bytes_transferred': totalBytesSoFar,
        'last_chunk_index': chunkIndex,
        'received_chunks': allReceivedChunks.join(','),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [transferId],
    );
  }

  /// Accept a pending transfer
  Future<void> acceptTransfer(int transferId) async {
    await updateStatus(transferId, AppConstants.TransferStatus.accepted);
  }

  /// Reject a pending transfer
  Future<void> rejectTransfer(int transferId) async {
    await updateStatus(transferId, AppConstants.TransferStatus.rejected);
  }

  /// Pause a transfer
  Future<void> pauseTransfer(int transferId) async {
    await updateStatus(transferId, AppConstants.TransferStatus.paused);
  }

  /// Resume a paused transfer
  Future<void> resumeTransfer(int transferId) async {
    await updateStatus(transferId, AppConstants.TransferStatus.transferring);
  }

  /// Complete a transfer successfully
  Future<void> completeTransfer(int transferId, {String? actualChecksum}) async {
    final db = await _db;
    
    await db.update(
      'file_transfers',
      {
        'status': AppConstants.TransferStatus.completed,
        'actual_checksum': actualChecksum,
        'bytes_transferred': 'file_size', // Set to full size
        'completed_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [transferId],
    );
    
    AppLogger.info('Transfer $transferId completed', 'TransferDAO');
  }

  /// Fail a transfer with reason
  Future<void> failTransfer(int transferId, String reason) async {
    await updateStatus(transferId, AppConstants.TransferStatus.failed, failureReason: reason);
    AppLogger.warn('Transfer $transferId failed: $reason', 'TransferDAO');
  }

  /// Cancel a transfer
  Future<void> cancelTransfer(int transferId) async {
    await updateStatus(transferId, AppConstants.TransferStatus.cancelled);
  }

  /// Increment retry count
  Future<void> incrementRetryCount(int transferId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE file_transfers SET 
        retry_count = retry_count + 1,
        updated_at = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), transferId]);
  }

  /// Store expected checksum before transfer starts
  Future<void> setExpectedChecksum(int transferId, String checksum) async {
    final db = await _db;
    await db.update(
      'file_transfers',
      {'checksum': checksum, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [transferId],
    );
  }

  // ==================== DELETE ====================

  /// Delete a transfer record
  Future<int> delete(int id) async {
    final db = await _db;
    return await db.delete(
      'file_transfers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete transfer by transfer ID
  Future<int> deleteByTransferId(String transferId) async {
    final db = await _db;
    return await db.delete(
      'file_transfers',
      where: 'transfer_id = ?',
      whereArgs: [transferId],
    );
  }

  /// Clear old completed transfers (cleanup)
  Future<int> cleanupOldTransfers({int olderThanDays = 7}) async {
    final db = await _db;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    
    return await db.delete(
      'file_transfers',
      where: '''status IN (?, ?, ?, ?) 
                AND (completed_at IS NOT NULL AND completed_at < ?)''',
      whereArgs: [
        AppConstants.TransferStatus.completed,
        AppConstants.TransferStatus.failed,
        AppConstants.TransferStatus.cancelled,
        AppConstants.TransferStatus.rejected,
        cutoffDate,
      ],
    );
  }

  // ==================== STATISTICS ====================

  /// Get total transferred bytes (all time)
  Future<long> getTotalTransferredBytes() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(bytes_transferred), 0) as total 
      FROM file_transfers 
      WHERE status = ${AppConstants.TransferStatus.completed}
    ''');
    
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Get number of active transfers
  Future<int> getActiveTransferCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM file_transfers 
      WHERE status IN (?, ?)
    ''', [
      AppConstants.TransferStatus.transferring,
      AppConstants.TransferStatus.paused,
    ]);
    
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
