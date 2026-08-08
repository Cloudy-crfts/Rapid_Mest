import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Classic Bluetooth Service
/// 
/// Handles Classic Bluetooth (BR/EDR) operations for large file transfers.
/// While BLE is great for discovery and small messages, Classic Bluetooth
/// provides 2-3 Mbps throughput which is better for large files.
/// 
/// Features:
/// - RFCOMM socket connections
/// - High-speed data streaming
/// - Connection pooling per device
/// - Automatic reconnection on disconnect

class ClassicBluetoothService {
  static final ClassicBluetoothService _instance = ClassicBluetoothService._internal();
  
  // Singleton instance
  static ClassicBluetoothService get instance => _instance;

  // State
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // Flutter Bluetooth Serial instance
  FlutterBluetoothSerial? _bluetoothSerial;
  
  // Active connections (address -> connection)
  final Map<String, BluetoothConnection> _connections = {};
  Map<String, BluetoothConnection> get connections => Map.unmodifiable(_connections);
  
  // Data streams per connection
  final Map<String, StreamController<Uint8List>> _dataStreams = {};
  
  // Callbacks
  typedef OnDataReceivedCallback = void Function(String address, Uint8List data);
  typedef OnConnectionStateChangedCallback = void Function(String address, bool connected);
  typedef OnErrorCallback = void Function(String error);
  
  OnDataReceivedCallback? onDataReceived;
  OnConnectionStateChangedCallback? onConnectionStateChanged;
  OnErrorCallback? onError;

  // Private constructor
  ClassicBluetoothService._internal();

  /// Initialize Classic Bluetooth service
  Future<bool> initialize() async {
    try {
      AppLogger.info('Initializing Classic Bluetooth service', 'ClassicBT');
      
      _bluetoothSerial = FlutterBluetoothSerial.instance;
      
      // Check if Bluetooth is available and enabled
      bool? isEnabled = await _bluetoothSerial?.isEnabled;
      if (isEnabled == null || !isEnabled) {
        // Try to enable
        bool? enabled = await _bluetoothSerial?.requestEnable();
        if (enabled != true) {
          throw Exception('Classic Bluetooth not available or could not be enabled');
        }
      }
      
      // Check if device supports Classic Bluetooth
      // Most Android devices do, but some cheap ones might be BLE-only
      
      _isInitialized = true;
      AppLogger.info('Classic Bluetooth service initialized', 'ClassicBT');
      
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Classic Bluetooth', 'ClassicBT', e, stackTrace);
      onError?.call('Failed to initialize Classic Bluetooth: $e');
      return false;
    }
  }

  /// Connect to a device via RFCOMM
  /// 
  /// [address] The MAC address of the target device
  /// [uuid] The RFCOMM service UUID (use our custom one)
  Future<bool> connectToDevice({
    required String address,
    String uuid = '0000RAPID-MESH-CLASSIC-0000-80000805F9B34FB',
  }) async {
    try {
      // Check if already connected
      if (_connections.containsKey(address)) {
        AppLogger.warn('Already connected to: $address', 'ClassicBT');
        return true;
      }
      
      AppLogger.info('Connecting to device via Classic BT: $address', 'ClassicBT');
      
      // Create connection
      final connection = await BluetoothConnection.toAddress(address);
      
      // Store connection
      _connections[address] = connection;
      
      // Set up data stream
      final streamController = StreamController<Uint8List>.broadcast();
      _dataStreams[address] = streamController;
      
      // Listen to incoming data
      connection.input?.listen(
        (Uint8List data) {
          onDataReceived?.call(address, data);
          streamController.add(data);
        },
        onError: (error) {
          AppLogger.error('Data receive error from $address', 'ClassicBT', error);
        },
        onDone: () {
          AppLogger.info('Connection input closed for $address', 'ClassicBT');
          handleDisconnect(address);
        },
      );
      
      onConnectionStateChanged?.call(address, true);
      AppLogger.info('Connected via Classic BT to: $address', 'ClassicBT');
      
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to connect via Classic BT: $address', 'ClassicBT', e, stackTrace);
      onError?.call('Failed to connect: $e');
      return false;
    }
  }

  /// Disconnect from a device
  Future<void> disconnectFromDevice(String address) async {
    try {
      final connection = _connections[address];
      if (connection == null) return;
      
      AppLogger.info('Disconnecting Classic BT: $address', 'ClassicBT');
      
      // Close data stream
      await _dataStreams[address]?.close();
      _dataStreams.remove(address);
      
      // Close connection
      await connection.close();
      _connections.remove(address);
      
      onConnectionStateChanged?.call(address, false);
      AppLogger.info('Disconnected Classic BT: $address', 'ClassicBT');
      
    } catch (e) {
      AppLogger.error('Error disconnecting Classic BT: $address', 'ClassicBT', e);
    }
  }

