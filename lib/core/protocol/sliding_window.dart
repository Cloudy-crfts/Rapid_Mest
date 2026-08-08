import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'packet_definitions.dart';

/// Sliding Window Protocol State
enum SlidingWindowState {
  idle,
  sending,
  receiving,
  waitingForAck,
  completed,
  failed,
  paused,
}

/// Sliding Window Entry - tracks a single packet in the window
class SlidingWindowEntry {
  final int sequenceNumber;
  final Packet packet;
  final DateTime sentAt;
  int retryCount;
  bool acknowledged;

  SlidingWindowEntry({
    required this.sequenceNumber,
    required this.packet,
    DateTime? sentAt,
    this.retryCount = 0,
    this.acknowledged = false,
  }) : sentAt = sentAt ?? DateTime.now();

  /// Check if this entry has timed out waiting for ACK
  bool get isTimedOut {
    final elapsed = DateTime.now().difference(sentAt).inMilliseconds;
    return elapsed > AppConstants.ackTimeoutMs && !acknowledged;
  }

  /// Check if max retries exceeded
  bool get isMaxRetriesExceeded => retryCount >= AppConstants.maxChunkRetries;
}

/// Sliding Window Protocol
/// 
/// Implements a reliable, ordered data transfer protocol over Bluetooth
/// using sliding window flow control with selective repeat ARQ.
/// 
/// Key Features:
/// - Configurable window size (default: 32 packets)
/// - Selective Repeat ARQ for handling losses
/// - Automatic retransmission of lost packets
/// - Pause/Resume support for interrupted transfers
/// - Sequence number tracking for ordering
/// - Congestion awareness (back off on repeated failures)
/// 
/// How it works:
/// 1. Sender transmits up to N packets without waiting for ACKs
/// 2. Receiver acknowledges each packet individually
/// 3. Sender slides window forward as ACKs arrive
/// 4. Unacknowledged packets are retransmitted after timeout
/// 5. Out-of-order packets are buffered at receiver

class SlidingWindowProtocol {
  // Configuration
  final int windowSize;
  final int ackTimeoutMs;
  final int maxRetries;

  // State
  SlidingWindowState _state = SlidingWindowState.idle;
  SlidingWindowState get state => _state;

  // Sequence numbers
  int _nextSendSequence = 0;
  int _nextReceiveSequence = 0;
  int _baseSequence = 0; // Oldest unacknowledged packet

  // Send window
  final Map<int, SlidingWindowEntry> _sendWindow = {};
  
  // Receive buffer (for out-of-order packets)
  final Map<int, Uint8List> _receiveBuffer = {};
  Set<int> get receivedSequences => _receiveBuffer.keys.toSet();

  // Acknowledgment tracking
  final Set<int> _ackedSequences = {};

  // Callbacks
  typedef OnPacketToSendCallback = Future<bool> Function(Packet packet);
  typedef OnDataDeliveredCallback = void Function(Uint8List data, int sequence);
  typedef OnAllAckedCallback = void Function();
  typedef OnErrorCallback = void Function(String error, {int? sequence});
  typedef OnProgressCallback = void Function(int ackedCount, int totalPackets);

  OnPacketToSendCallback? onPacketToSend;
  OnDataDeliveredCallback? onDataDelivered;
  OnAllAckedCallback? onAllAcked;
  OnErrorCallback? onError;
  OnProgressCallback? onProgress;

  // Timer for ACK timeout
  Timer? _ackTimer;

  // Statistics
  int _totalSent = 0;
  int _totalRetransmits = 0;
  int _totalAcksReceived = 0;

  // Constructor
  SlidingWindowProtocol({
    this.windowSize = AppConstants.slidingWindowSize,
    this.ackTimeoutMs = AppConstants.ackTimeoutMs,
    this.maxRetries = AppConstants.maxChunkRetries,
  });

  // ==================== SENDER SIDE ====================

  /// Initialize sender with total packet count
  void initializeSender(int totalPackets) {
    _reset();
    _state = SlidingWindowState.sending;
    _totalSent = 0;
    
    AppLogger.protocol('Sender initialized, window size: $windowSize, total: $totalPackets');
  }

  /// Add a packet to send window and transmit if possible
  /// 
  /// Returns true if packet was sent or queued, false if window is full
  Future<bool> sendPacket(Packet packet) async {
    if (_state != SlidingWindowState.sending && 
        _state != SlidingWindowState.waitingForAck) {
      throw Exception('Protocol not in sending state');
    }

    final seq = _nextSendSequence;
    
    // Create window entry
    _sendWindow[seq] = SlidingWindowEntry(
      sequenceNumber: seq,
      packet: packet,
    );
    
    _nextSendSequence++;
    
    // Try to send immediately if within window
    if (_canSend()) {
      return await _transmitPacket(seq);
    }
    
    return true; // Queued successfully
  }

