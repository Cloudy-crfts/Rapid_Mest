import 'dart:math' show min;

/// Device Model
/// 
/// Represents a Bluetooth device that has been discovered or saved.
/// Each device has a unique Bluetooth address and optional user-assigned alias.

class Device {
  final int? id;
  final String bluetoothAddress;  // Unique identifier (MAC address)
  final String? deviceName;       // Actual BT device name
  final String alias;             // User-assigned name (e.g., "John's Phone")
  final String? lastKnownName;    // Last advertised local name
  final bool isSaved;             // Whether user has saved this device
  final bool isBlocked;           // Whether this device is blocked
  final DateTime? firstSeenAt;    // First discovery timestamp
  final DateTime? lastConnectedAt; // Last successful connection
  final DateTime? lastInteractionAt; // Last message/file exchange
  final int totalMessagesSent;    // Stats: messages sent to this device
  final int totalMessagesReceived; // Stats: messages received from this device
  final int totalFilesTransferred; // Stats: files exchanged
  final int totalBytesTransferred; // Stats: bytes exchanged
  final String? publicKey;        // E2E public key for encryption
  final DateTime createdAt;
  final DateTime updatedAt;

  Device({
    this.id,
    required this.bluetoothAddress,
    this.deviceName,
    this.alias = '',
    this.lastKnownName,
    this.isSaved = false,
    this.isBlocked = false,
    this.firstSeenAt,
    this.lastConnectedAt,
    this.lastInteractionAt,
    this.totalMessagesSent = 0,
    this.totalMessagesReceived = 0,
    this.totalFilesTransferred = 0,
    this.totalBytesTransferred = 0,
    this.publicKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from database map
  factory Device.fromMap(Map<String, dynamic> map) {
    return Device(
      id: map['id'] as int?,
      bluetoothAddress: map['bluetooth_address'] as String,
      deviceName: map['device_name'] as String?,
      alias: map['alias'] as String? ?? '',
      lastKnownName: map['last_known_name'] as String?,
      isSaved: (map['is_saved'] as int) == 1,
      isBlocked: (map['is_blocked'] as int) == 1,
      firstSeenAt: map['first_seen_at'] != null
          ? DateTime.parse(map['first_seen_at'] as String)
          : null,
      lastConnectedAt: map['last_connected_at'] != null
          ? DateTime.parse(map['last_connected_at'] as String)
          : null,
      lastInteractionAt: map['last_interaction_at'] != null
          ? DateTime.parse(map['last_interaction_at'] as String)
          : null,
      totalMessagesSent: map['total_messages_sent'] as int? ?? 0,
      totalMessagesReceived: map['total_messages_received'] as int? ?? 0,
      totalFilesTransferred: map['total_files_transferred'] as int? ?? 0,
      totalBytesTransferred: (map['total_bytes_transferred'] as num?)?.toInt() ?? 0,
      publicKey: map['public_key'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'bluetooth_address': bluetoothAddress,
      'device_name': deviceName,
      'alias': alias,
      'last_known_name': lastKnownName,
      'is_saved': isSaved ? 1 : 0,
      'is_blocked': isBlocked ? 1 : 0,
      'first_seen_at': firstSeenAt?.toIso8601String(),
      'last_connected_at': lastConnectedAt?.toIso8601String(),
      'last_interaction_at': lastInteractionAt?.toIso8601String(),
      'total_messages_sent': totalMessagesSent,
      'total_messages_received': totalMessagesReceived,
      'total_files_transferred': totalFilesTransferred,
      'total_bytes_transferred': totalBytesTransferred,
      'public_key': publicKey,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get display name (prefer alias, fallback to known name, then address)
  String get displayName {
    if (alias.isNotEmpty) return alias;
    if (lastKnownName?.isNotEmpty == true) return lastKnownName!;
    if (deviceName?.isNotEmpty == true) return deviceName!;
    return bluetoothAddress.substring(0, min(17, bluetoothAddress.length));
  }

  /// Copy with modified fields
  Device copyWith({
    int? id,
    String? bluetoothAddress,
    String? deviceName,
    String? alias,
    String? lastKnownName,
    bool? isSaved,
    bool? isBlocked,
    DateTime? firstSeenAt,
    DateTime? lastConnectedAt,
    DateTime? lastInteractionAt,
    int? totalMessagesSent,
    int? totalMessagesReceived,
    int? totalFilesTransferred,
    int? totalBytesTransferred,
    String? publicKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Device(
      id: id ?? this.id,
      bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
      deviceName: deviceName ?? this.deviceName,
      alias: alias ?? this.alias,
      lastKnownName: lastKnownName ?? this.lastKnownName,
      isSaved: isSaved ?? this.isSaved,
      isBlocked: isBlocked ?? this.isBlocked,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
      totalMessagesSent: totalMessagesSent ?? this.totalMessagesSent,
      totalMessagesReceived: totalMessagesReceived ?? this.totalMessagesReceived,
      totalFilesTransferred: totalFilesTransferred ?? this.totalFilesTransferred,
      totalBytesTransferred: totalBytesTransferred ?? this.totalBytesTransferred,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Device(id: $id, address: $bluetoothAddress, name: $displayName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device && runtimeType == other.runtimeType && bluetoothAddress == other.bluetoothAddress;

  @override
  int get hashCode => bluetoothAddress.hashCode;
}
