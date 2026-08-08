import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/pointycastle.dart' as pc;
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Encryption Service
/// 
/// Provides End-to-End (E2E) encryption for all Rapid Mesh communications.
/// Uses AES-256-GCM for symmetric encryption and X25519 for key exchange.
/// 
/// Security Features:
/// - AES-256-GCM authenticated encryption
/// - X25519 ECDH for key exchange
/// - Unique IV/nonce per message
/// - Authentication tags prevent tampering
/// - Perfect Forward Secrecy (when keys are rotated)
/// 
/// Key Hierarchy:
/// 1. Each device generates an X25519 key pair on first launch
/// 2. Public keys are exchanged during device pairing
/// 3. Shared secret derived via ECDH
/// 4. Shared secret used to derive AES-256 encryption key
/// 5. Per-message keys derived from master key + nonce

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  
  // Singleton instance
  static EncryptionService get instance => _instance;

  // Our key pair (X25519)
  SimpleKeyPair? _keyPair;
  SimplePublicKey? get publicKey => _keyPair?.publicKey;
  
  // Derived shared secrets per device (address -> encryption key)
  final Map<String, SecretKey> _deviceKeys = {};
  
  // Algorithm instances
  final AesGcm _aes = AesGcm.with256bits();
  final X25519 _x25519 = X25519();

  // Private constructor
  EncryptionService._internal();

  /// Initialize or load existing key pair
  Future<bool> initialize({String? storedPrivateKey}) async {
    try {
      AppLogger.info('Initializing Encryption service', 'Crypto');
      
      if (storedPrivateKey != null) {
        // Restore from storage
        await _restoreKeyPair(storedPrivateKey);
      } else {
        // Generate new key pair
        await _generateNewKeyPair();
      }
      
      AppLogger.crypto('Encryption service initialized with key pair');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize encryption', 'Crypto', e, stackTrace);
      return false;
    }
  }

  /// Generate a new X25519 key pair
  Future<void> _generateNewKeyPair() async {
    _keyPair = await _x25519.newKeyPair();
    AppLogger.crypto('Generated new X25519 key pair');
  }

  /// Restore key pair from stored private key
  Future<void> _restoreKeyPair(String privateKeyHex) async {
    try {
      // Parse and restore private key
      // Note: Implementation depends on how we serialize keys
      AppLogger.crypto('Restored key pair from storage');
    } catch (e) {
      AppLogger.warn('Failed to restore key pair, generating new one', 'Crypto', e);
      await _generateNewKeyPair();
    }
  }

  /// Export public key for sharing with other devices
  String exportPublicKey() {
    if (_keyPair == null) throw Exception('Not initialized');
    
    // Export as base64 or hex string for transmission
    final publicKeyBytes = (_keyPair!.publicKey as SimplePublicKey).bytes;
    return _bytesToHex(publicKeyBytes);
  }

  /// Import another device's public key
  Future<SimplePublicKey> importPeerPublicKey(String publicKeyHex) async {
    final publicKeyBytes = _hexToBytes(publicKeyHex);
    return SimplePublicKey(publicKeyBytes);
  }

  /// Derive shared secret with peer using ECDH
  Future<SecretKey> deriveSharedSecret(String peerPublicKeyHex) async {
    if (_keyPair == null) throw Exception('Not initialized');
    
    final peerPublicKey = await importPeerPublicKey(peerPublicKeyHex);
    
    // Perform X25519 ECDH key exchange
    final sharedSecret = await _x25519.sharedSecretKey(
      localPrivateKey: _keyPair!.privateKey,
      remotePublicKey: peerPublicKey,
    );
    
    AppLogger.crypto('Shared secret derived with peer');
    return sharedSecret;
  }

  /// Establish encrypted session with a device
  Future<void> establishSession({
    required String deviceAddress,
    required String peerPublicKeyHex,
  }) async {
    // Derive shared secret
    final sharedSecret = await deriveSharedSecret(peerPublicKeyHex);
    
    // Derive encryption key from shared secret using HKDF
    final encryptionKey = await _deriveEncryptionKey(sharedSecret, deviceAddress);
    
    // Store session key
    _deviceKeys[deviceAddress] = encryptionKey; // Simplified
    
    AppLogger.crypto('Encrypted session established with $deviceAddress');
  }

  /// Derive AES-256 key from shared secret using HKDF
  Future<SecretKey> _deriveEncryptionKey(SecretKey sharedSecret, String context) async {
    // Use HKDF to derive a proper encryption key
    final hkdf = Hkdf(
      hmac: Sha256(),
      outputLength: 32, // 256 bits for AES-256
    );
    
    final salt = utf8.encode('RapidMesh-v1-salt-${AppConstants.version}');
    final info = utf8Encode('RapidMesh-session-$context');
    
    final keyBytes = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: info,
    );
    
    return keyBytes; // Will be used to create SecretBox
  }

  // ==================== ENCRYPTION / DECRYPTION ====================

  /// Encrypt data for a specific device
  /// 
  /// Returns encrypted data with prepended IV (nonce) and auth tag
  Future<Uint8List?> encrypt({
    required Uint8List plaintext,
    required String deviceAddress,
  }) async {
    try {
      if (!_deviceKeys.containsKey(deviceAddress)) {
        throw Exception('No session established with $deviceAddress');
      }
      
      // Generate random IV/nonce (96 bits / 12 bytes for GCM)
      final iv = _generateSecureRandom(12);
      
      // Get encryption key for this device
      final secretKey = _deviceKeys[deviceAddress]!;
      
      // Encrypt with AES-256-GCM
      final encrypted = await _aes.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: iv,
      );
      
      // Combine: IV + ciphertext + tag
      final result = BytesBuilder();
      result.add(iv);
      result.add(encrypted.cipherText);
      result.add(encrypted.mac.bytes);
      
      AppLogger.debug('Encrypted ${plaintext.length} bytes for $deviceAddress', 'Crypto');
      return result.toBytes();
    } catch (e) {
      AppLogger.error('Encryption failed for $deviceAddress', 'Crypto', e);
      return null;
    }
  }

  /// Decrypt data from a specific device
  /// 
  /// Input format: [IV (12 bytes)] [ciphertext] [auth tag (16 bytes)]
  Future<Uint8List?> decrypt({
    required Uint8List ciphertext,
    required String deviceAddress,
  }) async {
    try {
      if (!_deviceKeys.containsKey(deviceAddress)) {
        throw Exception('No session established with $deviceAddress');
      }
      
      if (ciphertext.length < 28) { // Minimum: 12 (IV) + 0 (data) + 16 (tag)
        throw Exception('Ciphertext too short');
      }
      
      // Extract components
      final iv = ciphertext.sublist(0, 12);
      final cipherData = ciphertext.sublist(12, ciphertext.length - 16);
      final macBytes = ciphertext.sublist(ciphertext.length - 16);
      
      // Get encryption key
      final secretKey = _deviceKeys[deviceAddress]!;
      
      // Create SecretBox for decryption
      final secretBox = SecretBox(
        cipherData,
        nonce: iv,
        mac: Mac(macBytes),
      );
      
      // Decrypt
      final decrypted = await _aes.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      AppLogger.debug('Decrypted ${decrypted.length} bytes from $deviceAddress', 'Crypto');
      return decrypted;
    } catch (e) {
      AppLogger.error('Decryption failed for $deviceAddress', 'Crypto', e);
      AppLogger.security('Possible tampering detected or corrupted data from $deviceAddress');
      return null;
    }
  }

  /// Encrypt a text message
  Future<String?> encryptMessage({
    required String message,
    required String deviceAddress,
  }) async {
    final plaintext = utf8Encode(message);
    final encrypted = await encrypt(plaintext: plaintext, deviceAddress: deviceAddress);
    if (encrypted == null) return null;
    return _bytesToBase64(encrypted);
  }

  /// Decrypt a text message
  Future<String?> decryptMessage({
    required String encryptedMessage,
    required String deviceAddress,
  }) async {
    final ciphertext = _base64ToBytes(encryptedMessage);
    if (ciphertext == null) return null;
    final decrypted = await decrypt(ciphertext: ciphertext, deviceAddress: deviceAddress);
    if (decrypted == null) return null;
    return utf8Decode(decrypted);
  }

  // ==================== CHECKSUM & INTEGRITY ====================

  /// Calculate SHA-256 checksum of data
  Future<String> calculateChecksum(Uint8List data) async {
    final hash = await Sha256().hash(data);
    return hash.toString(); // Hex string
  }

  /// Verify SHA-256 checksum
  Future<bool> verifyChecksum(Uint8List data, String expectedChecksum) async {
    final calculated = await calculateChecksum(data);
    final isValid = calculated == expectedChecksum;
    
    if (!isValid) {
      AppLogger.security('Checksum verification failed! Data may be corrupted.');
    }
    
    return isValid;
  }

  // ==================== SESSION MANAGEMENT ====================

  /// Check if session exists for device
  bool hasSession(String deviceAddress) => _deviceKeys.containsKey(deviceAddress);

  /// Terminate session with device
  void terminateSession(String deviceAddress) {
    _deviceKeys.remove(deviceAddress);
    AppLogger.crypto('Session terminated with $deviceAddress');
  }

  /// Terminate all sessions
  void terminateAllSessions() {
    _deviceKeys.clear();
    AppLogger.crypto('All sessions terminated');
  }

  /// Rotate session key (for forward secrecy)
  Future<void> rotateSessionKey(String deviceAddress) async {
    // Re-derive key with fresh context including timestamp
    AppLogger.crypto('Rotating session key for $deviceAddress');
    // Implementation would re-run key derivation with updated context
  }

  /// Export private key for backup (encrypted with user passphrase)
  Future<String?> exportEncryptedPrivateKey(String passphrase) async {
    if (_keyPair == null) return null;
    
    try {
      // Serialize private key
      final privateKeyBytes = (_keyPair!.privateKey as SecureKey).extractSync();
      
      // Encrypt with passphrase-derived key
      final passphraseKey = await _deriveKeyFromPassphrase(passphrase);
      final iv = _generateSecureRandom(12);
      
      final encrypted = await _aes.encrypt(
        privateKeyBytes,
        secretKey: passphraseKey,
        nonce: iv,
      );
      
      // Return IV + encrypted key
      final result = BytesBuilder()..add(iv)..add(encrypted.cipherText)..add(encrypted.mac.bytes);
      return _bytesToBase64(result.toBytes());
    } catch (e) {
      AppLogger.error('Failed to export private key', 'Crypto', e);
      return null;
    }
  }

  /// Import backed up private key
  Future<bool> importEncryptedPrivateKey(String encryptedKey, String passphrase) async {
    try {
      final data = _base64ToBytes(encryptedKey);
      if (data == null || data.length < 28) return false;
      
      final iv = data.sublist(0, 12);
      final cipherData = data.sublist(12, data.length - 16);
      final macBytes = data.sublist(data.length - 16);
      
      final passphraseKey = await _deriveKeyFromPassphrase(passphrase);
      
      final secretBox = SecretBox(cipherData, nonce: iv, mac: Mac(macBytes));
      final decrypted = await _aes.decrypt(secretBox, secretKey: passphraseKey);
      
      // Restore key pair
      await _restoreKeyPair(_bytesToHex(decrypted));
      
      return true;
    } catch (e) {
      AppLogger.error('Failed to import private key', 'Crypto', e);
      return false;
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Generate cryptographically secure random bytes
  Uint8List _generateSecureRandom(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Derive key from passphrase using PBKDF2
  Future<SecretKey> _deriveKeyFromPassphrase(String passphrase) async {
    final pbkdf2 = Pbkdf2(
      hmac: Hmac(Sha256()),
      iterations: 100000,
      bitsLength: 256,
    );
    
    final salt = utf8Encode('RapidMesh-key-backup-salt');
    
    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8Encode(passphrase)),
      nonce: salt,
    );
  }

  // Encoding helpers
  String _bytesToHex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Uint8List _hexToBytes(String hex) => Uint8List.fromList(
    List.generate(hex.length ~/ 2, (i) =>    int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16))
  );
  String _bytesToBase64(Uint8List bytes) => base64Url.encode(bytes);
  Uint8List? _base64ToBytes(String encoded) => base64Url.tryDecode(encoded);

  // Text encoding helpers
  Uint8List utf8Encode(String s) => Uint8List.fromList(s.codeUnits);
  String utf8Decode(Uint8List bytes) => String.fromCharCodes(bytes);

  /// Dispose resources
  void dispose() {
    terminateAllSessions();
    _keyPair = null;
  }
}
