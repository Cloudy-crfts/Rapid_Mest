import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'ble_service.dart';
import 'classic_bluetooth_service.dart';
import 'native_connection_service.dart';
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
  int? nativeConnectionId;
  String? remoteName;

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

// ==================== CONNECTION EVENTS ====================
//
// These are pushed onto [BluetoothService.events] so UI screens can react
// to real connection state changes (incoming requests, accepted/rejected
// requests, connection loss, incoming messages and delivery acks).

sealed class ConnectionEvent {
  const ConnectionEvent();
}

/// Another phone is asking to connect to us.
class IncomingRequestEvent extends ConnectionEvent {
  final String address;
  final String name;
  const IncomingRequestEvent({required this.address, required this.name});
}

/// A connection (either direction) is fully established and ready for chat.
class ConnectionEstablishedEvent extends ConnectionEvent {
  final String address;
  final String name;
  const ConnectionEstablishedEvent({required this.address, required this.name});
}

/// Our outgoing connection request was declined (or could not reach the device).
class ConnectionRequestRejectedEvent extends ConnectionEvent {
  final String address;
  const ConnectionRequestRejectedEvent({required this.address});
}

/// An established connection was lost.
class ConnectionLostEvent extends ConnectionEvent {
  final String address;
  const ConnectionLostEvent({required this.address});
}

/// A text message arrived from a connected device.
class TextMessageReceivedEvent extends ConnectionEvent {
  final String address;
  final String messageId;
  final String text;
  final DateTime sentAt;
  const TextMessageReceivedEvent({
    required this.address,
    required this.messageId,
    required this.text,
    required this.sentAt,
  });
}

/// The remote device confirmed receipt of one of our messages.
class TextMessageAckEvent extends ConnectionEvent {
  final String address;
  final String messageId;
  const TextMessageAckEvent({required this.address, required this.messageId});
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

  // Connections that completed the app-level handshake
  final Set<String> _establishedConnections = {};

  // Broadcast stream of real connection events for the UI
  final StreamController<ConnectionEvent> _eventController =
      StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get events => _eventController.stream;

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
    _setupNativeCallbacks();
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
      AppLogger.error('BLE error: $error', 'BT', error, stackTrace);
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
      AppLogger.error('Classic BT error: $error', 'BT', error);
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

