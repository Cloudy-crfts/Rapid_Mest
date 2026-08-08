import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Foreground Service Manager
/// 
/// Manages persistent notification to keep the app alive in background
/// and show connection status to user.
/// 
/// Features:
/// - Persistent notification showing active connections
/// - Connection count badge
/// - Transfer status updates
/// - Notification actions (quick disconnect, open app)
/// - Android 13+ notification permission handling

class ForegroundService {
  static final ForegroundService _instance = ForegroundService._internal();
  
  // Singleton instance
  static ForegroundService get instance => _instance;

  // Notification plugin
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  
  // State
  bool _isInitialized = false;
  bool _isShowingNotification = false;
  int _activeConnectionCount = 0;
  List<String> _connectedDeviceNames = [];
  String? _currentTransferInfo;

  // Callbacks
  typedef OnNotificationActionCallback = void Function(String action);
  OnNotificationActionCallback? onAction;

  // Private constructor
  ForegroundService._internal();

  /// Initialize notifications
  Future<bool> initialize() async {
    try {
      AppLogger.info('Initializing Foreground Service', 'Foreground');
      
      const androidSettings = AndroidInitializationSettings('ic_stat_notification');
      const initSettings = InitializationSettings(android: androidSettings);
      
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationAction,
      );
      
      // Request permission on Android 13+
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      }
      
