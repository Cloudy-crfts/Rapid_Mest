import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ble_service.dart';
import 'classic_bluetooth_service.dart';
import 'connection_events.dart';
import 'native_connection_service.dart';
import '../protocol/framing.dart';
import '../database/daos/device_dao.dart';
import '../database/daos/message_dao.dart';
import '../database/models/device.dart';
import '../database/models/message.dart';
import '../transfer/file_transfer_engine.dart';
import '../../services/profile_service.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

export 'connection_events.dart';

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
  String? avatarPath;

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
    this.nativeConnectionId,
    this.remoteName,
    this.avatarPath,
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

// Connection events are defined in connection_events.dart and re-exported here
// so existing imports of bluetooth_service.dart keep working.

// Callback typedefs (declared at top level - Dart does not allow typedefs
// inside a class body).
typedef OnDeviceDiscoveredCallback = void Function(dynamic device);
typedef OnConnectionChangedCallback = void Function(String address, bool connected);
typedef OnMessageReceivedCallback = void Function(String address, Uint8List message);
typedef OnFileDataReceivedCallback = void Function(String address, Uint8List chunk, int chunkIndex);
typedef OnErrorCallback = void Function(String error);

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

  // Per-connection byte stream reassembler (RFCOMM is a raw stream).
  final Map<String, FrameAssembler> _frameAssemblers = {};

  // Persistence
  final DeviceDao _deviceDao = DeviceDao();
  final MessageDao _messageDao = MessageDao();

  // Streaming file transfers
  late final FileTransferEngine _fileTransfers = FileTransferEngine(
    send: _sendFrame,
    emit: (event) => _eventController.add(event),
  );

  /// Public access to the file transfer engine (accept/reject/cancel).
  FileTransferEngine get fileTransfers => _fileTransfers;

  // Broadcast stream of real connection events for the UI
  final StreamController<ConnectionEvent> _eventController =
      StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get events => _eventController.stream;

  // Callbacks
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

    // Tell the other side who we are (display name + optional avatar).
    await _sendFrame(
      address,
      PacketType.handshakeResponse,
      Uint8List.fromList(
          utf8.encode(jsonEncode(ProfileService.instance.handshakeProfile()))),
    );

    unawaited(_recordConnectedDevice(address, info.remoteName));

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
      await _sendFrame(address, PacketType.connectionRejected,
          Uint8List(0));
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

  /// Send a length-prefixed frame (type + payload) over the native socket.
  ///
  /// All RFCOMM traffic goes through this one method so the byte stream stays
  /// consistent: framing on the wire, raw bytes only at the transport layer.
  Future<bool> _sendFrame(
      String address, int type, Uint8List payload) async {
    final id = NativeConnectionService.instance.connectionIdForAddress(address);
    if (id == null) {
      AppLogger.warn('Cannot send frame to $address: not connected', 'BT');
      return false;
    }
    final frame = Framing.buildFrame(type, payload);
    final ok = await NativeConnectionService.instance.send(id, frame);
    if (ok) {
      _connections[address]?.lastActivityAt = DateTime.now();
    }
    return ok;
  }

  /// Wire up callbacks from the native RFCOMM layer.
  void _setupNativeCallbacks() {
    final native = NativeConnectionService.instance;

    native.onIncomingRequest = (id, name, address) {
      _frameAssemblers[address] = FrameAssembler();
      _connections[address] ??= ConnectionInfo(
        address: address,
        role: ConnectionRole.acceptor,
        nativeConnectionId: id,
        remoteName: name,
      );
      // Remember who tried to connect (tiny local device log).
      unawaited(_recordSeenDevice(address, name));
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

      // Socket is up - announce ourselves (display name + optional avatar)
      // so the other side knows who we are.
      final profile = Uint8List.fromList(
          utf8.encode(jsonEncode(ProfileService.instance.handshakeProfile())));
      native.send(id, Framing.buildFrame(PacketType.handshake, profile));
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
      _frameAssemblers.remove(address)?.reset();
      unawaited(_fileTransfers.onConnectionLost(address));
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
  ///
  /// Bytes are reassembled into complete frames (RFCOMM is a raw stream that
  /// does not preserve message boundaries), then dispatched by packet type.
  void _handleNativeData(String address, Uint8List data) {
    if (data.isEmpty) return;

    final assembler = _frameAssemblers.putIfAbsent(address, FrameAssembler.new);
    assembler.add(data);

    for (final frame in assembler.drain()) {
      final type = frame.type;
      final payload = frame.payload;

      if (type >= PacketType.fileRequest &&
          type <= PacketType.fileCancel) {
        unawaited(_fileTransfers.handlePacket(address, type, payload));
        continue;
      }

      switch (type) {
        case PacketType.handshake:
          // 0x01 - the other side announced itself (name + optional avatar).
          _applyPeerProfile(address, payload);
          break;
        case PacketType.handshakeResponse:
          // 0x02 - they accepted our request.
          _establishedConnections.add(address);
          final info = _connections[address];
          final profile = _applyPeerProfile(address, payload);
          if (info != null) {
            info.isClassicConnected = true;
            info.connectedAt ??= DateTime.now();
          }
          _eventController.add(ConnectionEstablishedEvent(
            address: address,
            name: profile.name.isNotEmpty
                ? profile.name
                : (info?.remoteName ?? 'Device'),
          ));
          break;
        case PacketType.connectionRejected:
          // 0x03 - they declined our request.
          _connections.remove(address);
          _eventController.add(ConnectionRequestRejectedEvent(address: address));
          break;
        case PacketType.message:
          unawaited(_handleTextMessage(address, payload));
          break;
        case PacketType.messageAck:
          unawaited(_handleMessageAck(address, payload));
          break;
        default:
          _handleIncomingData(address, data, 'rfcomm');
          break;
      }
    }
  }

  /// Parse a handshake/handshake-response profile and apply it to the
  /// connection (and the local device log). Returns the parsed profile.
  ({String name, String? avatarBase64}) _applyPeerProfile(
      String address, Uint8List payload) {
    var name = '';
    String? avatar;
    try {
      final map = jsonDecode(utf8.decode(payload, allowMalformed: true));
      if (map is Map<String, dynamic>) {
        name = (map['name'] as String?)?.trim() ?? '';
        avatar = map['avatar'] as String?;
      }
    } catch (_) {
      // Older peers may send a bare name - fall back to plain text.
      name = utf8.decode(payload, allowMalformed: true).trim();
    }

    final info = _connections[address];
    if (info != null && name.isNotEmpty) {
      info.remoteName = name;
    }
    if (name.isNotEmpty) {
      unawaited(_recordSeenDevice(address, name));
    }
    if (avatar != null && avatar.isNotEmpty) {
      unawaited(_savePeerAvatar(address, avatar));
    }
    return (name: name, avatarBase64: avatar);
  }

  /// Persist a peer's avatar (received in the handshake) so we can show it in
  /// the chat header and lists. Stored under <app documents>/peers/.
  Future<void> _savePeerAvatar(String address, String avatarBase64) async {
    try {
      final bytes = base64Decode(avatarBase64);
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'peers'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final safe = address.replaceAll(':', '_');
      final file = File(p.join(dir.path, '$safe.jpg'));
      await file.writeAsBytes(bytes);
      final info = _connections[address];
      if (info != null) info.avatarPath = file.path;
    } catch (e) {
      AppLogger.error('Failed to save peer avatar: $address', 'BT', e);
    }
  }

  /// Decode an incoming text message (persist it, echo a delivery ack).
  Future<void> _handleTextMessage(String address, Uint8List payload) async {
    try {
      final jsonStr = utf8.decode(payload, allowMalformed: true);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final messageId = map['id']?.toString() ?? '';
      final text = map['text']?.toString() ?? '';
      final sentAtMs = (map['t'] as num?)?.toInt();
      final sentAt = DateTime.fromMillisecondsSinceEpoch(
          sentAtMs ?? DateTime.now().millisecondsSinceEpoch);

      // Persist the incoming message first so the UI (which reloads from the
      // database on this event) always sees the new row.
      if (messageId.isNotEmpty) {
        await _persistIncomingText(address, messageId, text, sentAt);
      }

      _eventController.add(TextMessageReceivedEvent(
        address: address,
        messageId: messageId,
        text: text,
        sentAt: sentAt,
      ));
      await sendMessageAck(address, messageId);
    } catch (e) {
      AppLogger.error('Failed to parse text message: $e', 'BT');
    }
  }

  /// Decode a delivery ack for a message we sent.
  Future<void> _handleMessageAck(String address, Uint8List payload) async {
    try {
      final jsonStr = utf8.decode(payload, allowMalformed: true);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final messageId = map['id']?.toString() ?? '';
      if (messageId.isNotEmpty) {
        await _messageDao
            .updateStatusByMessageId(messageId, MessageStatus.delivered);
      }
      _eventController.add(TextMessageAckEvent(
        address: address,
        messageId: messageId,
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
      final ok = await _sendFrame(
          address, PacketType.message, Uint8List.fromList(bytes));
      if (ok) {
        _connections[address]?.lastActivityAt = DateTime.now();
        // Update the device log (the chat screen owns message persistence so
        // it can show optimistic "sending -> sent" states).
        unawaited(_deviceDao.recordInteraction(
          address: address,
          sentMessage: true,
        ));
      }
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
    await _sendFrame(
        address, PacketType.messageAck, Uint8List.fromList(bytes));
  }

  // ==================== PERSISTENCE (LOCAL DEVICE LOG) ====================

  /// Upsert a device we've just seen (incoming request or handshake) so it is
  /// remembered in the local log even after a disconnect.
  Future<void> _recordSeenDevice(String address, String name) async {
    try {
      final existing = await _deviceDao.getByAddress(address);
      await _deviceDao.insertOrUpdate(Device(
        bluetoothAddress: address,
        deviceName: existing?.deviceName ?? name,
        alias: existing?.alias ?? '',
        lastKnownName: name.isNotEmpty ? name : existing?.lastKnownName,
        isSaved: existing?.isSaved ?? false,
        isBlocked: existing?.isBlocked ?? false,
        firstSeenAt: existing?.firstSeenAt ?? DateTime.now(),
        lastConnectedAt: existing?.lastConnectedAt,
        lastInteractionAt: existing?.lastInteractionAt,
        totalMessagesSent: existing?.totalMessagesSent ?? 0,
        totalMessagesReceived: existing?.totalMessagesReceived ?? 0,
        totalFilesTransferred: existing?.totalFilesTransferred ?? 0,
        totalBytesTransferred: existing?.totalBytesTransferred ?? 0,
        publicKey: existing?.publicKey,
      ));
    } catch (e) {
      AppLogger.error('Failed to record device: $address', 'BT', e);
    }
  }

  /// Mark a device as connected now (timestamp only).
  Future<void> _recordConnectedDevice(String address, String? name) async {
    await _recordSeenDevice(address, name ?? '');
    try {
      await _deviceDao.updateLastConnected(address);
    } catch (e) {
      AppLogger.error('Failed to update last connected: $address', 'BT', e);
    }
  }

  /// Persist an incoming text message.
  Future<void> _persistIncomingText(
      String address, String messageId, String text, DateTime sentAt) async {
    try {
      await _messageDao.insert(Message(
        messageId: messageId,
        deviceId: address,
        messageType: MessageType.text,
        content: text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        createdAt: sentAt,
      ));
      await _deviceDao.recordInteraction(
        address: address,
        receivedMessage: true,
      );
    } catch (e) {
      AppLogger.error('Failed to persist incoming text', 'BT', e);
    }
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
        case PacketType.message:
        case PacketType.messageAck:
          onMessageReceived?.call(address, data);
          break;
          
        case PacketType.fileChunk:
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