  /// Process incoming ACK
  void handleAck(int ackedSequence) {
    if (_sendWindow.containsKey(ackedSequence)) {
      final entry = _sendWindow[ackedSequence]!;
      entry.acknowledged = true;
      _ackedSequences.add(ackedSequence);
      _totalAcksReceived++;
      
      AppLogger.debug('ACK received for sequence: $ackedSequence', 'Protocol');
      
      // Slide window forward
      _slideWindow();
      
      // Report progress
      onProgress?.call(_ackedSequences.length, _sendWindow.length + _nextSendSequence - _baseSequence);
      
      // Check if all sent packets have been ACKed
      if (_isAllAcked()) {
        _state = SlidingWindowState.completed;
        _stopAckTimer();
        onAllAcked?.call();
        AppLogger.protocol('All packets acknowledged!');
      }
    }
  }

  /// Handle cumulative ACK (all sequences up to and including this one)
  void handleCumulativeAck(int lastAckedSequence) {
    for (int seq = _baseSequence; seq <= lastAckedSequence; seq++) {
      if (_sendWindow.containsKey(seq)) {
        handleAck(seq);
      }
    }
  }

  /// Check if we can send more packets
  bool _canSend() {
    final inFlightCount = _sendWindow.values.where((e) => !e.acknowledged).length;
    return inFlightCount < windowSize;
  }

  /// Transmit a specific packet by sequence number
  Future<bool> _transmitPacket(int sequence) async {
    final entry = _sendWindow[sequence];
    if (entry == null || entry.acknowledged) return true;
    
    try {
      // Mark as retransmission if retrying
      if (entry.retryCount > 0) {
        entry.packet.header.flags |= PacketHeader.flagRetransmit;
        _totalRetransmits++;
      }
      
      // Call callback to actually send
      final success = await onPacketToSend?.call(entry.packet) ?? false;
      
      if (success) {
        entry.sentAt = DateTime.now();
        _totalSent++;
        
        // Start/restart ACK timer
        _startAckTimer();
        
        AppLogger.debug('Transmitted sequence: $sequence', 'Protocol');
        
        // Try to send next queued packet
        _transmitNextQueued();
      } else {
        onError?.call('Failed to send packet', sequence: sequence);
      }
      
      return success;
    } catch (e) {
      AppLogger.error('Transmission error for sequence: $sequence', 'Protocol', e);
      onError?.call(e.toString(), sequence: sequence);
      return false;
    }
  }

  /// Transmit next queued packet if window allows
  void _transmitNextQueued() {
    for (final seq in _sendWindow.keys.toList()..sort()) {
      final entry = _sendWindow[seq];
      if (entry != null && !entry.acknowledged && entry.retryCount == 0) {
        if (_canSend()) {
          _transmitPacket(seq);
          break;
        }
      }
    }
  }

  /// Slide window forward based on ACKs
  void _slideWindow() {
    // Find new base (oldest unacknowledged)
    while (_sendWindow.containsKey(_baseSequence) && 
           _sendWindow[_baseSequence]!.acknowledged) {
      _sendWindow.remove(_baseSequence);
      _baseSequence++;
    }
    
    // Clean up old entries
    final keysToRemove = <int>[];
    for (final seq in _sendWindow.keys) {
      if (seq < _baseSequence || _sendWindow[seq]!.acknowledged) {
        keysToRemove.add(seq);
      }
    }
    for (final seq in keysToRemove) {
      _sendWindow.remove(seq);
    }
  }

  /// Check if all packets have been acknowledged
  bool _isAllAcked() {
    return _sendWindow.values.every((e) => e.acknowledged);
  }

  // ==================== RECEIVER SIDE ====================

  /// Initialize receiver
  void initializeReceiver() {
    _reset();
    _state = SlidingWindowState.receiving;
    _receiveBuffer.clear();
    _nextReceiveSequence = 0;
    
    AppLogger.protocol('Receiver initialized');
  }

  /// Handle incoming packet at receiver side
  /// 
  /// Returns true if packet was accepted, false if duplicate/out of range
  bool receivePacket(Packet packet) {
    if (_state != SlidingWindowState.receiving) {
      return false;
    }
    
    final seq = packet.header.sequenceNumber;
    
    // Check for duplicate
    if (_receiveBuffer.containsKey(seq)) {
      // Duplicate - resend ACK
      _sendAck(seq);
      return false;
    }
    
    // Accept packet (even out-of-order) and buffer it
    _receiveBuffer[seq] = packet.payload ?? Uint8List(0);
    
    // Send individual ACK
    _sendAck(seq);
    
    // Deliver any in-order packets
    _deliverInOrderPackets();
    
    return true;
  }

