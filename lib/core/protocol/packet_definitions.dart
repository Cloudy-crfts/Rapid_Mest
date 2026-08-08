import 'dart:typed_data';
import '../utils/constants.dart';
import '../../utils/helpers.dart';

/// Packet Header Structure
/// 
/// All packets follow this structure:
/// ┌──────────┬─────────┬──────────┬────────────┬────────────────┐
│ │ Version  │ Type    │ Flags    │ Payload Len │ Sequence Num   │
│ (1 byte) │ (1 byte)│ (1 byte) │ (2 bytes)   │ (4 bytes)      │
└──────────┴─────────┴──────────┴────────────┴────────────────┘
/// 
/// Followed by payload (variable length)
/// Optional: Checksum (4 bytes, for file chunks)

class PacketHeader {
  static const int headerSize = 9; // 1 + 1 + 1 + 2 + 4
  
  final int version;        // Protocol version (currently 1)
  final int packetType;     // See AppConstants.PacketType
  int flags;                // Bit field for various flags
  final int payloadLength;  // Length of payload following header
  final int sequenceNumber; // For ordering and ACK tracking

  PacketHeader({
    this.version = 1,
    required this.packetType,
    this.flags = 0,
    required this.payloadLength,
    required this.sequenceNumber,
  });

  /// Serialize header to bytes
  Uint8List toBytes() {
    final data = Uint8List(headerSize);
    data[0] = version;
    data[1] = packetType & 0xFF;
    data[2] = flags & 0xFF;
    
    // Payload length (big-endian, 2 bytes)
    data[3] = (payloadLength >> 8) & 0xFF;
    data[4] = payloadLength & 0xFF;
    
    // Sequence number (big-endian, 4 bytes)
    data[5] = (sequenceNumber >> 24) & 0xFF;
    data[6] = (sequenceNumber >> 16) & 0xFF;
    data[7] = (sequenceNumber >> 8) & 0xFF;
    data[8] = sequenceNumber & 0xFF;
    
    return data;
  }

  /// Parse header from bytes
  static PacketHeader? fromBytes(Uint8List data) {
    if (data.length < headerSize) return null;
    
    return PacketHeader(
      version: data[0],
      packetType: data[1],
      flags: data[2],
      payloadLength: (data[3] << 8) | data[4],
      sequenceNumber: (data[5] << 24) | (data[6] << 16) | (data[7] << 8) | data[8],
    );
  }

  /// Flag constants
  static const int flagEncrypted = 0x01;     // Payload is encrypted
  static const int flagCompressed = 0x02;    // Payload is compressed
  static const int flagLastChunk = 0x04;     // This is the last chunk in a transfer
  static const int flagNeedsAck = 0x08;      // Requires acknowledgment
  static const int flagRetransmit = 0x10;    // This is a retransmission

  bool get isEncrypted => (flags & flagEncrypted) != 0;
  bool get isCompressed => (flags & flagCompressed) != 0;
  bool get isLastChunk => (flags & flagLastChunk) != 0;
  bool get needsAck => (flags & flagNeedsAck) != 0;
  bool get isRetransmit => (flags & flagRetransmit) != 0;

  @override
  String toString() =>
      'PacketHeader(v$version, type=0x${packetType.toRadixString(16)}, seq=$sequenceNumber, len=$payloadLength)';
}

/// Complete Packet with optional payload and checksum
class Packet {
  final PacketHeader header;
  final Uint8List? payload;
  final Uint8List? checksum; // SHA-256 truncated to 4 bytes for efficiency

  Packet({
    required this.header,
    this.payload,
    this.checksum,
  });

  /// Get total packet size
  int get totalSize => PacketHeader.headerSize + 
                        (payload?.length ?? 0) + 
                        (checksum?.length ?? 0);

  /// Serialize complete packet to bytes
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    
    // Add header
    buffer.add(header.toBytes());
    
    // Add payload if present
    if (payload != null && payload!.isNotEmpty) {
      buffer.add(payload!);
    }
    
    // Add checksum if present
    if (checksum != null && checksum!.isNotEmpty) {
      buffer.add(checksum!);
    }
    
