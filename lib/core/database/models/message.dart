/// Message Model
/// 
/// Represents a single message in a conversation.
/// Supports text, images, videos, audio (voice), files, contacts, and location.

class Message {
  final int? id;
  final String deviceId;           // Foreign key to Device
  final int messageType;           // See AppConstants.MessageType
  final String? content;           // Text content or file metadata JSON
  final String? filePath;          // Local path to attached file
  final String? fileName;          // Original filename
  final long? fileSize;            // File size in bytes
  final String? mimeType;          // MIME type of attachment
  final String? thumbnailPath;     // Path to generated thumbnail
  final String? checksum;          // SHA-256 for integrity verification
  final int status;                // See AppConstants.MessageStatus
  final bool isOutgoing;           // true = sent by this user, false = received
  final bool isDeletedForMe;       // Soft delete for this device only
  final bool isDeletedForEveryone; // Deleted for all participants
  final DateTime? deletedAt;       // When deletion occurred
  final DateTime? deliveredAt;     // When message was delivered
  final DateTime? readAt;          // When message was read
  final String? replyToMessageId;  // ID of message being replied to
  final Map<String, dynamic>? metadata; // Additional data as JSON
  final DateTime createdAt;
  final DateTime updatedAt;

  Message({
    this.id,
    required this.deviceId,
    required this.messageType,
    this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.thumbnailPath,
    this.checksum,
    required this.status,
    required this.isOutgoing,
    this.isDeletedForMe = false,
    this.isDeletedForEveryone = false,
    this.deletedAt,
    this.deliveredAt,
    this.readAt,
    this.replyToMessageId,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from database map
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String,
      messageType: map['message_type'] as int,
      content: map['content'] as String?,
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSize: (map['file_size'] as num?)?.toInt(),
      mimeType: map['mime_type'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      checksum: map['checksum'] as String?,
      status: map['status'] as int,
      isOutgoing: (map['is_outgoing'] as int) == 1,
      isDeletedForMe: (map['is_deleted_for_me'] as int) == 1,
      isDeletedForEveryone: (map['is_deleted_for_everyone'] as int) == 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'] as String)
          : null,
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
      replyToMessageId: map['reply_to_message_id'] as String?,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(
              map['metadata'] is String
                  ? (jsonDecode(map['metadata']) as Map<String, dynamic>)
                  : (map['metadata'] as Map<String, dynamic>),
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
      'device_id': deviceId,
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'thumbnail_path': thumbnailPath,
      'checksum': checksum,
      'status': status,
      'is_outgoing': isOutgoing ? 1 : 0,
      'is_deleted_for_me': isDeletedForMe ? 1 : 0,
      'is_deleted_for_everyone': isDeletedForEveryone ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'reply_to_message_id': replyToMessageId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Check if message has an attachment
  bool get hasAttachment => filePath != null && filePath!.isNotEmpty;

  /// Check if message is text-only
  bool get isTextOnly => messageType == AppConstants.MessageType.text && !hasAttachment;

  /// Check if message has been soft-deleted
  bool get isDeleted => isDeletedForMe || isDeletedForEveryone;

  /// Get preview text for chat list
  String getPreviewText() {
    if (isDeletedForMe) {
      return 'Message deleted';
    }
    
    switch (messageType) {
      case AppConstants.MessageType.text:
        return content ?? '';
      case AppConstants.MessageType.image:
        return '📷 Photo';
      case AppConstants.MessageType.video:
        return '🎬 Video';
      case AppConstants.MessageType.audio:
        return '🎤 Voice message';
      case AppConstants.MessageType.file:
        return '📎 ${fileName ?? "File"}';
      case AppConstants.MessageType.contact:
        return '👤 Contact';
      case AppConstants.MessageType.location:
        return '📍 Location';
      default:
        return content ?? '';
    }
  }

  /// Copy with modified fields
  Message copyWith({
    int? id,
    String? deviceId,
    int? messageType,
    String? content,
    String? filePath,
    String? fileName,
    long? fileSize,
    String? mimeType,
    String? thumbnailPath,
    String? checksum,
    int? status,
    bool? isOutgoing,
    bool? isDeletedForMe,
    bool? isDeletedForEveryone,
    DateTime? deletedAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Message(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      checksum: checksum ?? this.checksum,
      status: status ?? this.status,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isDeletedForMe: isDeletedForMe ?? this.isDeletedForMe,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      deletedAt: deletedAt ?? this.deletedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Message(id: $id, type: $messageType, status: $status, outgoing: $isOutgoing)';
}

// Import for jsonEncode/decode
import 'dart:convert';
import '../utils/constants.dart';
import 'dart:math' show min;
