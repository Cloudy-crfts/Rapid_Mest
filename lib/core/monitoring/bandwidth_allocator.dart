import 'dart:async';
import 'dart:typed_data';
import '../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/logger.dart';

/// Bandwidth Allocation Strategy
enum AllocationStrategy {
  equal,       // Equal share to all connections
  priority,    // Priority-based (newer transfers get more)
  weighted,    // Weighted by transfer size/progress
  adaptive,    // Adapts based on network conditions
}

/// Connection Bandwidth Info
class ConnectionBandwidth {
  final String deviceId;
  int allocatedBps;        // Currently allocated bandwidth
  int usedBps;             // Actually used bandwidth
  int totalBytesTransferred;
  int activeTransfers;     // Number of active transfers
  double priority;         // Priority weight (0.0 - 1.0)
  DateTime? lastActivity;

  ConnectionBandwidth({
    required this.deviceId,
    this.allocatedBps = 0,
    this.usedBps = 0,
    this.totalBytesTransferred = 0,
    this.activeTransfers = 0,
    this.priority = 1.0,
    this.lastActivity,
  });

  /// Get utilization percentage
  double get utilization => allocatedBps > 0 ? usedBps / allocatedBps : 0;

  /// Update last activity timestamp
  void touch() => lastActivity = DateTime.now();
}

/// Bandwidth Allocator
/// 
/// Manages fair distribution of Bluetooth bandwidth across multiple
/// simultaneous connections and transfers.
/// 
/// Features:
/// - Equal or priority-based allocation
/// - Dynamic adjustment when connections change
/// - Reserved bandwidth for control messages
/// - Throttle factor support (for thermal management)
/// - Real-time speed monitoring and adjustment
/// 
/// Algorithm:
/// 1. Calculate total available bandwidth (max BT throughput)
/// 2. Reserve percentage for control/signaling (~10%)
/// 3. Divide remaining equally among active connections
/// 4. Apply thermal/power throttle factor if needed
/// 5. Monitor actual usage and adjust if needed

class BandwidthAllocator {
  static final BandwidthAllocator _instance = BandwidthAllocator._internal();
  
  // Singleton instance
  static BandwidthAllocator get instance => _instance;

  // Configuration
  final int _maxThroughputBps = AppConstants.maxBluetoothThroughputBps;
  final double _reservedBandwidthPercent = AppConstants.reservedBandwidthPercent;
  final int _minPerConnectionBps = AppConstants.minBandwidthPerConnectionBps;

  // Current strategy
  AllocationStrategy _strategy = AllocationStrategy.equal;
  AllocationStrategy get strategy => _strategy;

  // Active connections with their bandwidth info
  final Map<String, ConnectionBandwidth> _connections = {};
  
  // Global throttle factor (from thermal monitor, 0.0-1.0)
  double _throttleFactor = 1.0;
  double get throttleFactor => _throttleFactor;

  // Monitoring
  Timer? _adjustmentTimer;
  bool _isAdjusting = false;

  // Callbacks
  typedef OnAllocationChangedCallback = void Function(String deviceId, int newAllocation);
  OnAllocationChangedCallback? onAllocationChanged;

  // Statistics
  int _totalAllocated = 0;
  int _totalUsed = 0;
  DateTime _lastAdjustment = DateTime.now();

  // Private constructor
  BandwidthAllocator._internal();

  /// Set allocation strategy
  void setStrategy(AllocationStrategy strategy) {
    _strategy = strategy;
    AppLogger.info('Bandwidth strategy changed to: $strategy', 'Bandwidth');
    _recalculate();
  }

  /// Set global throttle factor (from thermal monitoring)
  void setThrottleFactor(double factor) {
    _throttleFactor = factor.clamp(0.0, 1.0);
    _recalculate();
    
    if (_throttleFactor < 1.0) {
      AppLogger.debug('Throttle factor applied: ${(_throttleFactor * 100).toInt()}%', 'Bandwidth');
    }
  }

