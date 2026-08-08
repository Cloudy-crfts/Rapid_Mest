import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/logger.dart';

/// File Storage Service
/// 
/// Manages all file operations within the app's sandboxed storage.
/// All files are stored in app-specific directories - no external storage access needed.
/// 
/// Directory Structure:
/// /data/data/com.rapidmesh.app/
/// ├── files/
/// │   ├── received_files/     # Files received from others
/// │   ├── sent_files/         # Cache of sent files
/// │   ├── voice_messages/     # Voice recordings
/// │   ├── images/             # Shared images
/// │   └── temp_transfers/     # In-progress downloads
/// └── cache/
///     └── thumbnails/         # Generated thumbnails

class FileStorageService {
  static final FileStorageService _instance = FileStorageService._internal();
  
  // Singleton instance
  static FileStorageService get instance => _instance;

  // Base directories
  String? _appFilesDir;
  String? _appCacheDir;

  // Sub-directory paths
  late String _receivedFilesDir;
  late String _sentFilesDir;
  late String _voiceMessagesDir;
  late String _imagesDir;
  late String _tempTransfersDir;
  late String _thumbnailsDir;

  // Private constructor
  FileStorageService._internal();

  /// Initialize storage directories
  Future<bool> initialize() async {
    try {
      AppLogger.info('Initializing File Storage Service', 'Storage');
      
      // Get base directories
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = await getTemporaryDirectory();
      
      _appFilesDir = appDir.path;
      _appCacheDir = cacheDir.path;
      
      // Set up sub-directories
      _receivedFilesDir = path.join(_appFilesDir!, AppConstants.receivedFilesDir);
      _sentFilesDir = path.join(_appFilesDir!, AppConstants.sentFilesDir);
      _voiceMessagesDir = path.join(_appFilesDir!, AppConstants.voiceMessagesDir);
      _imagesDir = path.join(_appFilesDir!, AppConstants.imagesDir);
      _tempTransfersDir = path.join(_appFilesDir!, AppConstants.tempTransfersDir);
      _thumbnailsDir = path.join(_appCacheDir!, AppConstants.thumbnailsDir);
      
      // Create all directories
      await _ensureDirectoryExists(_receivedFilesDir);
      await _ensureDirectoryExists(_sentFilesDir);
      await _ensureDirectoryExists(_voiceMessagesDir);
      await _ensureDirectoryExists(_imagesDir);
      await _ensureDirectoryExists(_tempTransfersDir);
      await _ensureDirectoryExists(_thumbnailsDir);
      
      AppLogger.info('File Storage initialized', 'Storage');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to initialize File Storage', 'Storage', e, stackTrace);
      return false;
    }
  }

  // ==================== DIRECTORY MANAGEMENT ====================

