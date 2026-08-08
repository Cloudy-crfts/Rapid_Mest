/// Rapid Mesh Application Constants
/// 
/// Centralized constants for the entire application.
/// All magic numbers, strings, and configuration values live here.

class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // ==================== APP INFO ====================
  
  /// Application name
  static const String appName = 'Rapid Mesh';
  
  /// Package name
  static const String packageName = 'com.rapidmesh.app';
  
  /// Version
  static const String version = '1.0.0';
  
  /// Build number
  static const int buildNumber = 1;

  // ==================== BLUETOOTH CONFIGURATION ====================
  
  /// Service UUID for Rapid Mesh BLE
  static const String bleServiceUuid = '0000RAPID-MESH-0000-8000-00805F9B34FB';
  
  /// Characteristic UUID for messaging
  static const String messageCharacteristicUuid = '0000MSG-CHAR-0000-8000-00805F9B34FB';
  
  /// Characteristic UUID for file transfer control
  static const String fileControlCharacteristicUuid = '0000FILE-CTRL-0000-8000-00805F9B34FB';
  
  /// Characteristic UUID for file data (large payloads)
  static const String fileDataCharacteristicUuid = '0000FILE-DATA-0000-8000-00805F9B34FB';
  
  /// Characteristic UUID for connection handshake
  static const String handshakeCharacteristicUuid = '0000HANDSHAKE-0000-8000-00805F9B34FB';
  
  /// Device name prefix for identification
  static const String deviceNamePrefix = '[RM] ';
  
  /// Scan duration in seconds
  static const int scanDurationSeconds = 10;
  
  /// Connection cooldown after rejection (5 minutes)
  static const int rejectionCooldownMinutes = 5;
  
  /// Connection timeout in milliseconds
  static const int connectionTimeoutMs = 15000;

  // ==================== BLUETOOTH OPTIMIZATION ====================
  
  /// Requested MTU size (max payload = MTU - 3)
  static const int requestedMtuSize = 512;
  
  /// Effective MTU payload size (MTU - 3 bytes for ATT header)
  static int get effectivePayloadSize => requestedMtuSize - 3;
  
  /// Connection interval minimum (7.5ms) - high priority mode
  static const int connectionIntervalMinHighPriority = 6; // 7.5ms
  
  /// Connection interval maximum (15ms) - high priority mode
  static const int connectionIntervalMaxHighPriority = 12; // 15ms
  
  /// Connection interval minimum (100ms) - power saving mode
  static const int connectionIntervalMinPowerSave = 80; // 100ms
  
  /// Connection interval maximum (100ms) - power saving mode
  static const int connectionIntervalMaxPowerSave = 80; // 100ms
  
  /// Slave latency (0 for high priority)
  static const int slaveLatency = 0;
  
  /// Supervision timeout (5000ms)
  static const int supervisionTimeoutMs = 5000;
  
  /// DLE requested max TX payload size
  static const int dleMaxTxPayloadSize = 251;
  
  /// DLE requested max RX payload size
  static const int dleMaxRxPayloadSize = 251;

  // ==================== FILE TRANSFER CONFIGURATION ====================
  
  /// Default chunk size in bytes (509 bytes to fit in 512 MTU)
  static const int defaultChunkSizeBytes = 509;
  
  /// Maximum chunk size (for devices with larger MTU support)
  static const int maxChunkSizeBytes = 2000;
  
  /// Sliding window size (number of unacknowledged chunks allowed)
  static const int slidingWindowSize = 32;
  
  /// Retry count for failed chunks before declaring failure
  static const int maxChunkRetries = 3;
  
  /// Timeout waiting for ACK in milliseconds
  static const int ackTimeoutMs = 3000;
  
  /// Interval between progress updates in milliseconds
  static const int progressUpdateIntervalMs = 250;
  
  /// Checksum algorithm used
  static const String checksumAlgorithm = 'SHA-256';

  // ==================== BANDWIDTH ALLOCATION ====================
  
  /// Maximum theoretical Bluetooth throughput in bytes per second
  /// ~1.4 Mbps = 175,000 bytes/sec (conservative estimate)
  static const int maxBluetoothThroughputBps = 175000;
  
  /// Reserved bandwidth percentage for control messages
  static const double reservedBandwidthPercent = 0.10; // 10%
  
  /// Minimum guaranteed bandwidth per active connection (bytes/sec)
  static const int minBandwidthPerConnectionBps = 10000; // ~10 KB/s

  // ==================== THERMAL & POWER MANAGEMENT ====================
  
  /// Temperature threshold for throttling start (Celsius)
  static const double thermalThrottleStartCelsius = 38.0;
  
  /// Temperature threshold for pausing transfers (Celsius)
  static const double thermalPauseThresholdCelsius = 42.0;
  
  /// Battery level threshold for power save mode (percentage)
  static const int batteryLowThresholdPercent = 20;
  
  /// Battery critical threshold - pause large transfers (percentage)
  static const int batteryCriticalThresholdPercent = 10;
  
  /// Thermal check interval in milliseconds
  static const int thermalCheckIntervalMs = 10000; // Check every 10 seconds

  // ==================== ENCRYPTION CONFIGURATION ====================
  
  /// Encryption algorithm
  static const String encryptionAlgorithm = 'AES/GCM/NoPadding';
  
  /// Key length in bits
  static const int encryptionKeyLengthBits = 256;
  
  /// IV/Nonce length in bytes
  static const int encryptionIvLengthBytes = 12;
  
  /// Auth tag length in bytes
  static const int encryptionAuthTagLengthBytes = 16;
  
  /// Key exchange algorithm
  static const String keyExchangeAlgorithm = 'X25519';

  // ==================== MESSAGE TYPES ====================
  
  class MessageType {
    static const int text = 0;
    static const int image = 1;
    static const int video = 2;
    static const int audio = 3;      // Voice message
    static const int file = 4;       // Generic file
    static const int contact = 5;    // Contact card
    static const int location = 6;   // Location sharing
    static const int system = 99;    // System messages
  }

  // ==================== MESSAGE STATUS ====================
  
  class MessageStatus {
    static const int sending = 0;
    static const int sent = 1;       // Sent but not yet delivered
    static const int delivered = 2;  // Delivered to recipient device
    static const int read = 3;       // Read by recipient
    static const int failed = 4;     // Failed to send
    static const int queued = 5;     // Queued offline, waiting for connection
  }

  // ==================== TRANSFER STATUS ====================
  
  class TransferStatus {
    static const int pending = 0;     // Waiting for acceptance
    static const int accepted = 1;    // Accepted by receiver
    static const int rejected = 2;    // Rejected by receiver
    static const int transferring = 3; // In progress
    static const int paused = 4;      // Paused (out of range / thermal)
    static const int completed = 5;   // Successfully completed
    static const int failed = 6;      // Failed (corruption / error)
    static const int cancelled = 7;   // Cancelled by user
  }

  // ==================== PACKET TYPES (Custom Protocol) ====================
  
  class PacketType {
    static const int handshake = 0x01;
    static const int handshakeResponse = 0x02;
    static const int message = 0x10;
    static const int messageAck = 0x11;
    static const int fileRequest = 0x20;
    static const int fileResponse = 0x21;
    static const int fileChunk = 0x22;
    static const int fileChunkAck = 0x23;
    static const int fileComplete = 0x24;
    static const int fileCancel = 0x25;
    static const int pauseTransfer = 0x26;
    static const int resumeTransfer = 0x27;
    static const int deleteForMe = 0x30;
    static const int deleteForEveryone = 0x31;
    static const int typingIndicator = 0x40;
    static const int onlineStatus = 0x41;
    static const int ping = 0xFE;
    static const int pong = 0xFF;
  }

  // ==================== STORAGE PATHS ====================
  
  /// Directory name for received files
  static const String receivedFilesDir = 'received_files';
  
  /// Directory name for sent files cache
  static const String sentFilesDir = 'sent_files';
  
  /// Directory name for voice messages
  static const String voiceMessagesDir = 'voice_messages';
  
  /// Directory name for images
  static const String imagesDir = 'images';
  
  /// Directory name for temporary/in-progress transfers
  static const String tempTransfersDir = 'temp_transfers';
  
  /// Directory name for thumbnails
  static const String thumbnailsDir = 'thumbnails';

  // ==================== UI CONSTANTS ====================
  
  /// Maximum characters for a nickname
  static const int maxNicknameLength = 30;
  
  /// Maximum characters for status/message preview
  static const int maxPreviewLength = 50;
  
  /// Animation durations
  static const int animationDurationMs = 300;
  static const int shortAnimationDurationMs = 150;
  
  /// Chat bubble border radius
  static const double chatBubbleRadius = 18.0;
  
  /// Avatar size in chat list
  static const double avatarSizeList = 56.0;
  
  /// Avatar size in chat screen
  static const double avatarSizeChat = 40.0;

  // ==================== DATABASE VERSION ====================
  
  /// Current database schema version
  static const int databaseVersion = 1;
}
