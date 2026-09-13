import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/database/daos/device_dao.dart';
import '../core/database/models/device.dart';
import '../utils/logger.dart';

/// Device Log Store
///
/// Rapid Mesh keeps a tiny local log of every device it has connected to.
/// Because Android deletes an app's private storage on uninstall, this service
/// lets the user *optionally* export that log to a file they own (their
/// Downloads / Documents folder) and import it again after reinstalling, so the
/// app still remembers who they connected to. The exported file is intentionally
/// small: device addresses, names and counters only - no messages.
class DeviceLogStore {
  static final DeviceLogStore _instance = DeviceLogStore._internal();

  static DeviceLogStore get instance => _instance;

  final DeviceDao _deviceDao = DeviceDao();

  DeviceLogStore._internal();

  /// Export the device log to a user-chosen location.
  ///
  /// Returns the saved path, or null if the user cancelled.
  Future<String?> exportDeviceLog() async {
    final devices = await _deviceDao.getAll();
    final rows = devices.map((d) => d.toMap()).toList();

    final payload = {
      'format': 'rapidmesh-device-log',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'devices': rows,
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Rapid Mesh device list',
      fileName: 'rapidmesh_devices.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (uri != null) {
      AppLogger.info('Device log exported (${devices.length} devices)', 'Devices');
    }
    return uri?.toString();
  }

  /// Import a previously exported device log.
  ///
  /// Returns the number of devices restored.
  Future<int> importDeviceLog() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a Rapid Mesh device list',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (file == null) return 0;

    final bytes = await file.readAsBytes();

    final decoded = jsonDecode(utf8.decode(bytes));
    final devices = (decoded as Map<String, dynamic>)['devices'] as List<dynamic>?;
    if (devices == null) {
      throw const FormatException('Not a Rapid Mesh device list');
    }

    var restored = 0;
    for (final raw in devices) {
      final map = Map<String, dynamic>.from(raw as Map);
      final address = map['bluetooth_address'] as String?;
      if (address == null || address.isEmpty) continue;

      final device = Device(
        bluetoothAddress: address,
        deviceName: map['device_name'] as String?,
        alias: (map['alias'] as String?) ?? '',
        lastKnownName: map['last_known_name'] as String?,
        isSaved: (map['is_saved'] as num?)?.toInt() == 1,
        isBlocked: (map['is_blocked'] as num?)?.toInt() == 1,
        firstSeenAt: _parseDate(map['first_seen_at']),
        lastConnectedAt: _parseDate(map['last_connected_at']),
        lastInteractionAt: _parseDate(map['last_interaction_at']),
        totalMessagesSent: (map['total_messages_sent'] as num?)?.toInt() ?? 0,
        totalMessagesReceived: (map['total_messages_received'] as num?)?.toInt() ?? 0,
        totalFilesTransferred: (map['total_files_transferred'] as num?)?.toInt() ?? 0,
        totalBytesTransferred: (map['total_bytes_transferred'] as num?)?.toInt() ?? 0,
        publicKey: map['public_key'] as String?,
      );
      await _deviceDao.insertOrUpdate(device);
      restored++;
    }

    AppLogger.info('Device log imported ($restored devices)', 'Devices');
    return restored;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
