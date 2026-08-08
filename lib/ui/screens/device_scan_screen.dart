import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

/// Device Scan Screen
/// 
/// Manual Bluetooth device scanning interface:
/// - Scan button to start/stop scanning
/// - List of discovered devices
/// - Connect request flow (like connecting to BT headphones)
/// - Accept/Reject dialog on receiver's device
/// - 5-minute cooldown on rejection
/// 
/// User Flow:
/// 1. Press "Scan" button
/// 2. See list of nearby devices
/// 3. Tap a device to send connection request
/// 4. Other device shows Accept/Reject popup
/// 5. If accepted → connected, can chat/share files
/// 6. If rejected → 5-minute cooldown before retry

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  bool _isScanning = false;
  int _scanDuration = 10;
  int _scanSecondsRemaining = 0;
  Timer? _scanTimer;
  
  // Discovered devices (sample data)
  final List<_DiscoveredDevice> _discoveredDevices = [];
  
  // Rejection cooldowns (address -> cooldown end time)
  final Map<String, DateTime> _cooldowns = {};

  @override
  void dispose() {
    _stopScan();
    super.dispose();
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
                  '$_scanDuration',
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
            _isScanning ? 'Searching for devices...' : 'Tap scan to find nearby devices',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          
          if (_isScanning) ...[
            const SizedBox(height: 8),
            
            // Progress indicator
            LinearProgressIndicator(
              value: _scanDuration > 0 ? 1 - (_scanSecondsRemaining / _scanDuration) : 0,
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
              'Start scanning to discover nearby Rapid Mesh devices',
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
                  Text(
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
        ],
      ),
      trailing: isInCooldown
          ? Icon(Icons.timer_outlined, color: AppTheme.error)
          : Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant),
      onTap: isInCooldown ? null : () => _showConnectDialog(device),
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
      
      // Add sample devices (would come from BLE in real app)
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _discoveredDevices.addAll([
              _DiscoveredDevice(
                name: "Alex's iPhone",
                address: "AA:BB:CC:DD:EE:FF",
                rssi: -45,
                isRapidMesh: true,
              ),
              _DiscoveredDevice(
                name: "Samsung Galaxy S23",
                address: "11:22:33:44:55:66",
                rssi: -62,
                isRapidMesh: true,
              ),
              _DiscoveredDevice(
                name: "Unknown Headset",
                address: "77:88:99:AA:BB:CC",
                rssi: -78,
                isRapidMesh: false,
              ),
            ]);
          });
        }
      });
    });

    // Start countdown timer
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _scanSecondsRemaining--;
        
        if (_scanSecondsRemaining <= 0) {
          _stopScan();
        }
      });
    });
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    
    setState(() {
      _isScanning = false;
    });
  }

  // ==================== CONNECTION FLOW ====================

  void _showConnectDialog(_DiscoveredDevice device) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Connect to ${device.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send a connection request to this device.'),
            const SizedBox(height: 16),
            
            // Device info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    device.isRapidMesh ? Icons.hub : Icons.bluetooth,
                    color: device.isRapidMesh ? AppTheme.primary : AppTheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(device.address, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            Text(
              'Note: The other user will need to accept your connection request.',
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

  void _sendConnectionRequest(_DiscoveredDevice device) {
    // Show sending state
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
          ],
        ),
      ),
    );

    // Simulate waiting for response (in real app, would wait for actual response via BT)
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pop(context); // Close loading dialog
      
      // For demo, show what happens on RECEIVER side
      _showReceiverAcceptDialog(device);
    });
  }

  /// This simulates what the OTHER device sees when receiving a connection request
  void _showReceiverAcceptDialog(_DiscoveredDevice senderDevice) {
    // In real app, this would appear on the OTHER person's phone
    // We're showing it here for demonstration
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.bluetooth_connected, color: AppTheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('Connection Request')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"Your Phone" wants to connect with you.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            
            Text(
              'If you accept, they will be able to:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            
            ...['Send you messages', 'Share files with you'].map((item) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Text(item),
                ],
              ),
            )),
            
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If you reject, they cannot try again for 5 minutes.',
                      style: TextStyle(fontSize: 13, color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // REJECT BUTTON
          SizedBox(
            width: 130,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleRejection(senderDevice);
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.error, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'REJECT',
                style: TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          
          // ACCEPT BUTTON
          SizedBox(
            width: 130,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleAcceptance(senderDevice);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'ACCEPT',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAcceptance(_DiscoveredDevice device) {
    // Connection established!
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Connected to ${device.name}! You can now chat and share files.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );

    // Navigate to chat screen
    Future.delayed(const Duration(milliseconds: 1500), () {
      Navigator.pushReplacementNamed(context, '/chat', arguments: device.name);
    });
  }

  void _handleRejection(_DiscoveredDevice device) {
    // Set cooldown
    setState(() {
      _cooldowns[device.address] = DateTime.now().add(
        const Duration(minutes: AppConstants.rejectionCooldownMinutes),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✗ Connection rejected by ${device.name}. You can try again in 5 minutes.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 4),
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
