import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../models/message.dart';
import '../../../utils/constants.dart';
import '../../../utils/logger.dart';

/// Data Access Object for Message operations
/// 
/// Handles all database CRUD operations for chat messages.
/// Supports "Delete for me" and "Delete for everyone" functionality.

class MessageDao {
  // Get database instance
  Future<Database> get _db async => AppDatabase.instance.database;

  // ==================== CREATE ====================

  /// Insert a new message
  Future<Message> insert(Message message) async {
    final db = await _db;
    
    try {
      final id = await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      AppLogger.debug('Message inserted: $id', 'MessageDAO');
      return message.copyWith(id: id);
    } catch (e) {
      AppLogger.error('Failed to insert message', 'MessageDAO', e);
      rethrow;
    }
  }

  /// Insert multiple messages in a transaction
  Future<List<Message>> insertBatch(List<Message> messages) async {
    final db = await _db;
    
    return await db.transaction((txn) async {
      final insertedMessages = <Message>[];
      
      for (final message in messages) {
        final id = await txn.insert(
          'messages',
          message.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        insertedMessages.add(message.copyWith(id: id));
      }
      
      return insertedMessages;
    });
  }

  // ==================== READ ====================

  /// Get message by ID
  Future<Message?> getById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return Message.fromMap(maps.first);
  }