      _isInitialized = true;
      AppLogger.info('Foreground Service initialized', 'Foreground');
      
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize Foreground Service', 'Foreground', e, stackTrace);
      return false;
    }
  }

  /// Show persistent notification with connection info
  Future<void> showPersistentNotification({
    required int connectionCount,
    List<String>? deviceNames,
    String? transferInfo,
  }) async {
    if (!_isInitialized) await initialize();
    
    _activeConnectionCount = connectionCount;
    _connectedDeviceNames = deviceNames ?? [];
    _currentTransferInfo = transferInfo;
    
    final androidDetails = AndroidNotificationDetails(
      'rapid_mesh_connection',
      'Rapid Mesh Connection',
      channelDescription: 'Shows when you have active Bluetooth connections',
      importance: Importance.low, // Low importance = no sound
      priority: Priority.low,
      ongoing: true, // Persistent notification
      showWhen: true,        icon: 'ic_stat_notification',
        subText: transferInfo != null ? 'Transferring...' : null,
      
      // Style
      styleInformation: BigTextStyleInformation(_buildBigContent()),
      
      // Actions
      actions: [
        const AndroidNotificationAction(
          'open_app',
          'Open App',
          icon: '@drawable/ic_open',
        ),
        if (connectionCount > 0)
          const AndroidNotificationAction(
            'disconnect_all',
            'Disconnect All',
            icon: '@drawable/ic_disconnect',
          ),
      ],
    );
    
    const platformDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      0, // ID 0 for our main notification
      _buildTitle(),
      _buildContent(),
      platformDetails,
    );
    
    _isShowingNotification = true;
    AppLogger.debug('Persistent notification shown ($connectionCount connections)', 'Foreground');
  }

  /// Update notification with new info (without recreating)
  Future<void> updateNotification({
    int? connectionCount,
    List<String>? deviceNames,
    String? transferInfo,
  }) async {
    if (!_isShowingNotification) {
      await showPersistentNotification(
        connectionCount: connectionCount ?? _activeConnectionCount,
        deviceNames: deviceNames ?? _connectedDeviceNames,
        transferInfo: transferInfo ?? _currentTransferInfo,
      );
      return;
    }
    
    if (connectionCount != null) _activeConnectionCount = connectionCount;
    if (deviceNames != null) _connectedDeviceNames = deviceNames;
    if (transferInfo != null) _currentTransferInfo = transferInfo;
    
    final androidDetails = AndroidNotificationDetails(
      'rapid_mesh_connection',
      'Rapid Mesh Connection',
      channelDescription: 'Shows when you have active Bluetooth connections',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showWhen: true,        icon: 'ic_stat_notification',
        subText: _currentTransferInfo != null ? 'Transferring...' : null,
      styleInformation: BigTextStyleInformation(_buildBigContent()),
      actions: [
        const AndroidNotificationAction('open_app', 'Open App'),
        if (_activeConnectionCount > 0)
          const AndroidNotificationAction('disconnect_all', 'Disconnect All'),
      ],
    );
    
    const platformDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(0, _buildTitle(), _buildContent(), platformDetails);
    
    AppLogger.debug('Notification updated', 'Foreground');
  }

  /// Hide persistent notification
  Future<void> hidePersistentNotification() async {
    await _notifications.cancel(0);
    _isShowingNotification = false;
    _activeConnectionCount = 0;
    _connectedDeviceNames.clear();
    _currentTransferInfo = null;
    
    AppLogger.debug('Persistent notification hidden', 'Foreground');
  }

  /// Show file transfer progress notification
  Future<void> showTransferProgress({
    required String fileName,
    required double progress,
    required int speedBytesPerSecond,
    bool isSending = true,
    String? toDeviceName,
  }) async {
    final direction = isSending ? 'Sending to' : 'Receiving from';
    final speed = Helpers.formatTransferSpeed(speedBytesPerSecond);
    
    final androidDetails = AndroidNotificationDetails(
      'rapid_mesh_transfer',
      'File Transfer',
      channelDescription: 'Shows file transfer progress',
      importance: Importance.default,
      priority: Priority.default,
      ongoing: true,
      showWhen: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress.round(),        icon: 'ic_stat_notification',
        styleInformation: BigTextStyleInformation(
        '''$fileName

Progress: ${progress.toStringAsFixed(1)}%
Speed: $speed
$direction: ${toDeviceName ?? "device"}''',
      ),
      actions: [
        const AndroidNotificationAction('cancel_transfer', 'Cancel'),
        const AndroidNotificationAction('pause_transfer', 'Pause'),
      ],
    );
    
    const platformDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(1, fileName, '${progress.toStringAsFixed(1)}%', platformDetails);
  }

  /// Update transfer progress
  Future<void> updateTransferProgress({
    double? progress,
    int? speedBytesPerSecond,
  }) async {
    // Would update existing transfer notification
    // Implementation similar to updateNotification but for transfer ID
  }

  /// Hide transfer notification
  Future<void> hideTransferNotification({bool completed = false}) async {
    await _notifications.cancel(1);
    
    if (completed) {
      // Show brief completion notification
      const androidDetails = AndroidNotificationDetails(
        'rapid_mesh_transfer',
        'File Transfer',
        channelDescription: 'Shows file transfer progress',
        importance: Importance.low,
        priority: Priority.low,
        icon: 'ic_stat_notification',
      );
      
      const platformDetails = NotificationDetails(android: androidDetails);
      await _notifications.show(2, 'Transfer Complete', 'File transferred successfully!', platformDetails);
      
      // Auto-dismiss after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _notifications.cancel(2);
      });
    }
  }

  /// Show incoming connection request notification
  Future<void> showConnectionRequest(String fromDeviceName) async {
    final androidDetails = AndroidNotificationDetails(
      'rapid_mesh_requests',
      'Connection Requests',
      channelDescription: 'Incoming connection requests from other devices',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_notification',
      title: 'Connection Request',
      contentText: '$fromDeviceName wants to connect',
      actions: [
        const AndroidNotificationAction('accept', 'Accept'),
        const AndroidNotificationAction('reject', 'Reject'),
      ],
    );
    
    const platformDetails = NotificationDetails(android: androidDetails);
    await _notifications.show(3, 'Connection Request', '$fromDeviceName wants to connect', platformDetails);
  }

  /// Show error/warning notification
  Future<void> showError({
    required String title,
    required String message,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'rapid_mesh_errors',
      'Errors & Warnings',
      channelDescription: 'Error and warning notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_notification',
    );
    
    const platformDetails = NotificationDetails(android: androidDetails);
    await _notifications.show(4, title, message, platformDetails);
  }

  // ==================== PRIVATE HELPERS ====================

  String _buildTitle() {
    if (_activeConnectionCount == 0) {
      return 'Rapid Mesh - Ready';
    } else if (_activeConnectionCount == 1) {
      return 'Connected to ${_connectedDeviceNames.firstOrNull ?? "1 device"}';
    } else {
      return '$_activeConnectionCount devices connected';
    }
  }

  String _buildContent() {
    if (_activeConnectionCount == 0) {
      return 'Tap to scan for nearby devices';
    } else if (_currentTransferInfo != null) {
      return _currentTransferInfo!;
    } else {
      final names = _connectedDeviceNames.take(3).join(', ');
      final extra = _connectedDeviceNames.length > 3 
          ? ' +${_connectedDeviceNames.length - 3} more' 
          : '';
      return 'Active: $names$extra';
    }
  }

  String _buildBigContent() {
    var buffer = StringBuffer();
    
    if (_activeConnectionCount > 0) {
      buffer.writeln('📱 Connected Devices ($_activeConnectionCount)');
      buffer.writeln('');
      
      for (var i = 0; i < _connectedDeviceNames.length && i < 10; i++) {
        buffer.writeln('• ${_connectedDeviceNames[i]}');
      }
      
      if (_connectedDeviceNames.length > 10) {
        buffer.writeln('\n...and ${_connectedDeviceNames.length - 10} more');
      }
    }
    
    if (_currentTransferInfo != null) {
      if (buffer.isNotEmpty) buffer.writeln('');
      buffer.writeln('📁 $_currentTransferInfo');
    }
    
    buffer.writeln('');
    buffer.writeln('⚡ Rapid Mesh - Offline P2P Sharing');
    
    return buffer.toString();
  }

  void _handleNotificationAction(NotificationResponse response) {
    AppLogger.info('Notification action: ${response.actionId}', 'Foreground');
    
    switch (response.actionId) {
      case 'open_app':
        onAction?.call('open_app');
        break;
        
      case 'disconnect_all':
        onAction?.call('disconnect_all');
        break;
        
      case 'accept':
        onAction?.call('accept_connection');
        break;
        
      case 'reject':
        onAction?.call('reject_connection');
        break;
        
      case 'cancel_transfer':
        onAction?.call('cancel_transfer');
        break;
        
      case 'pause_transfer':
        onAction?.call('pause_transfer');
        break;
    }
  }

  /// Get current state
  Map<String, dynamic> getState() {
    return {
      'isInitialized': _isInitialized,
      'isShowingNotification': _isShowingNotification,
      'activeConnections': _activeConnectionCount,
      'connectedDevices': _connectedDeviceNames,
      'hasActiveTransfer': _currentTransferInfo != null,
    };
  }

  /// Dispose resources
  Future<void> dispose() async {
    await hidePersistentNotification();
    await hideTransferNotification();
    _isInitialized = false;
  }
}