  /// Ensure a directory exists, create if not
  Future<void> _ensureDirectoryExists(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      AppLogger.debug('Created directory: $dirPath', 'Storage');
    }
  }

  /// Get directory path by type
  String getDirectoryPath(StorageType type) {
    switch (type) {
      case StorageType.received:
        return _receivedFilesDir;
      case StorageType.sent:
        return _sentFilesDir;
      case StorageType.voice:
        return _voiceMessagesDir;
      case StorageType.image:
        return _imagesDir;
      case StorageType.temp:
        return _tempTransfersDir;
      case StorageType.thumbnail:
        return _thumbnailsDir;
    }
  }

  // ==================== FILE OPERATIONS ====================

  /// Save received file to appropriate directory
  /// 
  /// Returns the full path of saved file
  Future<String?> saveReceivedFile({
    required Uint8List fileData,
    required String fileName,
    String? customName,
  }) async {
    try {
      final outputName = customName ?? Helpers.generateUniqueFilename(fileName);
      final outputPath = path.join(_receivedFilesDir, outputName);
      
      final file = File(outputPath);
      await file.writeAsBytes(fileData);
      
      AppLogger.info('Saved received file: $outputPath', 'Storage');
      return outputPath;
    } catch (e) {
      AppLogger.error('Failed to save received file', 'Storage', e);
      return null;
    }
  }

  /// Save file to sent files cache
  Future<String?> cacheSentFile({
    required Uint8List fileData,
    required String fileName,
  }) async {
    try {
      final outputName = Helpers.generateUniqueFilename(fileName);
      final outputPath = path.join(_sentFilesDir, outputName);
      
      final file = File(outputPath);
      await file.writeAsBytes(fileData);
      
      return outputPath;
    } catch (e) {
      AppLogger.error('Failed to cache sent file', 'Storage', e);
      return null;
    }
  }

  /// Save voice message
  Future<String?> saveVoiceMessage({
    required Uint8List audioData,
    required String extension, // e.g., 'ogg', 'opus'
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_$timestamp.$extension';
      final outputPath = path.join(_voiceMessagesDir, fileName);
      
      final file = File(outputPath);
      await file.writeAsBytes(audioData);
      
      return outputPath;
    } catch (e) {
      AppLogger.error('Failed to save voice message', 'Storage', e);
      return null;
    }
  }

  /// Save image
  Future<String?> saveImage({
    required Uint8List imageData,
    required String originalName,
  }) async {
    try {
      final outputName = Helpers.generateUniqueFilename(originalName);
      final outputPath = path.join(_imagesDir, outputName);
      
      final file = File(outputPath);
      await file.writeAsBytes(imageData);
      
      return outputPath;
    } catch (e) {
      AppLogger.error('Failed to save image', 'Storage', e);
      return null;
    }
  }

  /// Save thumbnail for media files
  Future<String?> saveThumbnail({
    required Uint8List thumbnailData,
    String sourceFileName,
  }) async {
    try {
      final baseName = path.basenameWithoutExtension(sourceFileName);
      final outputPath = path.join(_thumbnailsDir, '${baseName}_thumb.jpg');
      
      final file = File(outputPath);
      await file.writeAsBytes(thumbnailData);
      
      return outputPath;
    } catch (e) {
      AppLogger.error('Failed to save thumbnail', 'Storage', e);
      return null;
    }
  }

  /// Save partial/temporary transfer data
  Future<String?> saveTempTransfer({
    required Uint8List data,
    required String transferId,
    int chunkIndex = 0,
  }) async {
    try {
      final tempDir = Directory(_tempTransfersDir);
      final transferDir = path.join(_tempTransfersDir, transferId);
      await _ensureDirectoryExists(transferDir);
      
      final chunkPath = path.join(transferDir, 'chunk_$chunkIndex.bin');
      final file = File(chunkPath);
      await file.writeAsBytes(data);
      
      return chunkPath;
    } catch (e) {
      AppLogger.error('Failed to save temp transfer', 'Storage', e);
      return null;
    }
  }

  // ==================== FILE READING ====================

  /// Read file as bytes
  Future<Uint8List?> readFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (e) {
      AppLogger.error('Failed to read file: $filePath', 'Storage', e);
      return null;
    }
  }

  /// Read file as string (for text files)
  Future<String?> readTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      AppLogger.error('Failed to read text file: $filePath', 'Storage', e);
      return null;
    }
  }

  /// Get file info
  Future<FileInfo?> getFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final stat = await file.stat();
      return FileInfo(
        path: filePath,
        name: path.basename(filePath),
        size: stat.size,
        modifiedAt: stat.modified,
        isFile: stat.type == FileSystemEntity.file,
      );
    } catch (e) {
      AppLogger.error('Failed to get file info: $filePath', 'Storage', e);
      return null;
    }
  }

  // ==================== FILE DELETION ====================

  /// Delete a file
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        AppLogger.debug('Deleted file: $filePath', 'Storage');
        return true;
      }
      return false; // File didn't exist
    } catch (e) {
      AppLogger.error('Failed to delete file: $filePath', 'Storage', e);
      return false;
    }
  }

  /// Delete all files in a directory
  Future<int> deleteFilesInDirectory(String dirPath, {bool recursive = false}) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return 0;
      
      int count = 0;
      await for (final entity in dir.list(recursive: recursive)) {
        if (entity is File) {
          await entity.delete();
          count++;
        }
      }
      
      return count;
    } catch (e) {
      AppLogger.error('Failed to clean directory: $dirPath', 'Storage', e);
      return 0;
    }
  }

  /// Clean up temporary transfer files
  Future<int> cleanupTempTransfers({String? keepTransferId}) async {
    try {
      final tempDir = Directory(_tempTransfersDir);
      if (!await tempDir.exists()) return 0;
      
      int cleaned = 0;
      await for (final entity in tempDir.list()) {
        if (entity is Directory && keepTransferId != null) {
          if (path.basename(entity.path) != keepTransferId) {
            await entity.delete(recursive: true);
            cleaned++;
          }
        } else {
          await entity.delete(recursive: true);
          cleaned++;
        }
      }
      
      return cleaned;
    } catch (e) {
      AppLogger.error('Failed to cleanup temp transfers', 'Storage', e);
      return 0;
    }
  }

  // ==================== FILE OPERATIONS ====================

  /// Copy file within app storage
  Future<String?> copyFile(String sourcePath, String destinationDir, {String? newName}) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      
      final outputName = newName ?? path.basename(sourcePath);
      final destPath = path.join(destinationDir, outputName);
      
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      AppLogger.error('Failed to copy file', 'Storage', e);
      return null;
    }
  }

  /// Move file within app storage
  Future<String?> moveFile(String sourcePath, String destinationDir, {String? newName}) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      
      final outputName = newName ?? path.basename(sourcePath);
      final destPath = path.join(destinationDir, outputName);
      
      await source.rename(destPath);
      return destPath;
    } catch (e) {
      // If rename fails (cross-device), try copy+delete
      final copied = await copyFile(sourcePath, destinationDir, newName: newName);
      if (copied != null) {
        await deleteFile(sourcePath);
        return copied;
      }
      return null;
    }
  }

  /// Check if file exists
  Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  /// Generate unique filename in a directory
  String generateUniquePath(String directory, String filename) {
    final ext = path.extension(filename);
    final baseName = path.basenameWithoutExtension(filename);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return path.join(directory, '${baseName}_$timestamp$ext');
  }

  // ==================== STORAGE QUERIES ====================

  /// List files in a directory
  Future<List<FileInfo>> listFiles(String dirPath, {String? extensionFilter}) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];
      
      final files = <FileInfo>[];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          if (extensionFilter == null || path.extension(entity.path) == extensionFilter) {
            final stat = await entity.stat();
            files.add(FileInfo(
              path: entity.path,
              name: path.basename(entity.path),
              size: stat.size,
              modifiedAt: stat.modified,
              isFile: true,
            ));
          }
        }
      }
      
      // Sort by modified date (newest first)
      files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      return files;
    } catch (e) {
      AppLogger.error('Failed to list files in: $dirPath', 'Storage', e);
      return [];
    }
  }

  /// Calculate total size of a directory
  Future<long> getDirectorySize(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return 0;
      
      long totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      AppLogger.error('Failed to calculate directory size: $dirPath', 'Storage', e);
      return 0;
    }
  }

  /// Get total app storage usage
  Future<StorageUsage> getTotalAppUsage() async {
    long receivedSize = await getDirectorySize(_receivedFilesDir);
    long sentSize = await getDirectorySize(_sentFilesDir);
    long voiceSize = await getDirectorySize(_voiceMessagesDir);
    long imageSize = await getDirectorySize(_imagesDir);
    long tempSize = await getDirectorySize(_tempTransfersDir);
    
    return StorageUsage(
      receivedFiles: receivedSize,
      sentFiles: sentSize,
      voiceMessages: voiceSize,
      images: imageSize,
      tempTransfers: tempSize,
      total: receivedSize + sentSize + voiceSize + imageSize + tempSize,
    );
  }

  /// Get list of all stored files with details
  Future<List<FileInfo>> getAllStoredFiles() async {
    final allFiles = <FileInfo>[];
    
    allFiles.addAll(await listFiles(_receivedFilesDir));
    allFiles.addAll(await listFiles(_sentFilesDir));
    allFiles.addAll(await listFiles(_voiceMessagesDir));
    allFiles.addAll(await listFiles(_imagesDir));
    
    return allFiles;
  }
}