  /// Register an active connection
  void registerConnection(String deviceId) {
    if (!_connections.containsKey(deviceId)) {
      _connections[deviceId] = ConnectionBandwidth(deviceId: deviceId);
      AppLogger.debug('Connection registered: $deviceId', 'Bandwidth');
      _recalculate();
    }
  }

  /// Unregister a connection
  void unregisterConnection(String deviceId) {
    if (_connections.remove(deviceId) != null) {
      AppLogger.debug('Connection unregistered: $deviceId', 'Bandwidth');
      _recalculate();
    }
  }

  /// Update connection activity (call when sending/receiving data)
  void updateActivity(String deviceId, {int bytesTransferred = 0}) {
    final conn = _connections[deviceId];
    if (conn != null) {
      conn.touch();
      conn.totalBytesTransferred += bytesTransferred;
      
      // Update instantaneous usage (simplified)
      // In production, would use rolling average
      conn.usedBps = bytesTransferred; // Placeholder
    }
  }

  /// Set number of active transfers for a connection
  void setActiveTransfers(String deviceId, int count) {
    final conn = _connections[deviceId];
    if (conn != null) {
      conn.activeTransfers = count;
      _recalculate();
    }
  }

  /// Set connection priority (higher = more bandwidth)
  void setPriority(String deviceId, double priority) {
    final conn = _connections[deviceId];
    if (conn != null) {
      conn.priority = priority.clamp(0.1, 2.0); // Allow 0.1x to 2x
      _recalculate();
    }
  }

  /// Get current allocation for a device
  int getAllocation(String deviceId) {
    return _connections[deviceId]?.allocatedBps ?? 0;
  }

  /// Check if sending is allowed based on allocation
  bool canSend(String deviceId, {int packetSize = 0}) {
    final conn = _connections[deviceId];
    if (conn == null || conn.allocatedBps <= 0) return false;
    
    // Simple check: don't exceed allocation too much
    // In production, would use token bucket or similar
    return true;
  }

  /// Recalculate allocations for all connections
  void _recalculate() {
    if (_connections.isEmpty) {
      _totalAllocated = 0;
      return;
    }

    final connectionCount = _connections.length;
    
    // Calculate available bandwidth after reserve
    final reservedBps = (_maxThroughputBps * _reservedBandwidthPercent).toInt();
    var availableBps = _maxThroughputBps - reservedBps;
    
    // Apply throttle factor
    availableBps = (availableBps * _throttleFactor).toInt();
    
    // Allocate based on strategy
    switch (_strategy) {
      case AllocationStrategy.equal:
        _allocateEqual(availableBps, connectionCount);
        break;
      case AllocationStrategy.priority:
        _allocatePriority(availableBps);
        break;
      case AllocationStrategy.weighted:
        _allocateWeighted(availableBps);
        break;
      case AllocationStrategy.adaptive:
        _allocateAdaptive(availableBps);
        break;
    }

    _lastAdjustment = DateTime.now();
    _notifyChanges();
  }

  /// Equal allocation strategy
  void _allocateEqual(int availableBps, int count) {
    final perConnection = (availableBps / count).toInt();
    
    // Ensure minimum per connection
    final allocation = perConnection >= _minPerConnectionBps 
        ? perConnection 
        : _minPerConnectionBps;
    
    for (final conn in _connections.values) {
      conn.allocatedBps = allocation;
    }
    
    _totalAllocated = allocation * count;
  }

  /// Priority-based allocation
  void _allocatePriority(int availableBps) {
    // Calculate total priority weight
    double totalWeight = 0;
    for (final conn in _connections.values) {
      totalWeight += conn.priority;
    }
    
    if (totalWeight == 0) totalWeight = 1;
    
    // Allocate proportionally
    for (final conn in _connections.values) {
      final share = (conn.priority / totalWeight) * availableBps;
      conn.allocatedBps = share.toInt().clamp(_minPerConnectionBps, availableBps);
    }
  }

