import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database/daos/device_dao.dart';
import '../../services/device_log_store.dart';
import '../../services/profile_service.dart';
import '../../utils/constants.dart';
import '../theme/dark_theme.dart';

/// Settings Screen
///
/// - Profile: display name + avatar (shared with other users over Bluetooth).
/// - Device log: export/import the small list of connected devices, so it can
///   survive an uninstall (stored in a file the user owns).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final DeviceDao _deviceDao = DeviceDao();

  int _deviceCount = 0;
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _nameController.text = ProfileService.instance.displayName;
    _avatarBytes = ProfileService.instance.avatarBytes;
    _loadDeviceCount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceCount() async {
    final all = await _deviceDao.getAll();
    if (!mounted) return;
    setState(() => _deviceCount = all.length);
  }

  Future<void> _pickAvatar() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    try {
      await ProfileService.instance.setAvatarBytes(bytes);
      if (!mounted) return;
      setState(() => _avatarBytes = ProfileService.instance.avatarBytes);
      _snack('Avatar updated');
    } catch (_) {
      _snack('Could not read that image', isError: true);
    }
  }

  Future<void> _saveName() async {
    await ProfileService.instance.setDisplayName(_nameController.text);
    if (!mounted) return;
    _snack('Display name saved');
    FocusScope.of(context).unfocus();
  }

  Future<void> _exportLog() async {
    final path = await DeviceLogStore.instance.exportDeviceLog();
    if (!mounted) return;
    if (path != null) {
      _snack('Device list saved');
    }
  }

  Future<void> _importLog() async {
    try {
      final restored = await DeviceLogStore.instance.importDeviceLog();
      if (!mounted) return;
      _snack(restored > 0
          ? 'Restored $restored device${restored == 1 ? '' : 's'}'
          : 'No devices found in that file');
      _loadDeviceCount();
    } catch (_) {
      _snack('That file is not a Rapid Mesh device list', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppTheme.error : AppTheme.surfaceVariant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _sectionTitle('Profile'),
          _card(
            child: Column(
              children: [
                // Avatar
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: AppTheme.surfaceVariant,
                        backgroundImage: _avatarBytes != null
                            ? MemoryImage(_avatarBytes!)
                            : null,
                        child: _avatarBytes == null
                            ? Icon(Icons.person,
                                size: 36, color: AppTheme.onSurfaceVariant)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Profile picture',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to choose an image. A small copy is shared with other users when you connect.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Display name
                TextField(
                  controller: _nameController,
                  maxLength: AppConstants.maxNicknameLength,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Shown to other Rapid Mesh users',
                  ),
                  onSubmitted: (_) => _saveName(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveName,
                    child: const Text('Save name'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Device log'),
          _card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.devices, color: AppTheme.primary),
                  title: const Text('Connected devices'),
                  subtitle: Text(
                    '$_deviceCount device${_deviceCount == 1 ? '' : 's'} saved on this phone',
                  ),
                ),
                const Divider(color: AppTheme.borderLight),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.save_alt, color: AppTheme.success),
                  title: const Text('Export device list'),
                  subtitle: const Text(
                      'Save a small file so your device list survives an uninstall'),
                  onTap: _exportLog,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restore, color: AppTheme.secondary),
                  title: const Text('Import device list'),
                  subtitle: const Text(
                      'After reinstalling, restore the devices you had connected to'),
                  onTap: _importLog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The log only contains device names/addresses and counters - '
            'never your messages. Everything stays on your phone.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