      // Start the native layer: RFCOMM server + BLE advertising.
      // Retry briefly in case the adapter is still turning on.
      var nativeStarted = await NativeConnectionService.instance.start();
      for (var attempt = 0; !nativeStarted && attempt < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        nativeStarted = await NativeConnectionService.instance.start();
      }
      if (!nativeStarted) {
        AppLogger.warn('Native Bluetooth layer not running (is Bluetooth on?)', 'BT');
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

  /// Send a connection request to a discovered Rapid Mesh device.
  ///
  /// Dials the device over RFCOMM using the Rapid Mesh service UUID.
  /// If the dial succeeds a handshake is sent; the connection only counts
  /// as established once the other side accepts.
  Future<bool> sendConnectionRequest(String address) async {
    if (_isInCooldown(address)) {
      AppLogger.warn('Connection request to $address is in cooldown', 'BT');
      return false;
    }

    AppLogger.info('Sending connection request to: $address', 'BT');

    final ok = await NativeConnectionService.instance.connect(address);
    if (ok) {
      final info = _connections[address] ??=
          ConnectionInfo(address: address, role: ConnectionRole.initiator);
      info.role = ConnectionRole.initiator;
    }
    return ok;
  }

  /// Accept an incoming connection request (receiver side).
  ///
  /// Sends a handshake response back to the initiator and marks the
  /// connection as established on this side.
  Future<void> acceptIncomingConnection(String address) async {
    AppLogger.info('Accepting connection from: $address', 'BT');

    _rejectionCooldowns.remove(address);

    final info = _connections[address] ??=
        ConnectionInfo(address: address, role: ConnectionRole.acceptor);
    info.role = ConnectionRole.acceptor;
    info.connectedAt ??= DateTime.now();
    info.isClassicConnected = true;

    _establishedConnections.add(address);

    final id = NativeConnectionService.instance.connectionIdForAddress(address);
    if (id != null) {
      final nameBytes = utf8.encode(AppConstants.deviceDisplayName);
      final packet = Uint8List.fromList(
          [AppConstants.PacketType.handshakeResponse, ...nameBytes]);
      await NativeConnectionService.instance.send(id, packet);
    }

    _eventController.add(ConnectionEstablishedEvent(
      address: address,
      name: info.remoteName ?? 'Device',
    ));
  }

  /// Reject an incoming connection request (receiver side).
  ///
  /// Sends a rejection packet and closes the socket. The initiator goes
  /// into a cooldown period so they cannot retry immediately.
  Future<void> rejectIncomingConnection(String address) async {
    AppLogger.info('Rejecting connection from: $address (cooldown: ${AppConstants.rejectionCooldownMinutes}min)', 'BT');

    _rejectionCooldowns[address] = DateTime.now().add(
      Duration(minutes: AppConstants.rejectionCooldownMinutes),
    );

    final id = NativeConnectionService.instance.connectionIdForAddress(address);
    if (id != null) {
      final packet = Uint8List.fromList([AppConstants.PacketType.connectionRejected]);
      await NativeConnectionService.instance.send(id, packet);
      await NativeConnectionService.instance.reject(id);
    }
    _connections.remove(address);
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
      // Prefer the native RFCOMM socket (the real P2P connection)
      final nativeId = NativeConnectionService.instance.connectionIdForAddress(address);
      if (nativeId != null) {
        final ok = await NativeConnectionService.instance.send(nativeId, data);
        if (ok) _connections[address]?.lastActivityAt = DateTime.now();
        return ok;
      }

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
      // Prefer the native RFCOMM socket for real transfers
      final nativeId = NativeConnectionService.instance.connectionIdForAddress(address);
      if (nativeId != null) {
        final ok = await NativeConnectionService.instance.send(nativeId, chunk);
        if (ok) _connections[address]?.lastActivityAt = DateTime.now();
        return ok;
      }

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

  // ==================== NATIVE P2P CONNECTION (REAL RFCOMM) ====================

  /// Wire up callbacks from the native RFCOMM layer.
  void _setupNativeCallbacks() {
    final native = NativeConnectionService.instance;

    native.onIncomingRequest = (id, name, address) {
      _connections[address] ??= ConnectionInfo(
        address: address,
        role: ConnectionRole.acceptor,
        nativeConnectionId: id,
        remoteName: name,
      );
      _eventController.add(IncomingRequestEvent(address: address, name: name));
    };

    native.onConnected = (id, address) {
      final info = _connections[address] ??= ConnectionInfo(
        address: address,
        role: ConnectionRole.initiator,
        nativeConnectionId: id,
      );
      info.nativeConnectionId = id;
      info.lastActivityAt = DateTime.now();

      // Socket is up - announce ourselves so the other side knows who we are
      final nameBytes = utf8.encode(AppConstants.deviceDisplayName);
      final packet = Uint8List.fromList(
          [AppConstants.PacketType.handshake, ...nameBytes]);
      native.send(id, packet);
    };

    native.onData = (id, bytes) {
      final address = native.addressForConnectionId(id);
      if (address != null) _handleNativeData(address, bytes);
    };

    native.onDisconnected = (id) {
      final address = native.addressForConnectionId(id);
      if (address == null) return;
      final info = _connections[address];
      final wasEstablished = _establishedConnections.remove(address);
      if (!wasEstablished && info != null && info.role == ConnectionRole.initiator) {
        // Our outgoing request ended before being accepted
        _eventController.add(ConnectionRequestRejectedEvent(address: address));
      } else if (wasEstablished) {
        _eventController.add(ConnectionLostEvent(address: address));
      }
      _connections.remove(address);
    };

    native.onError = (message) {
      AppLogger.error('Native Bluetooth error: $message', 'BT');
      if (message.contains('connect failed')) {
        // An outgoing dial failed - release any pending initiator connection
        for (final entry in _connections.entries.toList()) {
          final info = entry.value;
          if (info.role == ConnectionRole.initiator &&
              !_establishedConnections.contains(entry.key)) {
            _connections.remove(entry.key);
            _eventController.add(ConnectionRequestRejectedEvent(address: entry.key));
          }
        }
      }
      onError?.call('Bluetooth error: $message');
    };
  }

  /// Handle raw bytes arriving over the native RFCOMM socket.
  void _handleNativeData(String address, Uint8List data) {
    if (data.isEmpty) return;
    final type = data[0];
    final payload = data.length > 1 ? data.sublist(1) : Uint8List(0);

    switch (type) {
      case AppConstants.PacketType.handshake:
        // 0x01 - the other side announced itself; we already know their
        // name from the native 'incoming' event, so nothing to do.
        break;
      case AppConstants.PacketType.handshakeResponse:
        // 0x02 - they accepted our request
        _establishedConnections.add(address);
        final info = _connections[address];
        final remoteName = utf8.decode(payload, allowMalformed: true).trim();
        if (info != null) {
          if (remoteName.isNotEmpty) info.remoteName = remoteName;
          info.isClassicConnected = true;
          info.connectedAt ??= DateTime.now();
        }
        _eventController.add(ConnectionEstablishedEvent(
          address: address,
          name: remoteName.isNotEmpty ? remoteName : (info?.remoteName ?? 'Device'),
        ));
        break;
      case AppConstants.PacketType.connectionRejected:
        // 0x03 - they declined our request
        _connections.remove(address);
        _eventController.add(ConnectionRequestRejectedEvent(address: address));
        break;
      case AppConstants.PacketType.message:
        _handleTextMessage(address, payload);
        break;
      case AppConstants.PacketType.messageAck:
        _handleMessageAck(address, payload);
        break;
      default:
        // e.g. file chunks - pass through to the normal packet handler
        _handleIncomingData(address, data, 'rfcomm');
        break;
    }
  }

  /// Decode an incoming text message (and echo a delivery ack).
  void _handleTextMessage(String address, Uint8List payload) {
    try {
      final jsonStr = utf8.decode(payload, allowMalformed: true);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final messageId = map['id']?.toString() ?? '';
      final text = map['text']?.toString() ?? '';
      final sentAtMs = (map['t'] as num?)?.toInt();
      _eventController.add(TextMessageReceivedEvent(
        address: address,
        messageId: messageId,
        text: text,
        sentAt: DateTime.fromMillisecondsSinceEpoch(
            sentAtMs ?? DateTime.now().millisecondsSinceEpoch),
      ));
      sendMessageAck(address, messageId);
    } catch (e) {
      AppLogger.error('Failed to parse text message: $e', 'BT');
    }
  }

  /// Decode a delivery ack for a message we sent.
  void _handleMessageAck(String address, Uint8List payload) {
    try {
      final jsonStr = utf8.decode(payload, allowMalformed: true);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      _eventController.add(TextMessageAckEvent(
        address: address,
        messageId: map['id']?.toString() ?? '',
      ));
    } catch (e) {
      // ignore malformed acks
    }
  }

  /// Send a text message to a connected device over the native socket.
  Future<bool> sendTextMessage({
    required String address,
    required String messageId,
    required String text,
  }) async {
    final id = NativeConnectionService.instance.connectionIdForAddress(address);
    if (id == null) {
      AppLogger.warn('Cannot send text: not connected to $address', 'BT');
      return false;
    }
    try {
      final map = {
        'id': messageId,
        'text': text,
        't': DateTime.now().millisecondsSinceEpoch,
      };
      final bytes = utf8.encode(jsonEncode(map));
      final packet = Uint8List.fromList([AppConstants.PacketType.message, ...bytes]);
      final ok = await NativeConnectionService.instance.send(id, packet);
      if (ok) _connections[address]?.lastActivityAt = DateTime.now();
      return ok;
    } catch (e) {
      AppLogger.error('Failed to send text message to $address', 'BT', e);
      return false;
    }
  }

  /// Send a delivery ack for a received message.
  Future<void> sendMessageAck(String address, String messageId) async {
    final id = NativeConnectionService.instance.connectionIdForAddress(address);
    if (id == null) return;
    final bytes = utf8.encode(jsonEncode({'id': messageId}));
    final packet = Uint8List.fromList([AppConstants.PacketType.messageAck, ...bytes]);
    await NativeConnectionService.instance.send(id, packet);
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
    await NativeConnectionService.instance.stop();
    await _bleService.dispose();
    await _classicService.dispose();
    
    _rejectionCooldowns.clear();
    _establishedConnections.clear();
    await _eventController.close();
    _isInitialized = false;
  }
}
