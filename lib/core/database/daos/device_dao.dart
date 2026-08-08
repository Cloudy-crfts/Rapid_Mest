import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../models/device.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

/// Data Access Object for Device operations
/// 
/// Handles all database CRUD operations for Bluetooth devices.

class DeviceDao {
  // Get database instance
  Future<Database> get _db async => AppDatabase.instance.database;

  // ==================== CREATE ====================

  /// Insert a new device or update if exists
  Future<Device> insertOrUpdate(Device device) async {
    final db = await _db;
    
    try {
      final existing = await getByAddress(device.bluetoothAddress);
      
      if (existing != null) {
        // Update existing device
        final updated = device.copyWith(
          id: existing.id,
          createdAt: existing.createdAt,
        );
        return await update(updated);
      } else {
        // Insert new device
        final id = await db.insert(
          'devices',
          device.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return device.copyWith(id: id);
      }
    } catch (e) {
      AppLogger.error('Failed to insert/update device', 'DeviceDAO', e);
      rethrow;
    }
  }

  // ==================== READ ====================

  /// Get device by ID
  Future<Device?> getById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return Device.fromMap(maps.first);
  }

  /// Get device by Bluetooth address
  Future<Device?> getByAddress(String address) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'bluetooth_address = ?',
      whereArgs: [address],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return Device.fromMap(maps.first);
  }

  /// Get all saved devices
  Future<List<Device>> getSavedDevices() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'is_saved = ? AND is_blocked = ?',
      whereArgs: [1, 0],
      orderBy: 'last_interaction_at DESC NULLS LAST',
    );
    
    return maps.map((map) => Device.fromMap(map)).toList();
  }

  /// Get all devices with recent interactions (for chat list)
  Future<List<Device>> getDevicesWithRecentChats() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT d.* FROM devices d
      INNER JOIN messages m ON d.bluetooth_address = m.device_id
      WHERE d.is_blocked = 0 AND m.is_deleted_for_me = 0
      GROUP BY d.bluetooth_address
      ORDER BY MAX(m.created_at) DESC
    ''');
    
    return maps.map((map) => Device.fromMap(map)).toList();
  }

  /// Get blocked devices
  Future<List<Device>> getBlockedDevices() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'is_blocked = ?',
      whereArgs: [1],
    );
    
    return maps.map((map) => Device.fromMap(map)).toList();
  }

  /// Search devices by name or alias
  Future<List<Device>> searchDevices(String query) async {
    final db = await _db;
    final searchPattern = '%$query%';
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: '''(alias LIKE ? OR last_known_name LIKE ? OR device_name LIKE ? 
                OR bluetooth_address LIKE ?)
                AND is_blocked = 0''',
      whereArgs: [searchPattern, searchPattern, searchPattern, searchPattern],
      orderBy: 'is_saved DESC, last_interaction_at DESC NULLS LAST',
    );
    
    return maps.map((map) => Device.fromMap(map)).toList();
  }

  /// Check if device is blocked
  Future<bool> isDeviceBlocked(String address) async {
    final device = await getByAddress(address);
    return device?.isBlocked ?? false;
  }

  /// Get total count of saved devices
  Future<int> getSavedCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM devices WHERE is_saved = 1'
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== UPDATE ====================

  /// Update an existing device
  Future<Device> update(Device device) async {
    final db = await _db;
    
    await db.update(
      'devices',
      device.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [device.id],
    );
    
    return device;
  }

  /// Update device alias
  Future<void> updateAlias(String address, String newAlias) async {
    final db = await _db;
    await db.update(
      'devices',
      {'alias': newAlias, 'updated_at': DateTime.now().toIso8601String()},
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
  }

  /// Mark device as saved/unsaved
  Future<void> setSaved(String address, bool isSaved) async {
    final db = await _db;
    await db.update(
      'devices',
      {'is_saved': isSaved ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
  }

  /// Block/unblock a device
  Future<void> setBlocked(String address, bool isBlocked) async {
    final db = await _db;
    await db.update(
      'devices',
      {'is_blocked': isBlocked ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
    
    AppLogger.security('Device ${isBlocked ? "blocked" : "unblocked"}: $address');
  }

  /// Update last connected timestamp
  Future<void> updateLastConnected(String address) async {
    final db = await _db;
    await db.update(
      'devices',
      {
        'last_connected_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
  }

  /// Update last interaction timestamp and increment stats
  Future<void> recordInteraction({
    required String address,
    bool sentMessage = false,
    bool receivedMessage = false,
    bool transferredFile = false,
    int bytesTransferred = 0,
  }) async {
    final db = await _db;
    
    final updates = <String, dynamic>{
      'last_interaction_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (sentMessage) {
      updates['total_messages_sent'] = 'total_messages_sent + 1';
    }
    if (receivedMessage) {
      updates['total_messages_received'] = 'total_messages_received + 1';
    }
    if (transferredFile) {
      updates['total_files_transferred'] = 'total_files_transferred + 1';
      updates['total_bytes_transferred'] = 'total_bytes_transferred + $bytesTransferred';
    }
    
    // Use raw SQL for incrementing counters
    final setClauses = [];
    final args = <dynamic>[];
    
    updates.forEach((key, value) {
      if (value is String && value.contains('+')) {
        setClauses.add('$key = $value');
      } else {
        setClauses.add('$key = ?');
        args.add(value);
      }
    });
    args.add(address);
    
    await db.rawUpdate(
      'UPDATE devices SET ${setClauses.join(', ')} WHERE bluetooth_address = ?',
      args,
    );
  }

  /// Store public key for E2E encryption
  Future<void> storePublicKey(String address, String publicKey) async {
    final db = await _db;
    await db.update(
      'devices',
      {
        'public_key': publicKey,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
    
    AppLogger.crypto('Public key stored for device: $address');
  }

  /// Get public key for a device
  Future<String?> getPublicKey(String address) async {
    final device = await getByAddress(address);
    return device?.publicKey;
  }

  // ==================== DELETE ====================

  /// Delete a device and all associated data
  Future<int> delete(int id) async {
    final db = await _db;
    return await db.delete(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete device by address
  Future<int> deleteByAddress(String address) async {
    final db = await _db;
    return await db.delete(
      'devices',
      where: 'bluetooth_address = ?',
      whereArgs: [address],
    );
  }

  /// Delete all unsaved devices (cleanup)
  Future<int> cleanupUnsavedDevices({int olderThanDays = 30}) async {
    final db = await _db;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    
    return await db.delete(
      'devices',
      where: 'is_saved = 0 AND (first_seen_at IS NULL OR first_seen_at < ?)',
      whereArgs: [cutoffDate],
    );
  }
}
