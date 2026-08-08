import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/pointycastle.dart' as pc;
import '../utils/constants.dart';
import '../../utils/helpers.dart';

/// Chunk Manager
/// 
/// Handles splitting files into chunks for transfer and reassembling
/// received chunks back into complete files.
/// 
/// Features:
/// - Configurable chunk size (based on MTU)
/// - Progress tracking
/// - Checksum verification per chunk and whole file
/// - Resume support (track which chunks are complete)
/// - Temporary file management

class ChunkManager {
  // Configuration
  final int chunkSize;

  // Constructor
  ChunkManager({this.chunkSize = AppConstants.defaultChunkSizeBytes});

  // ==================== SENDING: FILE SPLITTING ====================

  /// Split a file into chunks for transmission
  /// 
  /// Returns list of [chunkIndex, chunkData] pairs
  /// Also calculates total checksum of original file
  Future<ChunkedFile> splitFile(String filePath) async {
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }
    
    final fileSize = await file.length();
    final fileName = path.basename(filePath);
    
    if (fileSize == 0) {
      throw Exception('File is empty: $filePath');
    }
    
    AppLogger.transfer('Splitting file: $fileName (${Helpers.formatFileSize(fileSize)})');
    
    // Calculate total number of chunks
    final totalChunks = (fileSize / chunkSize).ceil();
    
    // Read entire file
    final fileBytes = await file.readAsBytes();
    
    // Calculate full file checksum
    final checksum = await _calculateSha256(fileBytes);
    
    // Split into chunks
    final chunks = <FileChunk>[];
    int offset = 0;
    int chunkIndex = 0;
    
    while (offset < fileSize) {
      int end = offset + chunkSize;
      if (end > fileSize) end = fileSize;
      
      final chunkData = fileBytes.sublist(offset, end);
      
      chunks.add(FileChunk(
        index: chunkIndex,
        data: chunkData,
        checksum: await _calculateSha256(chunkData),
        isLastChunk: end >= fileSize,
      ));
      
      offset = end;
      chunkIndex++;
    }
    
    AppLogger.transfer('File split into $chunks.length chunks');
    
    return ChunkedFile(
      fileName: fileName,
      filePath: filePath,
      fileSize: fileSize,
      totalChunks: totalChunks,
      chunks: chunks,
      checksum: checksum,
    );
  }

  /// Get specific chunk by index from a chunked file
  FileChunk? getChunk(ChunkedFile chunkedFile, int index) {
    if (index < 0 || index >= chunkedFile.chunks.length) return null;
    return chunkedFile.chunks[index];
  }

  // ==================== RECEIVING: FILE REASSEMBLY ====================

  /// Initialize receiver for incoming file transfer
  FileReceiver createReceiver({
    required String fileName,
    required int fileSize,
    required int totalChunks,
    required String expectedChecksum,
    String? destinationDir,
  }) {
    return FileReceiver(
      fileName: fileName,
      fileSize: fileSize,
      totalChunks: totalChunks,
      expectedChecksum: expectedChecksum,
      destinationDir: destinationDir,
    );
  }

  /// Resume existing receiver from saved state
  FileReceiver? resumeReceiver(Map<String, dynamic> savedState) {
    try {
      return FileReceiver.fromMap(savedState);
    } catch (e) {
      AppLogger.error('Failed to resume receiver', 'ChunkManager', e);
      return null;
    }
  }
}

/// Represents a single file chunk
class FileChunk {
  final int index;           // Zero-based chunk index
  final Uint8List data;     // Chunk data
  final String checksum;     // SHA-256 of this chunk
  final bool isLastChunk;    // Is this the last chunk?

  FileChunk({
    required this.index,
    required this.data,
    required this.checksum,
    this.isLastChunk = false,
  });

  /// Verify chunk integrity
  Future<bool> verify() async {
    final calculated = await _calculateSha256(data);
    return calculated == checksum;
  }

  /// Get chunk size in bytes
  int get size => data.length;
}

/// Represents a fully chunked file ready for sending
class ChunkedFile {
  final String fileName;
  final String filePath;
  final int fileSize;
  final int totalChunks;
  final List<FileChunk> chunks;
  final String checksum;       // SHA-256 of complete file

  ChunkedFile({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.totalChunks,
    required this.chunks,
    required this.checksum,
  });

  /// Get progress as percentage (chunks sent / total)
  double getProgress(Set<int> sentChunks) {
    if (totalChunks == 0) return 100.0;
    return (sentChunks.length / totalChunks * 100).clamp(0.0, 100.0);
  }

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'filePath': filePath,
      'fileSize': fileSize,
      'totalChunks': totalChunks,
      'checksum': checksum,
    };
  }
}

/// Handles receiving and reassembling file chunks
class FileReceiver {
  final String fileName;
  final int fileSize;
  final int totalChunks;
  final String expectedChecksum;
  final String? destinationDir;
  
  // Received chunks storage
  final Map<int, Uint8List> _receivedChunks = {};
  Set<int> get receivedIndices => _receivedChunks.keys.toSet();
  
  // State
  DateTime? startedAt;
  DateTime? completedAt;
  String? tempFilePath;
  String? finalFilePath;
  String? actualChecksum;
  
  // Callbacks
  typedef OnProgressCallback = void Function(int receivedCount, int totalChunks, int bytesReceived);
  OnProgressCallback? onProgress;
  
  typedef OnCompleteCallback = void Function(String filePath);
  OnCompleteCallback? onComplete;
  
  typedef OnErrorCallback = void Function(String error);
  OnErrorCallback? onError;

  FileReceiver({
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    required this.expectedChecksum,
    this.destinationDir,
  }) {
    startedAt = DateTime.now();
  }

