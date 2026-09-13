/// Connection events pushed onto `BluetoothService.events`.
///
/// These are plain data classes so UI screens can react to real connection
/// state changes (incoming requests, accepted/rejected requests, connection
/// loss, incoming messages, delivery acks, and file transfer progress).
library;

sealed class ConnectionEvent {
  /// Bluetooth address of the device this event concerns.
  String get address;

  const ConnectionEvent();
}

/// Another phone is asking to connect to us.
class IncomingRequestEvent extends ConnectionEvent {
  @override
  final String address;
  final String name;
  const IncomingRequestEvent({required this.address, required this.name});
}

/// A connection (either direction) is fully established and ready for chat.
class ConnectionEstablishedEvent extends ConnectionEvent {
  @override
  final String address;
  final String name;
  const ConnectionEstablishedEvent({required this.address, required this.name});
}

/// Our outgoing connection request was declined (or could not reach the device).
class ConnectionRequestRejectedEvent extends ConnectionEvent {
  @override
  final String address;
  const ConnectionRequestRejectedEvent({required this.address});
}

/// An established connection was lost.
class ConnectionLostEvent extends ConnectionEvent {
  @override
  final String address;
  const ConnectionLostEvent({required this.address});
}

/// A text message arrived from a connected device.
class TextMessageReceivedEvent extends ConnectionEvent {
  @override
  final String address;
  final String messageId;
  final String text;
  final DateTime sentAt;
  const TextMessageReceivedEvent({
    required this.address,
    required this.messageId,
    required this.text,
    required this.sentAt,
  });
}

/// The remote device confirmed receipt of one of our messages.
class TextMessageAckEvent extends ConnectionEvent {
  @override
  final String address;
  final String messageId;
  const TextMessageAckEvent({required this.address, required this.messageId});
}

/// A remote device wants to send us a file.
class FileTransferRequestEvent extends ConnectionEvent {
  @override
  final String address;
  final String transferId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  const FileTransferRequestEvent({
    required this.address,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

/// Progress update for an in-flight file transfer.
class FileTransferProgressEvent extends ConnectionEvent {
  @override
  final String address;
  final String transferId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBps;
  final bool outgoing;
  const FileTransferProgressEvent({
    required this.address,
    required this.transferId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBps,
    required this.outgoing,
  });
}

/// A file transfer finished (successfully or not).
class FileTransferCompletedEvent extends ConnectionEvent {
  @override
  final String address;
  final String transferId;
  final String fileName;
  final bool success;
  final String? filePath;
  final String? error;
  final bool outgoing;
  const FileTransferCompletedEvent({
    required this.address,
    required this.transferId,
    required this.fileName,
    required this.success,
    this.filePath,
    this.error,
    required this.outgoing,
  });
}