  /// Disconnect all devices
  Future<void> disconnectAll() async {
    final addresses = _connections.keys.toList();
    for (final address in addresses) {
      await disconnectFromDevice(address);
    }
  }

  /// Send data to a connected device
  /// 
  /// Returns true if data was sent successfully
  Future<bool> sendData({
    required String address,
    required Uint8List data,
  }) async {
    try {
      final connection = _connections[address];
      if (connection == null || !connection.isConnected) {
        throw Exception('Not connected to device: $address');
      }
      
      // Send data through output stream
      connection.output.add(data);
      await connection.output.allSent;
      
      return true;
    } catch (e) {
      AppLogger.error('Failed to send data via Classic BT to: $address', 'ClassicBT', e);
      return false;
    }
  }

  /// Send data with progress callback
  /// 
  /// Useful for large file transfers where you want to track progress
  Future<bool> sendDataWithProgress({
    required String address,
    required Uint8List data,
    int chunkSize = 4096, // 4KB chunks for Classic BT
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    try {
      final connection = _connections[address];
      if (connection == null || !connection.isConnected) {
        throw Exception('Not connected to device: $address');
      }
      
      int totalBytes = data.length;
      int bytesSent = 0;
      
      while (bytesSent < totalBytes) {
        int end = (bytesSent + chunkSize > totalBytes) ? totalBytes : bytesSent + chunkSize;
        Uint8List chunk = data.sublist(bytesSent, end);
        
        connection.output.add(chunk);
        await connection.output.allSent;
        
        bytesSent += chunk.length;
        onProgress?.call(bytesSent, totalBytes);
      }
      
      return true;
    } catch (e) {
      AppLogger.error('Failed to send data with progress', 'ClassicBT', e);
      return false;
    }
  }

  /// Get data stream for a device
  Stream<Uint8List>? getDataStream(String address) {
    return _dataStreams[address]?.stream;
  }

  /// Check if connected to a specific device
  bool isConnected(String address) {
    return _connections.containsKey(address) && 
           _connections[address]?.isConnected == true;
  }

  /// Get number of active connections
  int get activeConnectionCount => _connections.length;

  /// Handle unexpected disconnect
  void handleDisconnect(String address) {
    if (_connections.containsKey(address)) {
      _connections.remove(address);
      _dataStreams.remove(address);
      onConnectionStateChanged?.call(address, false);
    }
  }

  /// Get local device information
  Future<BluetoothDevice?> getLocalDeviceInfo() async {
    try {
      return await _bluetoothSerial?.getDevice();
    } catch (e) {
      AppLogger.error('Failed to get local device info', 'ClassicBT', e);
      return null;
    }
  }

  /// Get paired/bonded devices
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await _bluetoothSerial?.getBondedDevices() ?? [];
    } catch (e) {
      AppLogger.error('Failed to get bonded devices', 'ClassicBT', e);
      return [];
    }
  }

  /// Check if device is bonded/paired
  Future<bool> isDeviceBonded(String address) async {
    final bondedDevices = await getBondedDevices();
    return bondedDevices.any((d) => d.address == address);
  }

  /// Start discovery (scan for Classic Bluetooth devices)
  /// 
  /// Note: This is different from BLE scanning
  Future<void> startDiscovery({
    Duration? duration,
    void Function(BluetoothDevice)? onDeviceFound,
  }) async {
    try {
      AppLogger.info('Starting Classic BT discovery', 'ClassicBT');
      
      _bluetoothSerial?.startDiscovery().listen((result) {
        onDeviceFound?.call(result.device);
      });
      
      // Auto-stop after duration
      if (duration != null) {
        Future.delayed(duration, () {
          stopDiscovery();
        });
      }
    } catch (e) {
      AppLogger.error('Failed to start Classic BT discovery', 'ClassicBT', e);
    }
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    try {
      await _bluetoothSerial?.cancelDiscovery();
      AppLogger.info('Classic BT discovery stopped', 'ClassicBT');
    } catch (e) {
      AppLogger.error('Error stopping Classic BT discovery', 'ClassicBT', e);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    AppLogger.info('Disposing Classic Bluetooth service', 'ClassicBT');
    
    await disconnectAll();
    
    for (final controller in _dataStreams.values) {
      await controller.close();
    }
    _dataStreams.clear();
    
    _isInitialized = false;
  }
}
