import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/pointycastle.dart' as pc;

import '../bluetooth/connection_events.dart';
import '../database/daos/device_dao.dart';
import '../database/daos/file_transfer_dao.dart';
import '../database/daos/message_dao.dart';
import '../database/models/device.dart';
import '../database/models/file_transfer.dart';
import '../database/models/message.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

/// File Transfer Engine
///
/// Streams files between two phones over the RFCOMM socket. Files are read and
/// written in small chunks so that files of any size (GBs) can be sent as long
/// as the receiving phone has room - the whole file is never held in memory.
///
/// Wire protocol (all packets are already framed by the transport layer):
///   0x20 fileRequest   {transferId, fileName, fileSize, chunkSize, totalChunks, mimeType}
///   0x21 fileResponse  {transferId, accepted}
///   0x22 fileChunk     [idLen][transferId][chunkIndex(4)][sha256(64)][data]
///   0x23 fileChunkAck  [idLen][transferId][chunkIndex(4)]
///   0x24 fileComplete  {transferId}
///   0x25 fileCancel    {transferId}
class FileTransferEngine {
  FileTransferEngine({
    required Future<bool> Function(String address, int type, Uint8List payload)
        send,
    required void Function(ConnectionEvent event) emit,
  })  : _send = send,
        _emit = emit;

  final Future<bool> Function(String address, int type, Uint8List payload) _send;
  final void Function(ConnectionEvent event) _emit;

  final FileTransferDao _transferDao = FileTransferDao();
  final MessageDao _messageDao = MessageDao();
  final DeviceDao _deviceDao = DeviceDao();

  final Map<String, _Outgoing> _outgoing = {};
  final Map<String, _Incoming> _incoming = {};

  Timer? _tickTimer;
  int _chunkSize = AppConstants.streamingChunkSizeBytes;
  int _windowSize = AppConstants.fileTransferWindowSize;

  // ==================== INCOMING (DISPATCH FROM BLUETOOTH SERVICE) ==========

  /// Handle a file-transfer packet received from [address].
  Future<void> handlePacket(String address, int type, Uint8List payload) async {
    try {
      switch (type) {
        case PacketType.fileRequest:
          await _onFileRequest(address, payload);
          break;
        case PacketType.fileResponse:
          await _onFileResponse(payload);
          break;
        case PacketType.fileChunk:
          await _onFileChunk(address, payload);
          break;
        case PacketType.fileChunkAck:
          await _onFileChunkAck(payload);
          break;
        case PacketType.fileComplete:
          await _onFileComplete(payload);
          break;
        case PacketType.fileCancel:
          await _onFileCancel(payload);
          break;
        default:
          break;
      }
    } catch (e) {
      AppLogger.error('File transfer packet error', 'Transfer', e);
    }
  }

  // ==================== SENDING ====================