  /// Deliver packets that are now in order
  void _deliverInOrderPackets() {
    while (_receiveBuffer.containsKey(_nextReceiveSequence)) {
      final data = _receiveBuffer.remove(_nextReceiveSequence)!;
      
      // Deliver to application layer
      onDataDelivered?.call(data, _nextReceiveSequence);
      
      _nextReceiveSequence++;
    }
  }

  /// Send acknowledgment for a sequence
  void _sendAck(int sequence) {
    // This would be handled by the caller via callback
    // The actual ACK packet creation is done elsewhere
    AppLogger.debug('ACK ready for sequence: $sequence', 'Protocol');
  }

  // ==================== TIMEOUT & RETRANSMISSION ====================

  /// Start ACK timeout timer
  void _startAckTimer() {
    _ackTimer?.cancel();
    _ackTimer = Timer(Duration(milliseconds: ackTimeoutMs), _checkTimeouts);
  }

  /// Stop ACK timer
  void _stopAckTimer() {
    _ackTimer?.cancel();
    _ackTimer = null;
  }

  /// Check for timed-out packets and retransmit
  void _checkTimeouts() {
    if (_state != SlidingWindowState.sending && 
        _state != SlidingWindowState.waitingForAck) {
      return;
    }
    
    bool hasUnacked = false;
    
    for (final entry in _sendWindow.values) {
      if (!entry.acknowledged) {
        hasUnacked = true;
        
        if (entry.isTimedOut) {
          if (entry.isMaxRetriesExceeded) {
            // Max retries exceeded - fail transfer
            _state = SlidingWindowState.failed;
            _stopAckTimer();
            onError?.call('Max retries exceeded for sequence ${entry.sequenceNumber}', 
                          sequence: entry.sequenceNumber);
            return;
          } else {
            // Retransmit
            entry.retryCount++;
            AppLogger.debug('Retransmitting sequence: ${entry.sequenceNumber}, attempt: ${entry.retryCount}', 'Protocol');
            _transmitPacket(entry.sequenceNumber);
          }
        }
      }
    }
    
    // Restart timer if there are still unacked packets
    if (hasUnacked) {
      _startAckTimer();
    }
  }

  // ==================== PAUSE / RESUME ====================

  /// Pause transmission (e.g., device went out of range)
  void pause() {
    if (_state == SlidingWindowState.sending || 
        _state == SlidingWindowState.waitingForAck) {
      _state = SlidingWindowState.paused;
      _stopAckTimer();
      AppLogger.protocol('Transfer paused');
    }
  }

  /// Resume transmission after pause
  void resume() {
    if (_state == SlidingWindowState.paused) {
      _state = SlidingWindowState.sending;
      
      // Retransmit all unacked packets
      for (final entry in _sendWindow.values) {
        if (!entry.acknowledged) {
          entry.retryCount = 0; // Reset retry count on resume
          _transmitPacket(entry.sequenceNumber);
        }
      }
      
      AppLogger.protocol('Transfer resumed');
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Reset protocol state
  void _reset() {
    _stopAckTimer();
    _sendWindow.clear();
    _receiveBuffer.clear();
    _ackedSequences.clear();
    _nextSendSequence = 0;
    _nextReceiveSequence = 0;
    _baseSequence = 0;
    _totalSent = 0;
    _totalRetransmits = 0;
    _totalAcksReceived = 0;
  }

  /// Get current statistics
  Map<String, dynamic> getStatistics() {
    return {
      'state': _state.toString(),
      'windowSize': windowSize,
      'inFlight': _sendWindow.values.where((e) => !e.acknowledged).length,
      'totalSent': _totalSent,
      'totalRetransmits': _totalRetransmits,
      'totalAcksReceived': _totalAcksReceived,
      'nextSendSeq': _nextSendSequence,
      'nextReceiveSeq': _nextReceiveSequence,
      'baseSeq': _baseSequence,
      'ackedCount': _ackedSequences.length,
      'bufferedCount': _receiveBuffer.length,
    };
  }

  /// Get number of unacknowledged packets
  int get unackedCount => _sendWindow.values.where((e) => !e.acknowledged).length;

  /// Get window utilization (0.0 to 1.0)
  double get windowUtilization => unackedCount / windowSize;

  /// Dispose resources
  void dispose() {
    _stopAckTimer();
    _reset();
    _state = SlidingWindowState.idle;
  }
}