  /// Create from saved state (for resume)
  factory FileReceiver.fromMap(Map<String, dynamic> map) {
    return FileReceiver(
      fileName: map['fileName'] as String,
      fileSize: (map['fileSize'] as num).toInt(),
      totalChunks: map['totalChunks'] as int,
      expectedChecksum: map['expectedChecksum'] as String,
      destinationDir: map['destinationDir'] as String?,
    );
  }

  /// Receive a single chunk
  Future<bool> receiveChunk(int chunkIndex, Uint8List chunkData, {String? chunkChecksum}) async {
    try {
      // Validate chunk index
      if (chunkIndex < 0 || chunkIndex >= totalChunks) {
        throw Exception('Invalid chunk index: $chunkIndex');
      }
      
      // Check if already received
      if (_receivedChunks.containsKey(chunkIndex)) {
        AppLogger.debug("Chunk $chunkIndex already received", "Receiver");
        return true; // Duplicate is OK, just skip
      }
      
      // Verify chunk checksum if provided
      if (chunkChecksum != null) {
        final calculated = await _calculateSha256(chunkData);
        if (calculated != chunkChecksum) {
          throw Exception('Chunk $chunkIndex checksum mismatch!');
        }
      }
      
      // Store chunk
      _receivedChunks[chunkIndex] = chunkData;
      
      // Report progress
      onProgress?.call(_receivedChunks.length, totalChunks, getReceivedBytes());
      
      AppLogger.debug("Received chunk $chunkIndex/${totalChunks - 1}", "Receiver");
      
      // Check if all chunks received
      if (_receivedChunks.length == totalChunks) {
        await assembleFile();
      }
      
      return true;
    } catch (e) {
      AppLogger.error('Error receiving chunk $chunkIndex', 'Receiver', e);
      onError?.call(e.toString());
      return false;
    }
  }

  /// Assemble all received chunks into complete file
  Future<String?> assembleFile() async {
    try {
      if (_receivedChunks.length != totalChunks) {
        throw Exception('Not all chunks received yet (${_receivedChunks.length}/$totalChunks)');
      }
      
      AppLogger.transfer('Assembling file: $fileName');
      
      // Determine output directory
      final dir = destinationDir ?? await _getDefaultDestinationDir();
      
      // Create temporary file first
      final tempDir = await _getTempDir();
      tempFilePath = path.join(tempDir, 'receiving_$fileName');
      
      // Assemble chunks in order
      final buffer = BytesBuilder();
      for (var i = 0; i < totalChunks; i++) {
        if (!_receivedChunks.containsKey(i)) {
          throw Exception('Missing chunk $i');
        }
        buffer.add(_receivedChunks[i]!);
      }
      
      final assembledData = buffer.toBytes();
      
      // Write to temp file
      final tempFile = File(tempFilePath!);
      await tempFile.writeAsBytes(assembledData);
      
      // Verify complete file checksum
      actualChecksum = await _calculateSha256(assembledData);
      
      if (actualChecksum != expectedChecksum) {
        // Delete corrupted file
        await tempFile.delete();
        throw Exception('File checksum mismatch! Expected: $expectedChecksum, Got: $actualChecksum');
      }
      
      // Move to final location
      finalFilePath = path.join(dir, fileName);
      var finalFile = File(finalFilePath);
      
      // Handle filename conflicts
      if (await finalFile.exists()) {
        final baseName = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        finalFilePath = path.join(dir, '${baseName}_$timestamp$ext');
        finalFile = File(finalFilePath);
      }
      
      await tempFile.rename(finalFilePath);
      
      completedAt = DateTime.now();
      
      AppLogger.transfer('File assembled successfully: $finalFilePath');
      
      onComplete?.call(finalFilePath!);
      return finalFilePath;
      
    } catch (e) {
      AppLogger.error('File assembly failed', 'Receiver', e);
      onError?.call(e.toString());
      return null;
    }
  }

  /// Get total bytes received so far
  int getReceivedBytes() {
    int total = 0;
    for (final chunk in _receivedChunks.values) {
      total += chunk.length;
    }
    return total;
  }

  /// Get progress percentage
  double get progress {
    if (totalChunks == 0) return 100.0;
    return (_receivedChunks.length / totalChunks * 100).clamp(0.0, 100.0);
  }

  /// Get missing chunk indices
  List<int> getMissingChunks() {
    final missing = <int>[];
    for (var i = 0; i < totalChunks; i++) {
      if (!_receivedChunks.containsKey(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  /// Check if all chunks received
  bool get isComplete => _receivedChunks.length == totalChunks;

  /// Save current state for resume capability
  Map<String, dynamic> saveState() {
    return {
      'fileName': fileName,
      'fileSize': fileSize,
      'totalChunks': totalChunks,
      'expectedChecksum': expectedChecksum,
      'destinationDir': destinationDir,
      'receivedChunkIndices': receivedIndices.toList(),
      'startedAt': startedAt?.toIso8601String(),
    };
  }

  /// Clean up temporary files
  Future<void> cleanup() async {
    if (tempFilePath != null) {
      final tempFile = File(tempFilePath!);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
    _receivedChunks.clear();
  }

  /// Get default destination directory
  Future<String> _getDefaultDestinationDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, AppConstants.receivedFilesDir);
  }

  /// Get temp directory for partial downloads
  Future<String> _getTempDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final tempDir = path.join(appDir.path, AppConstants.tempTransfersDir);
    final dir = Directory(tempDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return tempDir;
  }
}

// ==================== UTILITY FUNCTIONS ====================

/// Calculate SHA-256 hash of data
Future<String> _calculateSha256(Uint8List data) async {
  // Use PointyCastle for SHA-256
  final digest = pc.Digest('SHA-256');
  final hash = digest.process(data);
  return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// Import logger
import '../../utils/logger.dart';
