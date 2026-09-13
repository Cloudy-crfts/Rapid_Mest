import 'package:flutter/material.dart';

import '../../core/storage/storage_monitor.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';
import 'storage_error_dialog.dart';

/// File Receive Permission Dialog
///
/// Shown on the receiver's phone when another Rapid Mesh device wants to send
/// a file. Before accepting, the phone checks it has room for the file (files
/// can be any size, so a huge file must be rejected early if there is no
/// space). Resolves to `true` if the user accepted (and there was room),
/// `false` otherwise.
class FilePermissionDialog extends StatefulWidget {
  final String senderName;
  final String fileName;
  final int fileSize;
  final String mimeType;

  const FilePermissionDialog({
    super.key,
    required this.senderName,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String senderName,
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FilePermissionDialog(
        senderName: senderName,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
      ),
    );
  }

  @override
  State<FilePermissionDialog> createState() => _FilePermissionDialogState();
}

class _FilePermissionDialogState extends State<FilePermissionDialog> {
  bool _checking = false;

  Future<void> _accept() async {
    setState(() => _checking = true);

    // Files can be any size, so check the phone actually has room before we
    // tell the sender to start streaming.
    final hasRoom =
        await StorageMonitor.instance.hasEnoughSpaceFor(widget.fileSize);

    if (!mounted) return;

    if (hasRoom) {
      Navigator.pop(context, true);
      return;
    }

    Navigator.pop(context, false);
    final free = await StorageMonitor.instance.getStorageInfo();
    if (!mounted) return;
    StorageErrorDialog.show(
      context: context,
      requiredSpace: widget.fileSize,
      availableSpace: free.freeSpace,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.file_download_outlined, color: AppTheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Incoming File')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.senderName}" wants to send you a file.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.insert_drive_file,
                      color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${Helpers.formatFileSize(widget.fileSize)} • ${widget.mimeType.isEmpty ? 'file' : widget.mimeType}',
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
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: 130,
          height: 48,
          child: OutlinedButton(
            onPressed: _checking
                ? null
                : () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.error, width: 1.5),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'DECLINE',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 130,
          height: 48,
          child: ElevatedButton(
            onPressed: _checking ? null : _accept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'ACCEPT',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
