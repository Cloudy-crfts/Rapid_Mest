import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'ble_service.dart';
import 'classic_bluetooth_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Connection Role
enum ConnectionRole {
  initiator,  // This device initiated the connection
  acceptor,   // This device accepted an incoming connection
}

/// Connection Info - tracks state of each connected device
class ConnectionInfo {
  final String address;
  String? alias;
  bool isBleConnected;
  bool isClassicConnected;
  ConnectionRole role;
  DateTime? connectedAt;
  DateTime? lastActivityAt;
  int pendingMessages;
  bool hasActiveTransfer;

  ConnectionInfo({
    required this.address,
    this.alias,
    this.isBleConnected = false,
    this.isClassicConnected = false,
    this.role = ConnectionRole.initiator,
    this.connectedAt,
    this.lastActivityAt,
    this.pendingMessages = 0,
    this.hasActiveTransfer = false,
  });

  bool get isConnected => isBleConnected || isClassicConnected;

  /// Get preferred transport (use Classic for file transfers, BLE for messages)
  String get preferredTransport {
    if (hasActiveTransfer && isClassicConnected) return 'classic';
    if (isBleConnected) return 'ble';
    if (isClassicConnected) return 'classic';
    return 'none';
  }
}

/// Main Bluetooth Service
/// 
/// Orchestrates both BLE and Classic Bluetooth for optimal performance:
/// - BLE: Device discovery, messaging, control signals, small data
/// - Classic BT: Large file transfers (2-3 Mbps throughput)
/// 
/// Features:
/// - Automatic transport selection based on data type
/// - Connection pooling and management
/// - Reconnection logic with cooldown on rejection
/// - Bandwidth-aware scheduling

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  
  // Singleton instance
  static BluetoothService get instance => _instance;

  // Sub-services
  BleService _bleService = BleService.instance;
  ClassicBluetoothService _classicService = ClassicBluetoothService.instance;

  // Connection tracking
  final Map<String, ConnectionInfo> _connections = {};
  Map<String, ConnectionInfo> get connections => Map.unmodifiable(_connections);

  // Rejection cooldown tracking (address -> cooldown end time)
  final Map<String, DateTime> _rejectionCooldowns = {};

  // State
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Callbacks
  typedef OnDeviceDiscoveredCallback = void Function(dynamic device);
  typedef OnConnectionChangedCallback = void Function(String address, bool connected);
  typedef OnMessageReceivedCallback = void Function(String address, Uint8List message);
  typedef OnFileDataReceivedCallback = void Function(String address, Uint8List chunk, int chunkIndex);
  typedef OnErrorCallback = void Function(String error);

  OnDeviceDiscoveredCallback? onDeviceDiscovered;
  OnConnectionChangedCallback? onConnectionChanged;
  OnMessageReceivedCallback? onMessageReceived;
  OnFileDataReceivedCallback? onFileDataReceived;
  OnErrorCallback? onError;

  // Private constructor
  BluetoothService._internal() {
    _setupSubServiceCallbacks();
  }

  /// Setup callbacks from sub-services
  void _setupSubServiceCallbacks() {
    // BLE callbacks
    _bleService.onDeviceDiscovered = (device) {
      onDeviceDiscovered?.call(device);
    };

    _bleService.onConnectionStateChanged = (address, connected) {
      _updateConnectionState(address, bleConnected: connected);
      onConnectionChanged?.call(address, connected);
    };

    _bleService.onDataReceived = (address, data) {
      _handleIncomingData(address, data, 'ble');
    };

    _bleService.onError = (error, {stackTrace}) {
      AppLogger.error('BLE error: $error', 'BT', error as Exception?, stackTrace);
      onError?.call('BLE Error: $error');
    };

    // Classic BT callbacks
    _classicService.onConnectionStateChanged = (address, connected) {
      _updateConnectionState(address, classicConnected: connected);
      onConnectionChanged?.call(address, connected);
    };

    _classicService.onDataReceived = (address, data) {
      _handleIncomingData(address, data, 'classic');
    };

    _classicService.onError = (error) {
      AppLogger.error('Classic BT error: $error', 'BT', error as Exception?);
      onError?.call('Classic BT Error: $error');
    };
  }

  /// Initialize all Bluetooth services
  Future<bool> initialize() async {
    try {
      AppLogger.info('Initializing Bluetooth Service', 'BT');
      
      // Initialize BLE service
      final bleInitialized = await _bleService.initialize();
      if (!bleInitialized) {
        throw Exception('Failed to initialize BLE service');
      }
      
      // Initialize Classic Bluetooth service
      final classicInitialized = await _classicService.initialize();
      if (!classicInitialized) {
        AppLogger.warn('Classic Bluetooth not available, will use BLE only', 'BT');
        // Not fatal - we can work with just BLE
      }
      
      _isInitialized = true;
      AppLogger.info('Bluetooth Service initialized successfully', 'BT');
      
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Bluetooth Service', 'BT', e, stackTrace);
      onError?.call('Initialization failed: $e');
      return false;
    }
  }

  // ==================== SCANNING ====================

  /// Start scanning for nearby devices
  Future<void> startScan({Duration? duration}) async {
    await _bleService.startScan(duration: duration);
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await _bleService.stopScan();
  }

  bool get isScanning => _bleService.isScanning;

  // ==================== CONNECTION MANAGEMENT ====================

  /// Initiate connection to a device
  /// 
  /// Connects via BLE first for discovery/messaging,
  /// then optionally establishes Classic BT for file transfers.
  Future<bool> connectToDevice(String address) async {
    try {
      // Check rejection cooldown
      if (_isInCooldown(address)) {
        final remaining = _getCooldownRemaining(address);
        throw Exception(
          'Device is in cooldown period. Try again in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s'
        );
      }
      
      AppLogger.info('Initiating connection to: $address', 'BT');
      
      // Step 1: Connect via BLE
      final bleConnected = await _bleService.connectToDevice(address: address);
      
      if (!bleConnected) {
        throw Exception('BLE connection failed');
      }
      
      // Create or update connection info
      _connections[address] ??= ConnectionInfo(address: address);
      _connections[address]!.isBleConnected = true;
      _connections[address]!.role = ConnectionRole.initiator;
      _connections[address]!.connectedAt ??= DateTime.now();
      _connections[address]!.lastActivityAt = DateTime.now();
      
      // Step 2: Optionally connect via Classic BT for better file transfer speeds
      // We do this in background to not block the initial connection
      _establishClassicConnectionInBackground(address);
      
      AppLogger.info('Connected to device: $address', 'BT');
      return true;
      
    } catch (e) {
      AppLogger.error('Failed to connect to: $address', 'BT', e);
      rethrow;
    }
  }

  /// Accept incoming connection request
  Future<bool> acceptConnection(String address) async {
    try {
      AppLogger.info('Accepting connection from: $address', 'BT');
      
      // Clear any existing cooldown
      _rejectionCooldowns.remove(address);
      
      // Create connection info
      _connections[address] = ConnectionInfo(
        address: address,
        role: ConnectionRole.acceptor,
        connectedAt: DateTime.now(),
        lastActivityAt: DateTime.now(),
      );
      
      // Accept BLE connection (the remote device initiated)
      // In practice, this means we're ready to accept their connection
      
      // Also prepare Classic BT
      await _classicService.connectToDevice(address: address);
      _connections[address]!.isClassicConnected = true;
      
      onConnectionChanged?.call(address, true);
      AppLogger.info('Accepted connection from: $address', 'BT');
      
      return true;
    } catch (e) {
      AppLogger.error('Failed to accept connection from: $address', 'BT', e);
      return false;
    }
  }

  /// Reject incoming connection request
  /// 
  /// Sets a cooldown period during which this device cannot retry
  Future<void> rejectConnection(String address) async {
    AppLogger.info('Rejecting connection from: $address (cooldown: ${AppConstants.rejectionCooldownMinutes}min)', 'BT');
    
    // Set cooldown
    _rejectionCooldowns[address] = DateTime.now().add(
      Duration(minutes: AppConstants.rejectionCooldownMinutes)
    );
    
    // Notify callback
    onConnectionChanged?.call(address, false);
  }

  /// Disconnect from a specific device
  Future<void> disconnectFromDevice(String address) async {
    AppLogger.info('Disconnecting from: $address', 'BT');
    
    await _bleService.disconnectFromDevice(address);
    await _classicService.disconnectFromDevice(address);
    
    _connections.remove(address);
    onConnectionChanged?.call(address, false);
  }

  /// Disconnect from all devices
  Future<void> disconnectAll() async {
    AppLogger.info('Disconnecting from all devices', 'BT');
    
    await _bleService.disconnectAll();
    await _classicService.disconnectAll();
    _connections.clear();
  }

  // ==================== DATA SENDING ====================

  /// Send message data (uses BLE)
  Future<bool> sendMessage({
    required String address,
    required Uint8List data,
  }) async {
    try {
      final connInfo = _connections[address];
      if (connInfo == null || !connInfo.isConnected) {
        throw Exception('Not connected to device: $address');
      }
      
      // Messages go through BLE (efficient for small payloads)
      final success = await _bleService.writeData(
        address: address,
        characteristicUuid: AppConstants.messageCharacteristicUuid,
        data: data,
        withoutResponse: true, // WRITE_TYPE_NO_RESPONSE for speed
      );
      
      if (success) {
        connInfo.lastActivityAt = DateTime.now();
      }
      
      return success;
    } catch (e) {
      AppLogger.error('Failed to send message to: $address', 'BT', e);
      return false;
    }
  }

  /// Send file chunk (uses Classic BT for speed, falls back to BLE)
  Future<bool> sendFileChunk({
    required String address,
    required Uint8List chunk,
    required int chunkIndex,
  }) async {
    try {
      final connInfo = _connections[address];
      if (connInfo == null || !connInfo.isConnected) {
        throw Exception('Not connected to device: $address');
      }
      
      connInfo.hasActiveTransfer = true;
      
      // Prefer Classic BT for file chunks (higher throughput)
      if (connInfo.isClassicConnected) {
        final success = await _classicService.sendData(
          address: address,
          data: chunk,
        );
        
        if (success) {
          connInfo.lastActivityAt = DateTime.now();
        }
        return success;
      } else {
        // Fall back to BLE
        return await _bleService.writeData(
          address: address,
          characteristicUuid: AppConstants.fileDataCharacteristicUuid,
          data: chunk,
          withoutResponse: true,
        );
      }
    } catch (e) {
      AppLogger.error('Failed to send file chunk to: $address', 'BT', e);
      return false;
    }
  }

  /// Send control signal (connection requests, ACKs, etc.)
  Future<bool> sendControlSignal({
    required String address,
    required Uint8List data,
  }) async {
    return await _bleService.writeData(
      address: address,
      characteristicUuid: AppConstants.handshakeCharacteristicUuid,
      data: data,
      withoutResponse: false, // Control signals need confirmation
    );
  }

  // ==================== INCOMING DATA HANDLING ====================

  void _handleIncomingData(String address, Uint8List data, String transport) {
    final connInfo = _connections[address];
    if (connInfo != null) {
      connInfo.lastActivityAt = DateTime.now();
    }
    
    // Parse packet type from header
    if (data.isNotEmpty) {
      final packetType = data[0];
      
      switch (packetType) {
        case AppConstants.PacketType.message:
        case AppConstants.PacketType.messageAck:
          onMessageReceived?.call(address, data);
          break;
          
        case AppConstants.PacketType.fileChunk:
          // Extract chunk index from packet
          if (data.length >= 5) {
            final chunkIndex = (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
            onFileDataReceived?.call(address, data.sublist(5), chunkIndex);
          }
          break;
          
        default:
          // Handle other packet types
          AppLogger.debug('Received packet type: $packetType from $address via $transport', 'BT');
          break;
      }
    }
  }

  // ==================== POWER MANAGEMENT ====================

  /// Switch to power saving mode for a device
  Future<void> enablePowerSavingMode(String address) async {
    await _bleService.enablePowerSavingMode(address);
  }

  /// Switch to high priority mode for a device
  Future<void> enableHighPriorityMode(String address) async {
    await _bleService.enableHighPriorityMode(address);
  }

  /// Enable power saving for all connections (app backgrounded)
  Future<void> enableGlobalPowerSaving() async {
    for (final address in _connections.keys) {
      await enablePowerSavingMode(address);
    }
  }

  /// Disable power saving for all connections (app foregrounded)
  Future<void> disableGlobalPowerSaving() async {
    for (final address in _connections.keys) {
      await enableHighPriorityMode(address);
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Update connection state internally
  void _updateConnectionState(String address, {bool? bleConnected, bool? classicConnected}) {
    if (_connections.containsKey(address)) {
      if (bleConnected != null) {
        _connections[address]!.isBleConnected = bleConnected;
      }
      if (classicConnected != null) {
        _connections[address]!.isClassicConnected = classicConnected;
      }
      
      // Clean up if fully disconnected
      if (!_connections[address]!.isConnected) {
        _connections.remove(address);
      }
    }
  }

  /// Establish Classic BT connection in background
  Future<void> _establishClassicConnectionInBackground(String address) async {
    // Don't block - attempt in background
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final connected = await _classicService.connectToDevice(address: address);
        if (connected && _connections.containsKey(address)) {
          _connections[address]!.isClassicConnected = true;
          AppLogger.debug('Classic BT established for: $address', 'BT');
        }
      } catch (e) {
        // Non-fatal - continue with BLE only
        AppLogger.debug('Classic BT not available for: $address, using BLE only', 'BT');
      }
    });
  }

  /// Check if device is in rejection cooldown
  bool _isInCooldown(String address) {
    final cooldownEnd = _rejectionCooldowns[address];
    if (cooldownEnd == null) return false;
    return DateTime.now().isBefore(cooldownEnd);
  }

  /// Get remaining cooldown time
  Duration _getCooldownRemaining(String address) {
    final cooldownEnd = _rejectionCooldowns[address];
    if (cooldownEnd == null) return Duration.zero;
    final remaining = cooldownEnd.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Set alias for a connected device
  void setDeviceAlias(String address, String alias) {
    if (_connections.containsKey(address)) {
      _connections[address]!.alias = alias;
    }
  }

  /// Check if connected to any device
  bool get hasConnections => _connections.isNotEmpty;

  /// Get total number of active connections
  int get connectionCount => _connections.length;

  /// Get list of connected device addresses
  List<String> get connectedAddresses => _connections.keys.toList();

  /// Get connection info for a specific device
  ConnectionInfo? getConnectionInfo(String address) {
    return _connections[address];
  }

  /// Dispose all resources
  Future<void> dispose() async {
    AppLogger.info('Disposing Bluetooth Service', 'BT');
    
    await disconnectAll();
    await _bleService.dispose();
    await _classicService.dispose();
    
    _rejectionCooldowns.clear();
    _isInitialized = false;
  }
}