  /// Start sending the file at [filePath] to [address].
  ///
  /// Returns the transfer id, or null if the file could not be opened.
  Future<String?> startSend({
    required String address,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) async {
    if (fileSize <= 0) {
      AppLogger.warn('Refusing to send empty file: $fileName', 'Transfer');
      return null;
    }

    final transferId = 'f${DateTime.now().microsecondsSinceEpoch}';
    final totalChunks = (fileSize + _chunkSize - 1) ~/ _chunkSize;

    RandomAccessFile raf;
    try {
      raf = await File(filePath).open();
    } catch (e) {
      AppLogger.error('Failed to open file for sending', 'Transfer', e);
      return null;
    }

    final transfer = await _transferDao.insert(FileTransfer(
      transferId: transferId,
      deviceId: address,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      mimeType: mimeType,
      direction: 0,
      status: TransferStatus.pending,
      totalChunks: totalChunks,
      startedAt: DateTime.now(),
    ));

    final message = await _messageDao.insert(Message(
      messageId: 'file-$transferId',
      deviceId: address,
      messageType: MessageType.file,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      mimeType: mimeType,
      status: MessageStatus.sending,
      isOutgoing: true,
    ));

    _outgoing[transferId] = _Outgoing(
      transferId: transferId,
      address: address,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      totalChunks: totalChunks,
      chunkSize: _chunkSize,
      raf: raf,
      dbRowId: transfer.id,
      messageRowId: message.id,
    );

    // Announce the file to the receiver.
    final request = jsonEncode({
      'transferId': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      'chunkSize': _chunkSize,
      'totalChunks': totalChunks,
      'mimeType': mimeType,
    });
    final ok = await _send(address, PacketType.fileRequest,
        Uint8List.fromList(utf8.encode(request)));
    if (!ok) {
      await _failOutgoing(transferId, 'Could not reach $address');
      return null;
    }

    _startTicker();
    _emit(FileTransferProgressEvent(
      address: address,
      transferId: transferId,
      fileName: fileName,
      bytesTransferred: 0,
      totalBytes: fileSize,
      speedBps: 0,
      outgoing: true,
    ));
    AppLogger.transfer('File transfer started: $fileName -> $address');
    return transferId;
  }

  /// Accept an incoming file request and prepare to receive its chunks.
  Future<void> acceptIncoming(String transferId) async {
    final inc = _incoming[transferId];
    if (inc == null || inc.accepted) return;

    try {
      final dir = await _tempDir();
      final tempPath = p.join(dir, 'receiving_$transferId.part');
      inc.raf = await File(tempPath).open(mode: FileMode.write);
      inc.tempPath = tempPath;
      inc.accepted = true;

      if (inc.dbRowId != null) {
        await _transferDao.updateStatus(
            inc.dbRowId!, TransferStatus.transferring);
      }

      final ok = await _send(inc.address, PacketType.fileResponse,
          Uint8List.fromList(utf8.encode(jsonEncode({
            'transferId': transferId,
            'accepted': true,
          }))));
      if (!ok) {
        AppLogger.warn('Could not send accept for $transferId', 'Transfer');
      }
    } catch (e) {
      AppLogger.error('Failed to accept transfer $transferId', 'Transfer', e);
      await _failIncoming(transferId, 'Failed to accept transfer');
    }
  }

  /// Reject an incoming file request.
  Future<void> rejectIncoming(String transferId) async {
    final inc = _incoming[transferId];
    if (inc == null) return;

    await _send(inc.address, PacketType.fileResponse,
        Uint8List.fromList(utf8.encode(jsonEncode({
          'transferId': transferId,
          'accepted': false,
        }))));

    if (inc.dbRowId != null) {
      await _transferDao.updateStatus(
          inc.dbRowId!, TransferStatus.rejected);
    }
    await _cleanupIncoming(inc);
    _incoming.remove(transferId);
    _emit(FileTransferCompletedEvent(
      address: inc.address,
      transferId: transferId,
      fileName: inc.fileName,
      success: false,
      error: 'rejected',
      outgoing: false,
    ));
  }

  /// Cancel an outgoing or incoming transfer.
  Future<void> cancelTransfer(String transferId) async {
    final out = _outgoing[transferId];
    if (out != null) {
      out.cancelled = true;
      await _send(out.address, PacketType.fileCancel,
          Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))));
      await _failOutgoing(transferId, 'cancelled');
      return;
    }
    final inc = _incoming[transferId];
    if (inc != null) {
      await _send(inc.address, PacketType.fileCancel,
          Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))));
      if (inc.dbRowId != null) {
        await _transferDao.updateStatus(
            inc.dbRowId!, TransferStatus.cancelled);
      }
      await _cleanupIncoming(inc);
      _incoming.remove(transferId);
    }
  }

  /// Pause an outgoing transfer (stops pumping new chunks).
  Future<void> pauseTransfer(String transferId) async {
    final out = _outgoing[transferId];
    if (out != null) {
      out.paused = true;
      if (out.dbRowId != null) {
        await _transferDao.updateStatus(
            out.dbRowId!, TransferStatus.paused);
      }
    }
  }

  /// Resume a paused outgoing transfer.
  Future<void> resumeTransfer(String transferId) async {
    final out = _outgoing[transferId];
    if (out != null && out.paused && !out.cancelled) {
      out.paused = false;
      if (out.dbRowId != null) {
        await _transferDao.updateStatus(
            out.dbRowId!, TransferStatus.transferring);
      }
      _startTicker();
      await _pump(out);
    }
  }

  /// Called by the Bluetooth service when a connection drops.
  Future<void> onConnectionLost(String address) async {
    final outIds = _outgoing.values
        .where((o) => o.address == address)
        .map((o) => o.transferId)
        .toList();
    for (final id in outIds) {
      await _failOutgoing(id, 'Connection lost');
    }
    final incIds = _incoming.values
        .where((i) => i.address == address)
        .map((i) => i.transferId)
        .toList();
    for (final id in incIds) {
      final inc = _incoming.remove(id);
      if (inc != null) {
        if (inc.dbRowId != null) {
          await _transferDao.updateStatus(
              inc.dbRowId!, TransferStatus.paused);
        }
        await _cleanupIncoming(inc);
      }
    }
  }

  // ==================== OUTGOING PACKET HANDLERS ====================

  Future<void> _onFileResponse(Uint8List payload) async {
    final map = _decodeJson(payload);
    if (map == null) return;
    final transferId = map['transferId'] as String?;
    if (transferId == null) return;
    final accepted = map['accepted'] as bool? ?? false;
    final out = _outgoing[transferId];
    if (out == null) return;

    if (!accepted) {
      await _failOutgoing(transferId, 'rejected by recipient');
      return;
    }

    if (out.dbRowId != null) {
      await _transferDao.updateStatus(
          out.dbRowId!, TransferStatus.transferring);
    }
    await _pump(out);
  }

  Future<void> _onFileChunkAck(Uint8List payload) async {
    final parsed = _parseIdAndIndex(payload);
    if (parsed == null) return;
    final (transferId, index) = parsed;
    final out = _outgoing[transferId];
    if (out == null) return;

    final inflight = out.inflight.remove(index);
    if (inflight == null) return; // stale/duplicate ack

    out.acked.add(index);
    out.bytesSent += inflight.length;
    out.lastAckAt = DateTime.now();

    if (out.dbRowId != null) {
      await _updateProgress(out);
    }
    _emitProgress(out);

    if (out.acked.length == out.totalChunks) {
      await _send(out.address, PacketType.fileComplete,
          Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))));
      await _completeOutgoing(out);
      return;
    }

    await _pump(out);
  }

  // ==================== INCOMING PACKET HANDLERS ====================

  Future<void> _onFileRequest(String address, Uint8List payload) async {
    final map = _decodeJson(payload);
    if (map == null) return;
    final transferId = map['transferId'] as String?;
    final fileName = map['fileName'] as String?;
    final fileSize = (map['fileSize'] as num?)?.toInt();
    final chunkSize = (map['chunkSize'] as num?)?.toInt();
    final totalChunks = (map['totalChunks'] as num?)?.toInt();
    final mimeType = map['mimeType'] as String? ?? 'application/octet-stream';

    if (transferId == null || fileName == null || fileSize == null) return;
    if (_incoming.containsKey(transferId)) return; // duplicate request

    final transfer = await _transferDao.insert(FileTransfer(
      transferId: transferId,
      deviceId: address,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      direction: 1,
      status: TransferStatus.pending,
      totalChunks: totalChunks ?? 0,
      startedAt: DateTime.now(),
    ));

    _incoming[transferId] = _Incoming(
      transferId: transferId,
      address: address,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      chunkSize: chunkSize ?? _chunkSize,
      totalChunks: totalChunks ?? 0,
      dbRowId: transfer.id,
    );

    _emit(FileTransferRequestEvent(
      address: address,
      transferId: transferId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
    ));
  }

  Future<void> _onFileChunk(String address, Uint8List payload) async {
    final parsed = _parseChunk(payload);
    if (parsed == null) return;
    final (transferId, index, hash, data) = parsed;
    final inc = _incoming[transferId];
    if (inc == null || !inc.accepted) return;

    // Verify this chunk's integrity before writing it.
    if (index < 0 || index >= inc.totalChunks) return;
    if (inc.received.contains(index)) {
      // Already have it - re-ack so the sender moves on.
      await _sendChunkAck(inc, index);
      return;
    }
    if (_sha256Hex(data) != hash) {
      AppLogger.warn('Chunk $index checksum mismatch, awaiting retransmit', 'Transfer');
      return; // don't ack - the sender will time out and resend
    }

    final raf = inc.raf;
    if (raf == null) return;
    await raf.setPosition(index * inc.chunkSize);
    await raf.writeFrom(data);

    inc.received.add(index);
    inc.bytesReceived += data.length;
    await _sendChunkAck(inc, index);

    if (inc.dbRowId != null) {
      await _updateIncomingProgress(inc);
    }
    _emitIncomingProgress(inc);

    if (inc.received.length == inc.totalChunks) {
      await _finalizeIncoming(inc);
    }
  }

  Future<void> _onFileComplete(Uint8List payload) async {
    final map = _decodeJson(payload);
    if (map == null) return;
    final transferId = map['transferId'] as String?;
    final inc = _incoming[transferId];
    if (inc == null) return;
    if (inc.received.length == inc.totalChunks) {
      await _finalizeIncoming(inc);
    }
  }

  Future<void> _onFileCancel(Uint8List payload) async {
    final map = _decodeJson(payload);
    if (map == null) return;
    final transferId = map['transferId'] as String?;
    if (transferId == null) return;
    final out = _outgoing[transferId];
    if (out != null) {
      out.cancelled = true;
      await _failOutgoing(transferId, 'cancelled by recipient');
      return;
    }
    final inc = _incoming[transferId];
    if (inc != null) {
      if (inc.dbRowId != null) {
        await _transferDao.updateStatus(
            inc.dbRowId!, TransferStatus.cancelled);
      }
      await _cleanupIncoming(inc);
      _incoming.remove(transferId);
      _emit(FileTransferCompletedEvent(
        address: inc.address,
        transferId: transferId,
        fileName: inc.fileName,
        success: false,
        error: 'cancelled by sender',
        outgoing: false,
      ));
    }
  }

  // ==================== SEND PIPELINE ====================

  Future<void> _pump(_Outgoing out) async {
    if (out.cancelled || out.paused || out.done) return;
    while (out.inflight.length < _windowSize &&
        out.nextChunk < out.totalChunks) {
      final index = out.nextChunk;
      final data = await _readChunk(out, index);
      if (data == null) {
        await _failOutgoing(out.transferId, 'failed to read file');
        return;
      }
      final hash = _sha256Hex(data);
      final ok = await _send(out.address, PacketType.fileChunk,
          _buildChunkPayload(out.transferId, index, data, hash));
      if (!ok) {
        await _failOutgoing(out.transferId, 'send failed');
        return;
      }
      out.inflight[index] = _InflightChunk(index, data.length, DateTime.now(), 0);
      out.nextChunk++;
    }
  }

  Future<Uint8List?> _readChunk(_Outgoing out, int index) async {
    try {
      await out.raf!.setPosition(index * out.chunkSize);
      final data = await out.raf!.read(out.chunkSize);
      if (data.isEmpty) return null;
      return data;
    } catch (e) {
      AppLogger.error('Failed to read chunk $index', 'Transfer', e);
      return null;
    }
  }

  void _startTicker() {
    if (_outgoing.isEmpty) return;
    _tickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    final idle = <String>[];
    for (final out in _outgoing.values) {
      if (out.cancelled || out.done) {
        idle.add(out.transferId);
        continue;
      }
      if (out.paused) continue;

      // Speed estimate: bytes since last tick.
      final inst = out.bytesSent - out.lastSpeedBytes;
      out.lastSpeedBytes = out.bytesSent;
      out.speedBps = inst.toDouble();

      // Retransmit timed-out chunks.
      final timedOut = out.inflight.values
          .where((c) => now.difference(c.sentAt).inMilliseconds >
              AppConstants.fileChunkAckTimeoutMs)
          .toList();
      for (final c in timedOut) {
        if (c.retries >= AppConstants.fileChunkMaxRetries) {
          await _failOutgoing(out.transferId, 'chunk ${c.index} failed');
          idle.add(out.transferId);
          continue;
        }
        c.retries++;
        c.sentAt = now;
        final data = await _readChunk(out, c.index);
        if (data == null) {
          await _failOutgoing(out.transferId, 'failed to read file');
          idle.add(out.transferId);
          continue;
        }
        await _send(out.address, PacketType.fileChunk,
            _buildChunkPayload(out.transferId, c.index, data, _sha256Hex(data)));
      }

      if (out.dbRowId != null) {
        await _updateProgress(out, force: true);
      }
    }
    for (final id in idle) {
      _outgoing.remove(id);
    }
    if (_outgoing.isEmpty) {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  // ==================== COMPLETION / FAILURE ====================

  Future<void> _completeOutgoing(_Outgoing out) async {
    out.done = true;
    try {
      await out.raf?.close();
    } catch (_) {}
    if (out.dbRowId != null) {
      await _transferDao.completeTransfer(out.dbRowId!);
    }
    if (out.messageRowId != null) {
      await _messageDao.updateStatus(
          out.messageRowId!, MessageStatus.delivered);
    }
    await _deviceDao.recordInteraction(
      address: out.address,
      transferredFile: true,
      bytesTransferred: out.fileSize,
    );
    _emit(FileTransferCompletedEvent(
      address: out.address,
      transferId: out.transferId,
      fileName: out.fileName,
      success: true,
      outgoing: true,
    ));
    AppLogger.transfer('File sent: ${out.fileName}');
  }

  Future<void> _failOutgoing(String transferId, String reason) async {
    final out = _outgoing.remove(transferId);
    if (out == null) return;
    out.cancelled = true;
    try {
      await out.raf?.close();
    } catch (_) {}
    if (out.dbRowId != null) {
      await _transferDao.failTransfer(out.dbRowId!, reason);
    }
    if (out.messageRowId != null) {
      await _messageDao.updateStatus(
          out.messageRowId!, MessageStatus.failed);
    }
    _emit(FileTransferCompletedEvent(
      address: out.address,
      transferId: transferId,
      fileName: out.fileName,
      success: false,
      error: reason,
      outgoing: true,
    ));
    AppLogger.warn('File transfer failed: ${out.fileName} ($reason)', 'Transfer');
  }

  Future<void> _finalizeIncoming(_Incoming inc) async {
    if (inc.finalized) return;
    inc.finalized = true;
    try {
      final raf = inc.raf;
      if (raf != null) {
        await raf.truncate(inc.fileSize);
        await raf.close();
      }

      final finalPath = await _moveToReceived(inc);
      inc.filePath = finalPath;

      if (inc.dbRowId != null) {
        await _transferDao.updateProgress(
          transferId: inc.dbRowId!,
          bytesTransferred: inc.fileSize,
          lastChunkIndex: inc.totalChunks - 1,
          receivedChunks: inc.received,
        );
        await _transferDao.completeTransfer(inc.dbRowId!);
      }

      await _messageDao.insert(Message(
        messageId: 'file-${inc.transferId}',
        deviceId: inc.address,
        messageType: MessageType.file,
        fileName: inc.fileName,
        fileSize: inc.fileSize,
        filePath: finalPath,
        mimeType: inc.mimeType,
        status: MessageStatus.delivered,
        isOutgoing: false,
      ));

      await _deviceDao.recordInteraction(
        address: inc.address,
        transferredFile: true,
        bytesTransferred: inc.fileSize,
      );

      _emit(FileTransferCompletedEvent(
        address: inc.address,
        transferId: inc.transferId,
        fileName: inc.fileName,
        success: true,
        filePath: finalPath,
        outgoing: false,
      ));
      AppLogger.transfer('File received: ${inc.fileName} -> $finalPath');
    } catch (e) {
      AppLogger.error('Failed to finalize received file', 'Transfer', e);
      if (inc.dbRowId != null) {
        await _transferDao.failTransfer(inc.dbRowId!, e.toString());
      }
      _emit(FileTransferCompletedEvent(
        address: inc.address,
        transferId: inc.transferId,
        fileName: inc.fileName,
        success: false,
        error: e.toString(),
        outgoing: false,
      ));
    } finally {
      _incoming.remove(inc.transferId);
    }
  }

  Future<void> _failIncoming(String transferId, String reason) async {
    final inc = _incoming.remove(transferId);
    if (inc == null) return;
    if (inc.dbRowId != null) {
      await _transferDao.failTransfer(inc.dbRowId!, reason);
    }
    await _cleanupIncoming(inc);
    _emit(FileTransferCompletedEvent(
      address: inc.address,
      transferId: transferId,
      fileName: inc.fileName,
      success: false,
      error: reason,
      outgoing: false,
    ));
  }

  Future<void> _cleanupIncoming(_Incoming inc) async {
    try {
      await inc.raf?.close();
    } catch (_) {}
    final tempPath = inc.tempPath;
    if (tempPath != null) {
      final f = File(tempPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<String> _moveToReceived(_Incoming inc) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, AppConstants.receivedFilesDir));
    if (!await dir.exists()) await dir.create(recursive: true);

    var finalPath = p.join(dir.path, inc.fileName);
    if (await File(finalPath).exists()) {
      final base = p.basenameWithoutExtension(inc.fileName);
      final ext = p.extension(inc.fileName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      finalPath = p.join(dir.path, '${base}_$ts$ext');
    }
    await File(inc.tempPath!).rename(finalPath);
    return finalPath;
  }

  Future<String> _tempDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, AppConstants.tempTransfersDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ==================== PROGRESS ====================

  void _emitProgress(_Outgoing out) {
    _emit(FileTransferProgressEvent(
      address: out.address,
      transferId: out.transferId,
      fileName: out.fileName,
      bytesTransferred: out.bytesSent,
      totalBytes: out.fileSize,
      speedBps: out.speedBps,
      outgoing: true,
    ));
  }

  void _emitIncomingProgress(_Incoming inc) {
    _emit(FileTransferProgressEvent(
      address: inc.address,
      transferId: inc.transferId,
      fileName: inc.fileName,
      bytesTransferred: inc.bytesReceived,
      totalBytes: inc.fileSize,
      speedBps: 0,
      outgoing: false,
    ));
  }

  Future<void> _updateProgress(_Outgoing out, {bool force = false}) async {
    if (!force && _withinThrottle(out.lastProgressAt)) return;
    out.lastProgressAt = DateTime.now();
    await _transferDao.updateProgress(
      transferId: out.dbRowId!,
      bytesTransferred: out.bytesSent,
      lastChunkIndex: out.nextChunk - 1,
      currentSpeed: out.speedBps.toInt(),
    );
  }

  Future<void> _updateIncomingProgress(_Incoming inc) async {
    if (_withinThrottle(inc.lastProgressAt)) return;
    inc.lastProgressAt = DateTime.now();
    await _transferDao.updateProgress(
      transferId: inc.dbRowId!,
      bytesTransferred: inc.bytesReceived,
      lastChunkIndex: inc.received.isEmpty ? -1 : inc.received.reduce((a, b) => a > b ? a : b),
      receivedChunks: inc.received,
    );
  }

  bool _withinThrottle(DateTime? last) {
    if (last == null) return false;
    return DateTime.now().difference(last).inMilliseconds < 500;
  }

  Future<void> _sendChunkAck(_Incoming inc, int index) async {
    await _send(inc.address, PacketType.fileChunkAck,
        _buildIdAndIndex(inc.transferId, index));
  }

  // ==================== PAYLOAD ENCODING ====================

  Uint8List _buildChunkPayload(
      String transferId, int index, Uint8List data, String hash) {
    final idBytes = utf8.encode(transferId);
    final builder = BytesBuilder();
    builder.addByte(idBytes.length);
    builder.add(idBytes);
    builder.add(_int4(index));
    builder.add(utf8.encode(hash));
    builder.add(data);
    return builder.toBytes();
  }

  Uint8List _buildIdAndIndex(String transferId, int index) {
    final idBytes = utf8.encode(transferId);
    final builder = BytesBuilder();
    builder.addByte(idBytes.length);
    builder.add(idBytes);
    builder.add(_int4(index));
    return builder.toBytes();
  }

  /// Parse a `fileChunkAck` payload: (transferId, chunkIndex).
  (String, int)? _parseIdAndIndex(Uint8List payload) {
    try {
      if (payload.length < 6) return null;
      final idLen = payload[0];
      if (payload.length < 1 + idLen + 4) return null;
      final id = utf8.decode(payload.sublist(1, 1 + idLen));
      final off = 1 + idLen;
      final index = _readInt4(payload, off);
      return (id, index);
    } catch (_) {
      return null;
    }
  }

  /// Parse a `fileChunk` payload: (transferId, index, hash, data).
  (String, int, String, Uint8List)? _parseChunk(Uint8List payload) {
    try {
      if (payload.length < 6) return null;
      final idLen = payload[0];
      if (payload.length < 1 + idLen + 4 + 64) return null;
      final id = utf8.decode(payload.sublist(1, 1 + idLen));
      var off = 1 + idLen;
      final index = _readInt4(payload, off);
      off += 4;
      final hash = ascii.decode(payload.sublist(off, off + 64));
      off += 64;
      final data = Uint8List.fromList(payload.sublist(off));
      return (id, index, hash, data);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeJson(Uint8List payload) {
    try {
      return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Uint8List _int4(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;

  int _readInt4(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  String _sha256Hex(Uint8List data) {
    final digest = pc.Digest('SHA-256');
    final hash = digest.process(data);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// ==================== INTERNAL STATE ====================

class _Outgoing {
  final String transferId;
  final String address;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final int totalChunks;
  final int chunkSize;
  RandomAccessFile? raf;
  int? dbRowId;
  int? messageRowId;

  final Set<int> acked = {};
  final Map<int, _InflightChunk> inflight = {};
  int nextChunk = 0;
  int bytesSent = 0;
  int lastSpeedBytes = 0;
  double speedBps = 0;
  DateTime? lastAckAt;
  DateTime? lastProgressAt;
  bool cancelled = false;
  bool paused = false;
  bool done = false;

  _Outgoing({
    required this.transferId,
    required this.address,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.totalChunks,
    required this.chunkSize,
    this.raf,
    this.dbRowId,
    this.messageRowId,
  });
}

class _InflightChunk {
  final int index;
  final int length;
  DateTime sentAt;
  int retries;

  _InflightChunk(this.index, this.length, this.sentAt, this.retries);
}

class _Incoming {
  final String transferId;
  final String address;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final int chunkSize;
  final int totalChunks;
  RandomAccessFile? raf;
  String? tempPath;
  String? filePath;
  int? dbRowId;

  final Set<int> received = {};
  int bytesReceived = 0;
  DateTime? lastProgressAt;
  bool accepted = false;
  bool finalized = false;

  _Incoming({
    required this.transferId,
    required this.address,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.chunkSize,
    required this.totalChunks,
    this.dbRowId,
  });
}