  /// Get messages for a device (paginated)
  Future<List<Message>> getByDevice({
    required String deviceId,
    int? limit,
    int? offset,
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    
    String whereClause = 'device_id = ?';
    List<dynamic> whereArgs = [deviceId];
    
    if (!includeDeleted) {
      whereClause += ' AND is_deleted_for_me = 0';
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );
    
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  /// Get latest N messages for a device
  Future<List<Message>> getLatestByDevice(String deviceId, {int count = 50}) async {
    return getByDevice(deviceId: deviceId, limit: count);
  }

  /// Get unread message count for a device
  Future<int> getUnreadCount(String deviceId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM messages 
      WHERE device_id = ? 
        AND is_outgoing = 0 
        AND status >= ${MessageStatus.delivered}
        AND read_at IS NULL
        AND is_deleted_for_me = 0
    ''', [deviceId]);
    
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total unread count across all devices
  Future<int> getTotalUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM messages 
      WHERE is_outgoing = 0 
        AND status >= ${MessageStatus.delivered}
        AND read_at IS NULL
        AND is_deleted_for_me = 0
    ''');
    
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get last message for a device (for chat list preview)
  Future<Message?> getLastMessage(String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'device_id = ? AND is_deleted_for_me = 0',
      whereArgs: [deviceId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return Message.fromMap(maps.first);
  }

  /// Get queued/sending messages for a device
  Future<List<Message>> getQueuedMessages(String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: '''device_id = ? 
                AND status IN (?, ?, ?)
                AND is_outgoing = 1
                AND is_deleted_for_me = 0''',
      whereArgs: [
        deviceId,
        MessageStatus.queued,
        MessageStatus.sending,
        MessageStatus.failed,
      ],
      orderBy: 'created_at ASC',
    );
    
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  /// Search messages by content
  Future<List<Message>> searchMessages(String query, {String? deviceId}) async {
    final db = await _db;
    final searchPattern = '%$query%';
    
    String whereClause = '(content LIKE ? OR file_name LIKE ?)';
    List<dynamic> whereArgs = [searchPattern, searchPattern];
    
    if (deviceId != null) {
      whereClause += ' AND device_id = ?';
      whereArgs.add(deviceId);
    }
    
    whereClause += ' AND is_deleted_for_me = 0';
    
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  /// Get messages by type
  Future<List<Message>> getByType(int messageType, {String? deviceId}) async {
    final db = await _db;
    
    String whereClause = 'message_type = ? AND is_deleted_for_me = 0';
    List<dynamic> whereArgs = [messageType];
    
    if (deviceId != null) {
      whereClause += ' AND device_id = ?';
      whereArgs.add(deviceId);
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  /// Get media messages (images, videos, audio)
  Future<List<Message>> getMediaMessages(String deviceId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: '''device_id = ? 
                AND message_type IN (?, ?, ?)
                AND file_path IS NOT NULL
                AND file_path != ''
                AND is_deleted_for_me = 0''',
      whereArgs: [
        deviceId,
        MessageType.image,
        MessageType.video,
        MessageType.audio,
      ],
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => Message.fromMap(map)).toList();
  }

  // ==================== UPDATE ====================

  /// Update message status by wire-level message id (used for delivery acks).
  Future<void> updateStatusByMessageId(String messageId, int newStatus) async {
    final db = await _db;

    Map<String, dynamic> updates = {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    switch (newStatus) {
      case MessageStatus.delivered:
        updates['delivered_at'] = DateTime.now().toIso8601String();
        break;
      case MessageStatus.read:
        updates['read_at'] = DateTime.now().toIso8601String();
        break;
    }

    await db.update(
      'messages',
      updates,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  /// Get a single message by its wire-level id.
  Future<Message?> getByMessageId(String messageId) async {
    final db = await _db;
    final maps = await db.query(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Message.fromMap(maps.first);
  }


  /// Update an existing message
  Future<Message> update(Message message) async {
    final db = await _db;
    
    await db.update(
      'messages',
      message.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
    
    return message;
  }

  /// Update message status
  Future<void> updateStatus(int messageId, int newStatus) async {
    final db = await _db;
    
    Map<String, dynamic> updates = {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    // Set timestamp based on status
    switch (newStatus) {
      case MessageStatus.delivered:
        updates['delivered_at'] = DateTime.now().toIso8601String();
        break;
      case MessageStatus.read:
        if (updates['delivered_at'] == null) {
          updates['delivered_at'] = DateTime.now().toIso8601String();
        }
        updates['read_at'] = DateTime.now().toIso8601String();
        break;
    }
    
    await db.update(
      'messages',
      updates,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Mark message as delivered
  Future<void> markAsDelivered(int messageId) async {
    await updateStatus(messageId, MessageStatus.delivered);
  }

  /// Mark message as read
  Future<void> markAsRead(int messageId) async {
    await updateStatus(messageId, MessageStatus.read);
  }

  /// Mark all messages from a device as read
  Future<void> markAllAsRead(String deviceId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    
    await db.rawUpdate('''
      UPDATE messages SET 
        status = ${MessageStatus.read},
        delivered_at = CASE WHEN delivered_at IS NULL THEN ? ELSE delivered_at END,
        read_at = ?,
        updated_at = ?
      WHERE device_id = ? 
        AND is_outgoing = 0 
        AND read_at IS NULL
        AND is_deleted_for_me = 0
    ''', [now, now, now, deviceId]);
  }

  /// Mark outgoing message as sent (delivered to BT stack)
  Future<void> markAsSent(int messageId) async {
    await updateStatus(messageId, MessageStatus.sent);
  }

  /// Mark outgoing message as failed
  Future<void> markAsFailed(int messageId) async {
    await updateStatus(messageId, MessageStatus.failed);
  }

  /// Mark message as sending (in progress)
  Future<void> markAsSending(int messageId) async {
    await updateStatus(messageId, MessageStatus.sending);
  }

  // ==================== DELETE OPERATIONS ====================

  /// Delete message only on this device ("Delete for me")
  Future<void> deleteForMe(int messageId) async {
    final db = await _db;
    
    await db.update(
      'messages',
      {
        'is_deleted_for_me': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    
    AppLogger.debug('Message $messageId deleted for me', 'MessageDAO');
  }

  /// Mark message for deletion on all devices ("Delete for everyone")
  /// This sends a delete command to the other device too
  Future<void> deleteForEveryone(int messageId) async {
    final db = await _db;
    
    await db.update(
      'messages',
      {
        'is_deleted_for_everyone': 1,
        'is_deleted_for_me': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    
    AppLogger.debug('Message $messageId deleted for everyone', 'MessageDAO');
  }

  /// Handle incoming "delete for everyone" from another device
  Future<void> handleRemoteDeleteForEveryone(String remoteMessageId) async {
    final db = await _db;
    
    await db.update(
      'messages',
      {
        'is_deleted_for_everyone': 1,
        'is_deleted_for_me': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [remoteMessageId],
    );
    
    AppLogger.security('Message remotely deleted for everyone: $remoteMessageId');
  }

  /// Permanently delete a message from database
  Future<int> permanentDelete(int messageId) async {
    final db = await _db;
    return await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Clear all messages for a device
  Future<int> clearChat(String deviceId) async {
    final db = await _db;
    return await db.delete(
      'messages',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Cleanup old soft-deleted messages (older than N days)
  Future<int> cleanupDeletedMessages({int olderThanDays = 30}) async {
    final db = await _db;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    
    return await db.delete(
      'messages',
      where: 'is_deleted_for_me = 1 AND deleted_at < ?',
      whereArgs: [cutoffDate],
    );
  }

  // ==================== STATISTICS ====================

  /// Get message count for a device
  Future<int> getMessageCount(String deviceId, {bool includeDeleted = false}) async {
    final db = await _db;
    
    String whereClause = 'device_id = ?';
    if (!includeDeleted) {
      whereClause += ' AND is_deleted_for_me = 0';
    }
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE $whereClause',
      [deviceId],
    );
    
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total size of attachments for a device
  Future<int> getTotalAttachmentSize(String deviceId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(file_size), 0) as total_size 
      FROM messages 
      WHERE device_id = ? 
        AND file_size IS NOT NULL 
        AND is_deleted_for_me = 0
    ''', [deviceId]);
    
    return (result.first['total_size'] as num?)?.toInt() ?? 0;
  }

  /// Get the chat-list view: every device that has at least one message,
  /// joined with its last message and unread count, most recent first.
  Future<List<Conversation>> getConversations() async {
    final db = await _db;
    final maps = await db.rawQuery('''
      SELECT
        d.bluetooth_address,
        COALESCE(d.alias, '') AS alias,
        COALESCE(d.last_known_name, d.device_name, '') AS name,
        m.message_type AS last_type,
        m.content AS last_content,
        m.file_name AS last_file_name,
        m.is_outgoing AS last_outgoing,
        m.status AS last_status,
        m.created_at AS last_time,
        (SELECT COUNT(*) FROM messages u
          WHERE u.device_id = d.bluetooth_address
            AND u.is_outgoing = 0
            AND u.read_at IS NULL
            AND u.is_deleted_for_me = 0) AS unread
      FROM devices d
      INNER JOIN messages m ON m.id = (
        SELECT id FROM messages x
        WHERE x.device_id = d.bluetooth_address
          AND x.is_deleted_for_me = 0
        ORDER BY x.created_at DESC
        LIMIT 1
      )
      WHERE d.is_blocked = 0
      ORDER BY m.created_at DESC
    ''');

    return maps.map((map) {
      return Conversation(
        address: map['bluetooth_address'] as String,
        alias: (map['alias'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        lastMessageType: (map['last_type'] as int?) ?? MessageType.text,
        lastContent: map['last_content'] as String?,
        lastFileName: map['last_file_name'] as String?,
        lastOutgoing: (map['last_outgoing'] as int?) == 1,
        lastStatus: (map['last_status'] as int?) ?? MessageStatus.sent,
        lastTime: map['last_time'] != null
            ? DateTime.tryParse(map['last_time'] as String)
            : null,
        unread: (map['unread'] as int?) ?? 0,
      );
    }).toList();
  }
}

/// A single row in the Chats list.
class Conversation {
  final String address;
  final String alias;
  final String name;
  final int lastMessageType;
  final String? lastContent;
  final String? lastFileName;
  final bool lastOutgoing;
  final int lastStatus;
  final DateTime? lastTime;
  final int unread;

  Conversation({
    required this.address,
    required this.alias,
    required this.name,
    required this.lastMessageType,
    this.lastContent,
    this.lastFileName,
    required this.lastOutgoing,
    required this.lastStatus,
    this.lastTime,
    this.unread = 0,
  });

  String get displayName {
    if (alias.isNotEmpty) return alias;
    if (name.isNotEmpty) return name;
    if (address.isNotEmpty && address.length >= 4) {
      return address.substring(address.length - 4);
    }
    return 'Device';
  }

  /// Human-readable preview of the last message for the chat list.
  String get preview {
    switch (lastMessageType) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎬 Video';
      case MessageType.audio:
        return '🎤 Voice message';
      case MessageType.file:
        return '📎 ${lastFileName ?? 'File'}';
      default:
        return lastContent ?? '';
    }
  }
}