  /// Weighted allocation (by transfer count and size)
  void _allocateWeighted(int availableBps) {
    // More transfers = more bandwidth needed
    double totalWeight = 0;
    for (final conn in _connections.values) {
      // Weight = base + (active transfers * bonus)
      final weight = 1.0 + (conn.activeTransfers * 0.5);
      conn.priority = weight; // Store for reference
      totalWeight += weight;
    }
    
    if (totalWeight == 0) totalWeight = 1;
    
    for (final conn in _connections.values) {
      final share = (conn.priority / totalWeight) * availableBps;
      conn.allocatedBps = share.toInt().clamp(_minPerConnectionBps, availableBps);
    }
  }

  /// Adaptive allocation (based on recent usage patterns)
  void _allocateAdaptive(int availableBps) {
    // Give more to connections that are actively using their allocation
    // Less to idle ones
    
    double totalScore = 0;
    final scores = <String, double>{};
    
    for (final entry in _connections.entries) {
      final deviceId = entry.key;
      final conn = entry.value;
      
      // Score based on utilization and recency
      double score = 1.0;
      
      // Higher utilization = higher score (up to a point)
      if (conn.utilization > 0.8) {
        score *= 1.3; // Boost high utilizers slightly
      } else if (conn.utilization < 0.2) {
        score *= 0.7; // Reduce idle connections
      }
      
      // Recent activity bonus
      if (conn.lastActivity != null) {
        final minutesSinceActivity = DateTime.now().difference(conn.lastActivity!).inMinutes;
        if (minutesSinceActivity < 1) {
          score *= 1.2; // Recently active
        } else if (minutesSinceActivity > 5) {
          score *= 0.8; // Idle for a while
        }
      }
      
      scores[deviceId] = score;
      totalScore += score;
    }
    
    if (totalScore == 0) totalScore = 1;
    
    // Allocate by score
    for (final entry in _connections.entries) {
      final deviceId = entry.key;
      final conn = entry.value;
      final score = scores[deviceId] ?? 1.0;
      
      final share = (score / totalScore) * availableBps;
      conn.allocatedBps = share.toInt().clamp(_minPerConnectionBps, availableBps);
    }
  }

  /// Notify listeners of allocation changes
  void _notifyChanges() {
    for (final entry in _connections.entries) {
      onAllocationChanged?.call(entry.key, entry.value.allocatedBps);
    }
  }

  /// Start automatic adjustment timer
  void startAutoAdjust({Duration interval = const Duration(seconds: 2)}) {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = Timer.periodic(interval, (_) {
      _recalculate();
    });
  }

  /// Stop auto adjustment
  void stopAutoAdjust() {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = null;
  }

  /// Get allocation summary for display
  Map<String, dynamic> getSummary() {
    return {
      'strategy': _strategy.toString(),
      'maxThroughput': _maxThroughputBps,
      'throttleFactor': _throttleFactor,
      'activeConnections': _connections.length,
      'totalAllocated': _totalAllocated,
      'perConnection': _connections.isNotEmpty 
          ? (_totalAllocated / _connections.length).round() : 0,
      'connections': _connections.map((key, value) => MapEntry(
        key,
        {
          'allocated': Helpers.formatTransferSpeed(value.allocatedBps),
          'transfers': value.activeTransfers,
          'priority': value.priority.toStringAsFixed(2),
        },
      )),
    };
  }

  /// Get human-readable allocation info for a device
  String getDeviceInfo(String deviceId) {
    final conn = _connections[deviceId];
    if (conn == null) return 'Not connected';
    
    return '''${Helpers.formatTransferSpeed(conn.allocatedBps)} allocated
(${conn.activeTransfers} active transfer${conn.activeTransfers != 1 ? 's' : ''})''';
  }

  /// Dispose resources
  void dispose() {
    stopAutoAdjust();
    _connections.clear();
  }
}
