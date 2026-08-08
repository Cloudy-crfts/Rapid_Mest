import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import '../utils/constants.dart';
import '../../utils/logger.dart';

/// Thermal State
enum ThermalState {
  normal,      // Operating normally
  warm,        # Slightly warm, consider throttling
  hot,         # Hot, should throttle
  critical,    # Very hot, must pause operations
  unknown,     # Cannot determine
}

/// Power State
enum PowerState {
  charging,
  discharging,
  full,
  notCharging,
  unknown,
}

/// Thermal & Power Monitoring Service
/// 
/// Monitors device temperature and battery level to make intelligent
/// decisions about throttling or pausing transfers.
/// 
/// Features:
/// - Temperature monitoring (when available)
/// - Battery level tracking
/// - Automatic throttling based on thermal state
/// - Power-aware transfer management
/// - Configurable thresholds

class ThermalMonitor {
  static final ThermalMonitor _instance = ThermalMonitor._internal();
  
  // Singleton instance
  static ThermalMonitor get instance => _instance;

  // Battery instance
  final Battery _battery = Battery();

  // Current state
  ThermalState _thermalState = ThermalState.unknown;
  ThermalState get thermalState => _thermalState;

  PowerState _powerState = PowerState.unknown;
  PowerState get powerState => _powerState;

  int _batteryLevel = 100;
  int get batteryLevel => _batteryLevel;

  double? _currentTemperature; // Celsius
  double? get currentTemperature => _currentTemperature;

  // Thresholds (configurable)
  double _throttleStartTemp = AppConstants.thermalThrottleStartCelsius;   // 38°C
  double _pauseTemp = AppConstants.thermalPauseThresholdCelsius;          // 42°C
  int _lowBatteryThreshold = AppConstants.batteryLowThresholdPercent;     // 20%
  int _criticalBatteryThreshold = AppConstants.batteryCriticalThresholdPercent; // 10%

  // Monitoring
  Timer? _monitorTimer;
  bool _isMonitoring = false;

  // Callbacks
  typedef OnThermalStateChangedCallback = void Function(ThermalState oldState, ThermalState newState);
  typedef OnPowerStateChangedCallback = void Function(PowerState state, int level);
  typedef OnThrottleRequiredCallback = void Function(double throttleFactor); // 0.0-1.0
  typedef OnPauseRequiredCallback = void Function(String reason);
  typedef OnResumeAllowedCallback = void Function();
  
  OnThermalStateChangedCallback? onThermalStateChanged;
  OnPowerStateChangedCallback? onPowerStateChanged;
  OnThrottleRequiredCallback? onThrottleRequired;
  OnPauseRequiredCallback? onPauseRequired;
  OnResumeAllowedCallback? onResumeAllowed;

  // History for trend analysis
  final List<double> _temperatureHistory = [];
  static const int _maxHistoryLength = 60; // Keep last 60 readings

  // Private constructor
  ThermalMonitor._internal();

  /// Initialize the monitor
  Future<bool> initialize() async {
    try {
      AppLogger.info('Initializing Thermal Monitor', 'Thermal');
      
      // Get initial battery state
      final level = await _battery.batteryLevel;
      _batteryLevel = level ?? 100;
      
      final state = await _battery.batteryState;
      _powerState _mapBatteryState(state);
      
      // Try to get initial temperature
      await _updateTemperature();
      
      AppLogger.info('Thermal Monitor initialized', 'Thermal');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Thermal Monitor', 'Thermal', e, stackTrace);
      return false;
    }
  }

  /// Start periodic monitoring
  void startMonitoring({int intervalMs = AppConstants.thermalCheckIntervalMs}) {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    
    _monitorTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _checkStatus(),
    );
    
    AppLogger.info('Thermal monitoring started (interval: ${intervalMs}ms)', 'Thermal');
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _isMonitoring = false;
    
