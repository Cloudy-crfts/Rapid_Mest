import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database/app_database.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Profile Service
///
/// Holds the user's locally-stored profile: a display name and an avatar
/// image. The display name (and a small copy of the avatar) is sent inside the
/// Bluetooth handshake so other Rapid Mesh users can see who they are talking
/// to. Everything lives on the phone - nothing is ever uploaded anywhere.
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();

  static ProfileService get instance => _instance;

  static const String _keyName = 'profile_name';
  static const String _keyAvatar = 'profile_avatar_path';

  String _displayName = AppConstants.deviceDisplayName;
  String? _avatarPath;
  Uint8List? _avatarBytes;

  String get displayName => _displayName;
  String? get avatarPath => _avatarPath;
  Uint8List? get avatarBytes => _avatarBytes;

  ProfileService._internal();

  /// Load the saved name and avatar from storage. Safe to call at startup.
  Future<void> load() async {
    try {
      final name = await AppDatabase.instance.getSetting(_keyName);
      if (name != null && name.trim().isNotEmpty) {
        _displayName = name.trim();
      }
      final avatar = await AppDatabase.instance.getSetting(_keyAvatar);
      if (avatar != null && avatar.isNotEmpty) {
        final file = File(avatar);
        if (await file.exists()) {
          _avatarPath = avatar;
          _avatarBytes = await file.readAsBytes();
        }
      }
    } catch (e) {
      AppLogger.error('Failed to load profile', 'Profile', e);
    }
  }

  /// Update the display name shown to other users.
  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _displayName = trimmed;
    await AppDatabase.instance.setSetting(_keyName, trimmed);
    AppLogger.info('Display name updated', 'Profile');
  }

  /// Set the avatar from raw image bytes (downscaled to a shareable size).
  Future<void> setAvatarBytes(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException('Unsupported image format');
      }

      // Downscale so the longest side is at most 512px - small enough to send
      // over Bluetooth in the handshake, large enough to look good.
      final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
      var resized = decoded;
      if (longest > 512) {
        if (decoded.width >= decoded.height) {
          resized = img.copyResize(decoded, width: 512);
        } else {
          resized = img.copyResize(decoded, height: 512);
        }
      }

      final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 82));

      final dir = await getApplicationDocumentsDirectory();
      final profileDir = Directory(p.join(dir.path, 'profile'));
      if (!await profileDir.exists()) {
        await profileDir.create(recursive: true);
      }
      final file = File(p.join(profileDir.path, 'avatar.jpg'));
      await file.writeAsBytes(encoded);

      _avatarPath = file.path;
      _avatarBytes = encoded;
      await AppDatabase.instance.setSetting(_keyAvatar, file.path);
      AppLogger.info('Avatar updated (${encoded.length} bytes)', 'Profile');
    } catch (e) {
      AppLogger.error('Failed to set avatar', 'Profile', e);
      rethrow;
    }
  }

  /// The profile payload sent inside the Bluetooth handshake.
  Map<String, dynamic> handshakeProfile() {
    return {
      'name': _displayName,
      if (_avatarBytes != null) 'avatar': base64Encode(_avatarBytes!),
    };
  }
}
