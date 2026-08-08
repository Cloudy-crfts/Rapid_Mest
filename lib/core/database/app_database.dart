import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Rapid Mesh Application Database
/// 
/// Singleton database manager using SQLite.
/// All data is stored locally on the device - no cloud, no servers.
/// 
/// Tables:
/// - devices: Saved/discovered Bluetooth devices
/// - messages: Chat messages (text, media, files)
/// - file_transfers: File transfer tracking with resumable state
/// - offline_queue: Messages queued for delivery when device reconnects
/// - app_settings: User preferences and local configuration

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  static Database? _database;

  // Private constructor
  AppDatabase._internal();

  /// Get singleton instance
  static AppDatabase get instance => _instance;

  /// Get database instance (lazy initialization)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize and open the database
  Future<Database> _initDatabase() async {
    final String dbPath = await getDatabasesPath();
    final String path = join(dbPath, 'rapid_mesh.db');

    AppLogger.info('Initializing database at: $path', 'Database');

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
      singleInstance: true,
    );
  }

  /// Create all tables on first run
  Future<void> _onCreate(Database db, int version) async {
    AppLogger.info('Creating database schema (version $version)', 'Database');

    // Create batch for atomic table creation
    final batch = db.batch();

    // ==================== DEVICES TABLE ====================
    batch.execute('''
      CREATE TABLE devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bluetooth_address TEXT NOT NULL UNIQUE,
        device_name TEXT,
        alias TEXT DEFAULT '',
        last_known_name TEXT,
        is_saved INTEGER DEFAULT 0,
        is_blocked INTEGER DEFAULT 0,
        first_seen_at TEXT,
        last_connected_at TEXT,
        last_interaction_at TEXT,
        total_messages_sent INTEGER DEFAULT 0,
        total_messages_received INTEGER DEFAULT 0,
        total_files_transferred INTEGER DEFAULT 0,
        total_bytes_transferred INTEGER DEFAULT 0,
        public_key TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    // Index for fast lookup by address
    batch.execute('CREATE INDEX idx_devices_address ON devices(bluetooth_address)');
    batch.execute('CREATE INDEX idx_devices_saved ON devices(is_saved)');

    // ==================== MESSAGES TABLE ====================
    batch.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        message_type INTEGER NOT NULL DEFAULT 0,
        content TEXT,
        file_path TEXT,
        file_name TEXT,
        file_size INTEGER,
        mime_type TEXT,
        thumbnail_path TEXT,
        checksum TEXT,
        status INTEGER NOT NULL DEFAULT 5,
        is_outgoing INTEGER NOT NULL DEFAULT 1,
        is_deleted_for_me INTEGER DEFAULT 0,
        is_deleted_for_everyone INTEGER DEFAULT 0,
        deleted_at TEXT,
        delivered_at TEXT,
        read_at TEXT,
        reply_to_message_id INTEGER,
        metadata TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (device_id) REFERENCES devices(bluetooth_address)
          ON DELETE CASCADE
      )
    ''');
    
    // Indexes for common queries
    batch.execute('CREATE INDEX idx_messages_device ON messages(device_id)');
    batch.execute('CREATE INDEX idx_messages_status ON messages(status)');
    batch.execute('CREATE INDEX idx_messages_created ON messages(created_at)');
    batch.execute('CREATE INDEX idx_messages_type ON messages(message_type)');
    batch.execute(
      'CREATE INDEX idx_messages_device_created ON messages(device_id, created_at DESC)'
    );

    // ==================== FILE TRANSFERS TABLE ====================
    batch.execute('''
      CREATE TABLE file_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transfer_id TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        file_path TEXT,
        mime_type TEXT NOT NULL,
        direction INTEGER NOT NULL DEFAULT 0,
        status INTEGER NOT NULL DEFAULT 0,
        bytes_transferred INTEGER DEFAULT 0,
        last_chunk_index INTEGER DEFAULT -1,
        total_chunks INTEGER DEFAULT 0,
        received_chunks TEXT DEFAULT '',
        checksum TEXT,
        actual_checksum TEXT,
        current_speed INTEGER DEFAULT 0,
        average_speed INTEGER DEFAULT 0,
        started_at TEXT,
        paused_at TEXT,
        resumed_at TEXT,
        completed_at TEXT,
        failure_reason TEXT,
        retry_count INTEGER DEFAULT 0,
        metadata TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (device_id) REFERENCES devices(bluetooth_address)
          ON DELETE CASCADE
      )
    ''');
    
    batch.execute('CREATE INDEX idx_file_transfers_device ON file_transfers(device_id)');
    batch.execute('CREATE INDEX idx_file_transfers_status ON file_transfers(status)');
    batch.execute('CREATE INDEX idx_file_transfers_transfer_id ON file_transfers(transfer_id)');

    // ==================== OFFLINE QUEUE TABLE ====================
    batch.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        message_id INTEGER,
        packet_data BLOB NOT NULL,
        priority INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 10,
        created_at TEXT NOT NULL,
        expires_at TEXT,
        FOREIGN KEY (device_id) REFERENCES devices(bluetooth_address)
          ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES messages(id)
          ON DELETE CASCADE
      )
    ''');
    
    batch.execute('CREATE INDEX idx_offline_queue_device ON offline_queue(device_id)');
    batch.execute('CREATE INDEX idx_offline_queue_priority ON offline_queue(priority DESC, created_at ASC)');

    // ==================== APP SETTINGS TABLE ====================
    batch.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        type TEXT DEFAULT 'string',
        updated_at TEXT NOT NULL
      )
    ''');

    // Execute all statements
    await batch.commit(noResult: true);
    
    AppLogger.info('Database schema created successfully', 'Database');
    
    // Insert default settings
    await _insertDefaultSettings(db);
  }

  /// Insert default application settings
  Future<void> _insertDefaultSettings(Database db) async {
    final now = DateTime.now().toIso8601String();
    final defaultSettings = [
      {'key': 'nickname', 'value': '', 'type': 'string'},
      {'key': 'auto_accept_files', 'value': 'false', 'type': 'bool'},
      {'key': 'max_file_size_limit', 'value': '0', 'type': 'int'}, // 0 = unlimited
      {'key': 'thermal_throttling_enabled', 'value': 'true', 'type': 'bool'},
      {'key': 'show_notification_badge', 'value': 'true', 'type': 'bool'},
      {'key': 'dark_mode', 'value': 'true', 'type': 'bool'},
      {'key': 'chat_backup_enabled', 'value': 'false', 'type': 'bool'},
      {'key': 'last_cleanup_run', 'value': now, 'type': 'datetime'},
    ];

    final batch = db.batch();
    for (final setting in defaultSettings) {
      batch.rawInsert(
        'INSERT OR IGNORE INTO app_settings (key, value, type, updated_at) VALUES (?, ?, ?, ?)',
        [setting['key'], setting['value'], setting['type'], now],
      );
    }
    await batch.commit(noResult: true);

    AppLogger.info('Default settings inserted', 'Database');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLogger.info('Upgrading database from $oldVersion to $newVersion', 'Database');
    
    // Version migration logic here
    // Example:
    // if (oldVersion < 2) { /* Add new column */ }
  }

  /// Called when database is opened
  Future<void> _onOpen(Database db) async {
    // Enable foreign key constraints
    await db.execute('PRAGMA foreign_keys = ON');
    
    // Performance optimizations
    await db.execute('PRAGMA journal_mode = WAL'); // Write-Ahead Logging for better concurrency
    await db.execute('PRAGMA synchronous = NORMAL'); // Balance between safety and speed
    await db.execute('PRAGMA cache_size = -2000');   // 2MB cache
    
    AppLogger.info('Database opened with optimized settings', 'Database');
  }

  // ==================== UTILITY METHODS ====================

  /// Test database connection
  Future<bool> testConnection() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT 1');
      return result.isNotEmpty;
    } catch (e) {
      AppLogger.error('Database connection test failed', 'Database', e);
      return false;
    }
  }

  /// Get database size in bytes
  Future<int> getDatabaseSize() async {
    try {
      final String dbPath = await getDatabasesPath();
      final File file = File(join(dbPath, 'rapid_mesh.db'));
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      AppLogger.error('Failed to get database size', 'Database', e);
      return 0;
    }
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      AppLogger.info('Database closed', 'Database');
    }
  }

  /// Clear all data (for testing/debugging only)
  Future<void> clearAllData() async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('offline_queue');
        await txn.delete('file_transfers');
        await txn.delete('messages');
        await txn.delete('devices');
      });
      AppLogger.warn('All data cleared from database', 'Database');
    } catch (e) {
      AppLogger.error('Failed to clear data', 'Database', e);
    }
  }

  /// Run VACUUM to reclaim space
  Future<void> vacuum() async {
    try {
      final db = await database;
      await db.execute('VACUUM');
      AppLogger.info('Database vacuumed successfully', 'Database');
    } catch (e) {
      AppLogger.error('Vacuum failed', 'Database', e);
    }
  }
}
