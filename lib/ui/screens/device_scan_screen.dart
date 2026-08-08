import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';
import '../../core/bluetooth/ble_service.dart';
import '../../core/bluetooth/bluetooth_service.dart';
import '../../utils/constants.dart';

/// Device Scan Screen
///
/// REAL Bluetooth scanning for nearby Rapid Mesh devices:
/// - Scans over BLE filtered by the Rapid Mesh service UUID, so ONLY phones
///   with this app installed appear in the list (headphones, TVs, other
///   phones without the app are never shown).
/// - Tap a device to send a real connection request.
/// - The other phone shows an Accept/Reject dialog.
/// - If accepted, both sides open a chat. If rejected, a 5-minute cooldown.

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  bool _isScanning = false;
  int _scanDuration = 15;
  int _scanSecondsRemaining = 0;

  Timer? _countdownTimer;
  Timer? _refreshTimer;
  StreamSubscription<ConnectionEvent>? _eventSub;

  // Discovered devices (real results from the BLE scan)
  final List<_DiscoveredDevice> _discoveredDevices = [];

  // Rejection cooldowns (address -> cooldown end time)
  final Map<String, DateTime> _cooldowns = {};

  // Address currently waiting for an accept/reject response
  String? _pendingAddress;

  @override
  void initState() {
    super.initState();
    _eventSub = BluetoothService.instance.events.listen(_handleConnectionEvent);
  }

  @override
  void dispose() {
    _stopScan();
    _eventSub?.cancel();
    super.dispose();
  }

  void _handleConnectionEvent(ConnectionEvent event) {
    if (!mounted) return;

    if (event is ConnectionEstablishedEvent) {
      if (_pendingAddress == event.address) {
        _pendingAddress = null;
        Navigator.of(context, rootNavigator: true).pop(); // close request dialog
        _navigateToChat(event.address, event.name);
      }
    } else if (event is ConnectionRequestRejectedEvent) {
      if (_pendingAddress == event.address) {
        _pendingAddress = null;
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _cooldowns[event.address] = DateTime.now().add(
            const Duration(minutes: AppConstants.rejectionCooldownMinutes),
          );
        });
        _showSnack(
          '✗ Connection rejected. You can try again in 5 minutes.',
          isError: true,
        );
      }
    } else if (event is ConnectionLostEvent) {
      if (_pendingAddress == event.address) {
        _pendingAddress = null;
        Navigator.of(context, rootNavigator: true).pop();
        _showSnack('The connection with the device was lost.', isError: true);
      }
    }
  }

  void _navigateToChat(String address, String name) {
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/chat',
      arguments: {
        'name': name.isEmpty ? 'Device' : name,
        'address': address,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _isScanning ? 'Scanning...' : 'Scan Devices',
        ),
        centerTitle: true,
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '$_scanSecondsRemaining',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Scan animation/status area
          _buildScanStatusArea(),

          // Devices list
          Expanded(
            child: _buildDevicesList(),
          ),

          // Scan button
          _buildScanButton(),
        ],
      ),
    );
  }

  /// Build scan status area with animation
  Widget _buildScanStatusArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withOpacity(0.1),
            AppTheme.background,
          ],
        ),
      ),
      child: Column(
        children: [
          // Animated radar/scanner icon
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: _isScanning ? 1 : 0),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, child) {
              return Transform.rotate(
                angle: value * 6.28, // Full rotation
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withOpacity(0.15 + value * 0.1),
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3 + value * 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.bluetooth_searching,
                    size: 48,
                    color: AppTheme.primary.withOpacity(0.7 + value * 0.3),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          // Status text
          Text(
            _isScanning
                ? 'Searching for Rapid Mesh devices...'
                : 'Tap scan to find nearby devices\n(only devices with this app will appear)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),

          if (_isScanning) ...[
            const SizedBox(height: 8),

            // Progress indicator
            LinearProgressIndicator(
              value: _scanDuration > 0
                  ? 1 - (_scanSecondsRemaining / _scanDuration)
                  : 0,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),

            const SizedBox(height: 8),

            Text(
              'Found ${_discoveredDevices.length} device(s)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build discovered devices list
  Widget _buildDevicesList() {
    if (!_isScanning && _discoveredDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 64,
              color: AppTheme.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No devices found yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure Bluetooth is on and nearby phones\nhave the app open with Bluetooth enabled.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_discoveredDevices.isEmpty && _isScanning) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _discoveredDevices.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderLight),
      itemBuilder: (context, index) {
        final device = _discoveredDevices[index];
        return _buildDeviceTile(device);
      },
    );
  }

  /// Build individual device tile
  Widget _buildDeviceTile(_DiscoveredDevice device) {
    final isInCooldown = _isInCooldown(device.address);
    final isPending = _pendingAddress == device.address;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: device.isRapidMesh
              ? AppTheme.primary.withOpacity(0.15)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          device.isRapidMesh ? Icons.hub : Icons.bluetooth,
          color: device.isRapidMesh ? AppTheme.primary : AppTheme.onSurfaceVariant,
          size: 28,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              device.name ?? 'Unknown Device',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          if (device.isRapidMesh)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 14, color: AppTheme.success),
                  const SizedBox(width: 4),
                  const Text(
                    'Rapid Mesh',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.signal_cellular_alt, size: 14, color: _getSignalColor(device.rssi)),
              const SizedBox(width: 4),
              Text(
                '${device.rssi} dBm • ${device.address}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
              ),
            ],
          ),

          if (isInCooldown) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.block, size: 14, color: AppTheme.error),
                const SizedBox(width: 4),
                Text(
                  'Cooldown: ${_getCooldownRemaining(device.address)}',
                  style: TextStyle(fontSize: 11, color: AppTheme.error),
                ),
              ],
            ),
          ],

          if (isPending) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Waiting for response...',
                  style: TextStyle(fontSize: 11, color: AppTheme.primary),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: isInCooldown
          ? Icon(Icons.timer_outlined, color: AppTheme.error)
          : isPending
              ? null
              : Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant),
      onTap: (isInCooldown || isPending || _pendingAddress != null)
          ? null
          : () => _showConnectDialog(device),
    );
  }

  /// Build scan button at bottom
  Widget _buildScanButton() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _isScanning ? _stopScan : _startScan,
          icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _isScanning ? 'STOP SCANNING' : 'START SCAN',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isScanning ? AppTheme.error : AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  // ==================== SCAN CONTROL ====================

  void _startScan() {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _scanSecondsRemaining = _scanDuration;
    });

    // Live-update the list while the scan runs
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _refreshDeviceList(),
    );

    // Countdown
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _scanSecondsRemaining--;
        if (_scanSecondsRemaining <= 0) _stopScan();
      });
    });

    // Start the real BLE scan (filtered to the Rapid Mesh service UUID)
    BleService.instance.startScan(duration: Duration(seconds: _scanDuration));

    // Detect scan failure (permissions not granted / Bluetooth off)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isScanning && BleService.instance.state == BleServiceState.error) {
        _stopScan();
        _showSnack(
          'Could not start scanning.\nMake sure Bluetooth is on and permissions are granted.',
          isError: true,
        );
      }
    });
  }

  void _stopScan() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;

    BleService.instance.stopScan();

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// Pull the latest scan results from the BLE service into the list.
  /// Only devices running this app (Rapid Mesh devices) are shown.
  void _refreshDeviceList() {
    if (!mounted) return;
    final devices = BleService.instance.discoveredDevices.values
        .where((d) => d.isRapidMeshDevice)
        .map((d) => _DiscoveredDevice(
              name: d.name.isEmpty ? 'Rapid Mesh Device' : d.name,
              address: d.address,
              rssi: d.rssi,
              isRapidMesh: true,
            ))
        .toList();
    setState(() {
      _discoveredDevices
        ..clear()
        ..addAll(devices);
    });
  }

  // ==================== CONNECTION FLOW ====================

  void _showConnectDialog(_DiscoveredDevice device) {
    if (_pendingAddress != null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Send Connection Request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send a connection request to "${device.name}"?'),
            const SizedBox(height: 12),
            Text(
              device.address,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'They will get an Accept / Reject prompt on their phone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendConnectionRequest(device);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  void _sendConnectionRequest(_DiscoveredDevice device) async {
    final ok = await BluetoothService.instance.sendConnectionRequest(device.address);
    if (!mounted) return;

    if (!ok) {
      _showSnack(
        'Could not reach ${device.name}. Make sure they have the app open.',
        isError: true,
      );
      return;
    }

    setState(() {
      _pendingAddress = device.address;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 24),
            Text('Sending connection request to ${device.name}...'),
            const SizedBox(height: 8),
            Text(
              'Waiting for them to accept...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _pendingAddress = null;
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== UTILITY METHODS ====================

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return AppTheme.success;
    if (rssi >= -60) return AppTheme.success.withOpacity(0.7);
    if (rssi >= -70) return AppTheme.warning;
    return AppTheme.error;
  }

  bool _isInCooldown(String address) {
    final cooldownEnd = _cooldowns[address];
    if (cooldownEnd == null) return false;
    return DateTime.now().isBefore(cooldownEnd);
  }

  String _getCooldownRemaining(String address) {
    final cooldownEnd = _cooldowns[address];
    if (cooldownEnd == null) return '';

    final remaining = cooldownEnd.difference(DateTime.now());
    if (remaining.isNegative) {
      _cooldowns.remove(address);
      return '';
    }

    return '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppTheme.error : AppTheme.surface,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

// ==================== DATA CLASSES ====================

class _DiscoveredDevice {
  final String? name;
  final String address;
  final int rssi;
  final bool isRapidMesh;

  _DiscoveredDevice({
    this.name,
    required this.address,
    required this.rssi,
    this.isRapidMesh = false,
  });
}