    return buffer.toBytes();
  }

  /// Parse packet from bytes
  static Packet? fromBytes(Uint8List data) {
    if (data.length < PacketHeader.headerSize) return null;
    
    final header = PacketHeader.fromBytes(data);
    if (header == null) return null;
    
    // Validate minimum size
    if (data.length < PacketHeader.headerSize + header.payloadLength) {
      return null;
    }
    
    // Extract payload
    Uint8List? payload;
    if (header.payloadLength > 0) {
      payload = data.sublist(
        PacketHeader.headerSize,
        PacketHeader.headerSize + header.payloadLength,
      );
    }
    
    // Extract checksum if present
    Uint8List? checksum;
    final remainingData = data.length - (PacketHeader.headerSize + header.payloadLength);
    if (remainingData >= 4) {
      checksum = data.sublist(
        PacketHeader.headerSize + header.payloadLength,
        PacketHeader.headerSize + header.payloadLength + 4,
      );
    }
    
    return Packet(header: header, payload: payload, checksum: checksum);
  }

  @override
  String toString() => 'Packet($header, payloadLen: ${payload?.length ?? 0})';
}

// ==================== PACKET FACTORY METHODS ====================

/// Factory methods for creating specific packet types
class Packets {
  // Prevent instantiation
  Packets._();

