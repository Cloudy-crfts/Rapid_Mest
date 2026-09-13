import 'dart:typed_data';

import '../../utils/constants.dart';

/// A single complete packet extracted from the RFCOMM byte stream.
class Frame {
  final int type;
  final Uint8List payload;

  const Frame(this.type, this.payload);
}

/// Stream framing for the Rapid Mesh RFCOMM transport.
///
/// RFCOMM is a raw byte stream: it does not preserve message boundaries.
/// Without framing, two packets sent back-to-back could be merged into one
/// read, and a single packet could be split across several reads. That is why
/// every packet sent over the native socket is wrapped in a frame:
///
///   ┌──────────────┬──────┬─────────────────┐
///   │ length (4B)  │ type │ payload         │
///   │ big-endian   │ (1B) │ (variable)      │
///   └──────────────┴──────┴─────────────────┘
///
/// `length` is the byte count of everything that follows it (type + payload).
class Framing {
  Framing._();

  /// Wrap [type] + [payload] into a single length-prefixed frame.
  static Uint8List buildFrame(int type, List<int> payload) {
    final total = 1 + payload.length;
    final bytes = Uint8List(4 + total);
    bytes[0] = (total >> 24) & 0xFF;
    bytes[1] = (total >> 16) & 0xFF;
    bytes[2] = (total >> 8) & 0xFF;
    bytes[3] = total & 0xFF;
    bytes[4] = type & 0xFF;
    bytes.setRange(5, 5 + payload.length, payload);
    return bytes;
  }
}

/// Accumulates raw RFCOMM bytes and yields complete [Frame]s.
class FrameAssembler {
  final List<int> _buffer = <int>[];
  final List<Frame> _ready = <Frame>[];

  /// Feed raw bytes received from the socket.
  void add(List<int> data) {
    if (data.isEmpty) return;
    _buffer.addAll(data);
    _extract();
  }

  /// Remove and return all complete frames currently available.
  List<Frame> drain() {
    if (_ready.isEmpty) return const [];
    final out = List<Frame>.from(_ready);
    _ready.clear();
    return out;
  }

  void _extract() {
    while (_buffer.length >= 4) {
      final total = (_buffer[0] << 24) |
          (_buffer[1] << 16) |
          (_buffer[2] << 8) |
          _buffer[3];
      if (total < 1 || total > AppConstants.maxFrameSizeBytes) {
        // Corrupt stream: discard everything and resynchronize on the next
        // plausible frame boundary (the native layer reports errors anyway).
        _buffer.clear();
        return;
      }
      if (_buffer.length < 4 + total) return;
      final type = _buffer[4];
      final payload = Uint8List.fromList(_buffer.sublist(5, 4 + total));
      _buffer.removeRange(0, 4 + total);
      _ready.add(Frame(type, payload));
    }
  }

  /// Drop any partially received data (used when a connection is closed).
  void reset() {
    _buffer.clear();
    _ready.clear();
  }
}
