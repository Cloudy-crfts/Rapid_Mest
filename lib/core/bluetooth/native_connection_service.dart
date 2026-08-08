import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// Native Connection Service
///
/// Dart-side bridge to the native Android layer (`RapidMeshNative.kt`),
/// which provides the pieces Flutter's Bluetooth plugins cannot:
///
///  - BLE advertising of the Rapid Mesh service UUID (so only phones with
///    this app appear in other phones' filtered scans)
///  - An RFCOMM server that *accepts* incoming connection requests
///  - An RFCOMM client that dials out to discovered Rapid Mesh phones
///  - Raw byte streaming in both directions
///
/// MethodChannel: com.rapidmesh/native   (start / stop / connect / send / reject)
/// EventChannel:  com.rapidmesh/native/events (incoming / connected / data / disconnected / error)
class NativeConnectionService {
  static final NativeConnectionService _instance = NativeConnectionService._internal();

  // Singleton instance
  static NativeConnectionService get instance => _instance;

  static const MethodChannel _channel = MethodChannel('com.rapidmesh/native');
  static const EventChannel _events = EventChannel('com.rapidmesh/native/events');

  // Native socket id <-> Bluetooth address mapping
  final Map<int, String> _addressById = {};
  final Map<String, int> _idByAddress = {};

  StreamSubscription<dynamic>? _subscription;
  bool _listening = false;

  // Callbacks (wired up by BluetoothService)
  void Function(int id, String name, String address)? onIncomingRequest;
  void Function(int id, String address)? onConnected;
  void Function(int id, Uint8List bytes)? onData;
  void Function(int id)? onDisconnected;
  void Function(String message)? onError;

  NativeConnectionService._internal();

  /// Get the native socket id for a Bluetooth address, if connected.
  int? connectionIdForAddress(String address) => _idByAddress[address];

  /// Get the Bluetooth address for a native socket id, if known.
  String? addressForConnectionId(int id) => _addressById[id];

  /// Start listening for native events and start the RFCOMM server +
  /// BLE advertising. Events are only delivered while we are listening,
  /// so the listen subscription is set up *before* invoking start.
  Future<bool> start() async {
    try {
      _listen();
      final ok = await _channel.invokeMethod<bool>('start');
      return ok ?? false;
    } catch (e) {
      AppLogger.error('Native start failed: $e', 'Native');
      return false;
    }
  }

  /// Stop the server, advertising, and close all sockets.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      // ignore
    }
    _addressById.clear();
    _idByAddress.clear();
  }

  /// Dial an outgoing RFCOMM connection to a discovered device.
  Future<bool> connect(String address) async {
    try {
      await _channel.invokeMethod('connect', {'address': address});
      return true;
    } catch (e) {
      AppLogger.error('Native connect failed: $e', 'Native');
      return false;
    }
  }

  /// Send raw bytes over a native socket. Returns true on success.
  Future<bool> send(int id, Uint8List bytes) async {
    try {
      await _channel.invokeMethod('send', {'id': id, 'bytes': bytes});
      return true;
    } catch (e) {
      AppLogger.error('Native send failed: $e', 'Native');
      return false;
    }
  }

  /// Close a native socket (used when rejecting a connection).
  Future<void> reject(int id) async {
    try {
      await _channel.invokeMethod('reject', {'id': id});
    } catch (_) {
      // ignore
    }
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _subscription = _events.receiveBroadcastStream().listen(
          _handleEvent,
          onError: (Object e) {
            AppLogger.error('Native event stream error: $e', 'Native');
          },
        );
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['event'] as String?;
    final id = event['id'] as int?;

    switch (type) {
      case 'incoming':
        final name = event['name'] as String? ?? 'Unknown';
        final address = event['address'] as String? ?? '';
        if (id != null && address.isNotEmpty) {
          _addressById[id] = address;
          _idByAddress[address] = id;
        }
        onIncomingRequest?.call(id ?? 0, name, address);
        break;

      case 'connected':
        final address = event['address'] as String? ?? '';
        if (id != null && address.isNotEmpty) {
          _addressById[id] = address;
          _idByAddress[address] = id;
        }
        onConnected?.call(id ?? 0, address);
        break;

      case 'data':
        final bytes = event['bytes'] as Uint8List?;
        if (id != null && bytes != null) {
          onData?.call(id, bytes);
        }
        break;

      case 'disconnected':
        if (id != null) {
          // Call the callback first so BluetoothService can still resolve
          // the address, then clean up the mapping.
          onDisconnected?.call(id);
          final address = _addressById.remove(id);
          if (address != null) _idByAddress.remove(address);
        }
        break;

      case 'error':
        final message = event['message'] as String? ?? 'Unknown error';
        onError?.call(message);
        break;
    }
  }
}