  /// Create handshake packet
  static Packet createHandshake({
    required String deviceId,
    String? nickname,
    int version = 1,
    List<int>? supportedFeatures,
  }) {
    final payload = <int>[];
    
    // Device ID (variable length, prefixed with length)
    final deviceIdBytes = Helpers.stringToBytes(deviceId);
    payload.add(deviceIdBytes.length);
    payload.addAll(deviceIdBytes);
    
    // Nickname (optional)
    final nicknameBytes = nickname != null ? Helpers.stringToBytes(nickname) : [];
    payload.add(nicknameBytes.length);
    payload.addAll(nicknameBytes);
    
    // Version
    payload.add(version);
    
    // Supported features bitmap
    payload.addAll(supportedFeatures ?? [0xFF]); // All features by default
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.handshake,
        payloadLength: payload.length,
        sequenceNumber: 0,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create handshake response packet
  static Packet createHandshakeResponse({
    required String deviceId,
    bool accepted = true,
    String? rejectionReason,
  }) {
    final payload = <int>[];
    
    // Device ID
    final deviceIdBytes = Helpers.stringToBytes(deviceId);
    payload.add(deviceIdBytes.length);
    payload.addAll(deviceIdBytes);
    
    // Accepted flag
    payload.add(accepted ? 1 : 0);
    
    // Rejection reason (if rejected)
    final reasonBytes = rejectionReason != null ? Helpers.stringToBytes(rejectionReason) : [];
    payload.add(reasonBytes.length);
    payload.addAll(reasonBytes);
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.handshakeResponse,
        payloadLength: payload.length,
        sequenceNumber: 0,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create message packet
  static Packet createMessage({
    required int messageType,
    required String content,
    required int sequenceNumber,
    String? messageId,
    String? replyToMessageId,
    bool encrypted = true,
  }) {
    final payload = <int>[];
    
    // Message type
    payload.add(messageType);
    
    // Message ID (if provided)
    final msgIdBytes = messageId != null ? Helpers.stringToBytes(messageId) : [];
    payload.add(msgIdBytes.length);
    payload.addAll(msgIdBytes);
    
    // Reply-to message ID (if provided)
    final replyIdBytes = replyToMessageId != null ? Helpers.stringToBytes(replyToMessageId) : [];
    payload.add(replyIdBytes.length);
    payload.addAll(replyIdBytes);
    
    // Content
    final contentBytes = Helpers.stringToBytes(content);
    final contentLengthBytes = Helpers.intToBytes(contentBytes.length, byteLength: 2);
    payload.addAll(contentLengthBytes);
    payload.addAll(contentBytes);
    
    final flags = encrypted ? PacketHeader.flagEncrypted : 0;
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.message,
        flags: flags | PacketHeader.flagNeedsAck,
        payloadLength: payload.length,
        sequenceNumber: sequenceNumber,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create message ACK packet
  static Packet createMessageAck({
    required int acknowledgedSequenceNumber,
    required String messageId,
  }) {
    final payload = <int>[];
    
    // Acknowledged sequence number
    final seqBytes = Helpers.intToBytes(acknowledgedSequenceNumber, byteLength: 4);
    payload.addAll(seqBytes);
    
    // Message ID
    final msgIdBytes = Helpers.stringToBytes(messageId);
    payload.add(msgIdBytes.length);
    payload.addAll(msgIdBytes);
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.messageAck,
        payloadLength: payload.length,
        sequenceNumber: acknowledgedSequenceNumber,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create file request packet
  static Packet createFileRequest({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String checksum,
  }) {
    final payload = <int>[];
    
    // Transfer ID
    final transferIdBytes = Helpers.stringToBytes(transferId);
    payload.add(transferIdBytes.length);
    payload.addAll(transferIdBytes);
    
    // File name
    final fileNameBytes = Helpers.stringToBytes(fileName);
    final fileNameLength = Helpers.intToBytes(fileNameBytes.length, byteLength: 2);
    payload.addAll(fileNameLength);
    payload.addAll(fileNameBytes);
    
    // File size (8 bytes)
    final fileSizeBytes = Helpers.intToBytes(fileSize, byteLength: 8);
    payload.addAll(fileSizeBytes);
    
    // MIME type
    final mimeTypeBytes = Helpers.stringToBytes(mimeType);
    payload.add(mimeTypeBytes.length);
    payload.addAll(mimeTypeBytes);
    
    // Checksum
    final checksumBytes = Helpers.stringToBytes(checksum);
    payload.addAll(checksumBytes);
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.fileRequest,
        payloadLength: payload.length,
        sequenceNumber: 0,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create file response packet (accept/reject)
  static Packet createFileResponse({
    required String transferId,
    required bool accepted,
    String? rejectionReason,
  }) {
    final payload = <int>[];
    
    // Transfer ID
    final transferIdBytes = Helpers.stringToBytes(transferId);
    payload.add(transferIdBytes.length);
    payload.addAll(transferIdBytes);
    
    // Accept/reject
    payload.add(accepted ? 1 : 0);
    
    // Reason (if rejected)
    final reasonBytes = rejectionReason != null ? Helpers.stringToBytes(rejectionReason) : [];
    payload.add(reasonBytes.length);
    payload.addAll(reasonBytes);
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.fileResponse,
        payloadLength: payload.length,
        sequenceNumber: 0,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create file chunk packet
  static Packet createFileChunk({
    required String transferId,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List chunkData,
    required int sequenceNumber,
    bool isLastChunk = false,
  }) {
    final payload = <int>[];
    
    // Transfer ID (shortened - use hash instead)
    final transferIdHash = Helpers.intToBytes(transferId.hashCode, byteLength: 4);
    payload.addAll(transferIdHash);
    
    // Chunk index (4 bytes)
    final chunkIndexBytes = Helpers.intToBytes(chunkIndex, byteLength: 4);
    payload.addAll(chunkIndexBytes);
    
    // Total chunks (4 bytes)
    final totalChunksBytes = Helpers.intToBytes(totalChunks, byteLength: 4);
    payload.addAll(totalChunksBytes);
    
    // Chunk data
    payload.addAll(chunkData);
    
    final flags = PacketHeader.flagNeedsAck;
    if (isLastChunk) {
      // Note: We can't modify const here, so we'll handle it differently
    }
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.fileChunk,
        flags: flags | (isLastChunk ? PacketHeader.flagLastChunk : 0),
        payloadLength: payload.length,
        sequenceNumber: sequenceNumber,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create file chunk ACK packet
  static Packet createFileChunkAck({
    required String transferId,
    required int chunkIndex,
  }) {
    final payload = <int>[];
    
    // Transfer ID hash
    final transferIdHash = Helpers.intToBytes(transferId.hashCode, byteLength: 4);
    payload.addAll(transferIdHash);
    
    // Acknowledged chunk index
    final chunkIndexBytes = Helpers.intToBytes(chunkIndex, byteLength: 4);
    payload.addAll(chunkIndexBytes);
    
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.fileChunkAck,
        payloadLength: payload.length,
        sequenceNumber: chunkIndex,
      ),
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create ping packet
  static Packet createPing({int sequenceNumber = 0}) {
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.ping,
        payloadLength: 0,
        sequenceNumber: sequenceNumber,
      ),
    );
  }

  /// Create pong packet
  static Packet createPong({required int pingSequenceNumber}) {
    return Packet(
      header: PacketHeader(
        packetType: AppConstants.PacketType.pong,
        payloadLength: 0,
        sequenceNumber: pingSequenceNumber,
      ),
    );
  }

  /// Create delete command packet
  static Packet createDeleteCommand({
    required String messageId,
    bool deleteForEveryone = false,
  }) {
    final payload = <int>[];
    
    // Message ID
    final msgIdBytes = Helpers.stringToBytes(messageId);
    payload.add(msgIdBytes.length);
    payload.addAll(msgIdBytes);
    
    // Delete scope
    payload.add(deleteForEveryone ? 1 : 0); // 0 = for me, 1 = everyone
    
    return Packet(
      header: PacketHeader(
        packetType: deleteForEveryone 
            ? AppConstants.PacketType.deleteForEveryone 
            : AppConstants.PacketType.deleteForMe,
        payloadLength: payload.length,
        sequenceNumber: 0,
      ),
      payload: Uint8List.fromList(payload),
    );
  }
}