// ==================== SUPPORTING TYPES ====================

/// Storage type enumeration
enum StorageType {
  received,
  sent,
  voice,
  image,
  temp,
  thumbnail,
}

/// File information model
class FileInfo {
  final String path;
  final String name;
  final long size;
  final DateTime modifiedAt;
  final bool isFile;

  FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.isFile,
  });

  /// Get formatted file size
  String get formattedSize => Helpers.formatFileSize(size);

  /// Get relative time since modification
  String get relativeTime => Helpers.getRelativeTime(modifiedAt);

  /// Get file extension
  String get extension => path.extension(name).toLowerCase();

  /// Check if this is an image file
  bool get isImage => Helpers.isImageFile(name);

  /// Check if this is a video file
  bool get isVideo => Helpers.isVideoFile(name);

  /// Check if this is an audio file
  bool get isAudio => Helpers.isAudioFile(name);
}

/// Storage usage statistics
class StorageUsage {
  final long receivedFiles;
  final long sentFiles;
  final long voiceMessages;
  final long images;
  final long tempTransfers;
  final long total;

  StorageUsage({
    required this.receivedFiles,
    required this.sentFiles,
    required this.voiceMessages,
    required this.images,
    required this.tempTransfers,
    required this.total,
  });

  /// Get formatted usage strings
  Map<String, String> get formatted {
    return {
      'received': Helpers.formatFileSize(receivedFiles),
      'sent': Helpers.formatFileSize(sentFiles),
      'voice': Helpers.formatFileSize(voiceMessages),
      'images': Helpers.formatFileSize(images),
      'temp': Helpers.formatFileSize(tempTransfers),
      'total': Helpers.formatFileSize(total),
    };
  }
}