    AppLogger.info('Thermal monitoring stopped', 'Thermal');
  }

  /// Perform a single status check
  Future<void> _checkStatus() async {
    // Update battery
    await _updateBattery();
    
    // Update temperature
    await _updateTemperature();
    
    // Evaluate thermal state
    await _evaluateThermalState();
    
    // Evaluate power state
    _evaluatePowerState();
  }

  /// Update battery information
  Future<void> _updateBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      
      final newLevel = level ?? 100;
      final newState = _mapBatteryState(state);
      
      bool changed = false;
      
      if (newLevel != _batteryLevel) {
        _batteryLevel = newLevel;
        changed = true;
      }
      
      if (newState != _powerState) {
        final oldState = _powerState;
        _powerState = newState;
        onPowerStateChanged?.call(newState, _batteryLevel);
        AppLogger.debug('Power state changed: $oldState -> $newState ($_batteryLevel%)', 'Thermal');
        changed = true;
      }
      
      if (changed) {
        _evaluatePowerState();
      }
    } catch (e) {
      AppLogger.error('Failed to update battery info', 'Thermal', e);
    }
  }

  /// Update temperature reading
  Future<void> _updateTemperature() async {
    try {
      // Note: Android doesn't provide direct temperature API to apps
      // This would require platform channel to read from thermal zone files
      // For now, we'll simulate or use available APIs
      
      // In production:
      // final temp = await MethodChannel('com.rapidmesh/thermal').invokeMethod('getTemperature');
      
      // Simulated/estimated value (would be real in production)
      // This could use battery temperature sensor if available
      final temp = await _readBatteryTemperature();
      
      if (temp != null) {
        _currentTemperature = temp;
        
        // Add to history
        _temperatureHistory.add(temp);
        if (_temperatureHistory.length > _maxHistoryLength) {
          _temperatureHistory.removeAt(0);
        }
      }
    } catch (e) {
      // Temperature reading may not be available on all devices
      AppLogger.debug('Temperature reading unavailable', 'Thermal');
    }
  }

  /// Read battery temperature (platform-specific)
  Future<double?> _readBatteryTemperature() async {
    try {
      // This would use platform channel in production
      // Reading from /sys/class/thermal/ or /sys/class/power_supply/battery/temp
      
      // Return null if unavailable
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Map battery plugin state to our enum
  PowerState _mapBatteryState(BatteryState? state) {
    switch (state) {
      case BatteryState.charging:
        return PowerState.charging;
      case BatteryState.discharging:
        return PowerState.discharging;
      case BatteryState.full:
        return PowerState.full;
      case BatteryState.notCharging:
        return PowerState.notCharging;
      default:
        return PowerState.unknown;
    }
  }

  /// Evaluate and update thermal state
  Future<void> _evaluateThermalState() async {
    if (_currentTemperature == null) return;
    
    final temp = _currentTemperature!;
    final oldState = _thermalState;
    ThermalState newState;
    
    if (temp >= _pauseTemp) {
      newState = ThermalState.critical;
    } else if (temp >= _throttleStartTemp) {
      newState = ThermalState.hot;
    } else if (temp >= _throttleStartTemp - 3) { // 35°C+ is "warm"
      newState = ThermalState.warm;
    } else {
      newState = ThermalState.normal;
    }
    
    if (newState != _thermalState) {
      _thermalState = newState;
      onThermalStateChanged?.call(oldState, newState);
      AppLogger.warn('Thermal state changed: $oldState -> $newState (${temp.toStringAsFixed(1)}°C)', 'Thermal');
      
      // Take action based on new state
      _applyThermalPolicy(newState);
    }
  }

  /// Apply policy based on thermal state
  void _applyThermalPolicy(ThermalState state) {
    switch (state) {
      case ThermalState.critical:
        // Must pause all intensive operations
        onPauseRequired?.call(
          'Device temperature too high (${_currentTemperature!.toStringAsFixed(1)}°C). '
          'Transfers paused until device cools down.'
        );
        break;
        
      case ThermalState.hot:
        // Heavy throttling required (~50% speed)
        onThrottleRequired?.call(0.5);
        break;
        
      case ThermalState.warm:
        // Light throttling (~75% speed)
        onThrottleRequired?.call(0.75);
        break;
        
      case ThermalState.normal:
        // Full speed ahead!
        onThrottleRequired?.call(1.0);
        onResumeAllowed?.call();
        break;
        
      case ThermalState.unknown:
        // Conservative default
        onThrottleRequired?.call(0.8);
        break;
    }
  }

  /// Evaluate power state and take action
  void _evaluatePowerState() {
    switch (_powerState) {
      case PowerState.charging:
        // While charging, we can be more aggressive with transfers
        // No special action needed
        break;
        
      case PowerState.discharging:
        if (_batteryLevel <= _criticalBatteryThreshold) {
          // Critical battery - pause large transfers
          onPauseRequired?.call(
            'Critical battery level ($_batteryLevel%). '
            'Large file transfers paused.'
          );
        } else if (_batteryLevel <= _lowBatteryThreshold) {
          // Low battery - throttle
          onThrottleRequired?.call(0.6);
        }
        break;
        
      case PowerState.full:
        // Fully charged - no restrictions
        onThrottleRequired?.call(1.0);
        break;
        
      default:
        break;
    }
  }

  /// Calculate recommended throttle factor (0.0 to 1.0)
  double calculateThrottleFactor() {
    double factor = 1.0;
    
    // Thermal factor
    switch (_thermalState) {
      case ThermalState.critical:
        factor = 0.0; // Stop completely
        break;
      case ThermalState.hot:
        factor = 0.5;
        break;
      case ThermalState.warm:
        factor = 0.75;
        break;
      default:
        factor = 1.0;
    }
    
    // Power factor (take more restrictive)
    double powerFactor = 1.0;
    if (_powerState == PowerState.discharging) {
      if (_batteryLevel <= _criticalBatteryThreshold) {
        powerFactor = 0.0;
      } else if (_batteryLevel <= _lowBatteryThreshold) {
        powerFactor = 0.6;
      }
    }
    
    // Use the more restrictive factor
    return factor < powerFactor ? factor : powerFactor;
  }

  /// Check if transfers are allowed
  bool get areTransfersAllowed {
    if (_thermalState == ThermalState.critical) return false;
    if (_powerState == PowerState.discharging && 
        _batteryLevel <= _criticalBatteryThreshold) return false;
    return true;
  }

  /// Check if we should be in power-saving mode
  bool get shouldUsePowerSavingMode {
    return _thermalState == ThermalState.hot ||
           _thermalState == ThermalState.critical ||
           (_powerState == PowerState.discharging && _batteryLevel <= _lowBatteryThreshold);
  }

  /// Get temperature trend (rising/falling/stable)
  String get temperatureTrend {
    if (_temperatureHistory.length < 5) return 'Unknown';
    
    final recent = _temperatureHistory.sublist(_temperatureHistory.length - 5);
    final avgFirst = recent.sublist(0, 2).reduce((a, b) => a + b) / 2;
    final avgLast = recent.sublist(3).reduce((a, b) => a + b) / 2;
    
    final diff = avgLast - avgFirst;
    if (diff > 0.5) return 'Rising';
    if (diff < -0.5) return 'Falling';
    return 'Stable';
  }

  /// Get detailed status report
  Map<String, dynamic> getStatusReport() {
    return {
      'thermalState': _thermalState.toString(),
      'temperature': _currentTemperature,
      'trend': temperatureTrend,
      'powerState': _powerState.toString(),
      'batteryLevel': _batteryLevel,
      'transfersAllowed': areTransfersAllowed,
      'throttleFactor': calculateThrottleFactor(),
      'powerSaving': shouldUsePowerSavingMode,
    };
  }

  /// Set custom thresholds
  void setThresholds({
    double? throttleStartTemp,
    double? pauseTemp,
    int? lowBatteryPercent,
    int? criticalBatteryPercent,
  }) {
    if (throttleStartTemp != null) _throttleStartTemp = throttleStartTemp;
    if (pauseTemp != null) _pauseTemp = pauseTemp;
    if (lowBatteryPercent != null) _lowBatteryThreshold = lowBatteryPercent;
    if (criticalBatteryPercent != null) _criticalBatteryThreshold = criticalBatteryPercent;
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _temperatureHistory.clear();
  }
}
