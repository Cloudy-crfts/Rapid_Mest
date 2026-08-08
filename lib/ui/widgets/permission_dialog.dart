import 'package:flutter/material.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';

/// File Transfer Permission Dialog
/// 
/// Shows when someone wants to send a file to this device.
/// User can Accept or Reject the transfer.
/// 
/// Layout:
/// ┌─────────────────────────────┐
│  📁 File Transfer Request     │
│                             │
│  [Sender Name] wants to send │
│                             │
│  📄 [Filename.ext]           │
│     (File Size)              │
│                             │
│  ┌─────────┐  ┌──────────┐   │
│  │ ACCEPT  │  │ REJECT   │   │
│  └─────────┘  └──────────┘   │
└─────────────────────────────┘

class FilePermissionDialog extends StatelessWidget {
  final String senderName;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const FilePermissionDialog({
    super.key,
    required this.senderName,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
    required this.onAccept,
    required this.onReject,
  });

  /// Show the dialog
  static Future<bool> show({
    required BuildContext context,
    required String senderName,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FilePermissionDialog(
        senderName: senderName,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        onAccept: () => Navigator.of(context).pop(true),
        onReject: () => Navigator.of(context).pop(false),
      ),
    );
    
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getFileIcon(),
                size: 32,
                color: AppTheme.primary,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Title
            Text(
              'File Transfer Request',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // Sender info
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyLarge,
                children: [
                  TextSpan(
                    text: senderName,
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' wants to send you'),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // File info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  // File type icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getFileTypeColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getFileIcon(),
                      color: _getFileTypeColor(),
                      size: 26,
                    ),
                  ),
                  
                  const SizedBox(width: 14),
                  
                  // File details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        const SizedBox(height: 4),
                        
                        Text(
                          Helpers.formatFileSize(fileSize),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 28),
            
            // Action buttons
            Row(
              children: [
                // Reject button
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'REJECT',
                        style: TextStyle(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Accept button
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'ACCEPT',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon() {
    if (mimeType == null) return Icons.insert_drive_file;
    
    final type = mimeType!.toLowerCase();
    
    if (type.startsWith('image/')) return Icons.image;
    if (type.startsWith('video/')) return Icons.videocam;
    if (type.startsWith('audio/')) return Icons.audiotrack;
    if (type.contains('pdf')) return Icons.picture_as_pdf;
    if (type.contains('zip') || type.contains('rar') || type.contains('archive'))
      return Icons.folder_zip;
    
    return Icons.insert_drive_file;
  }

  Color _getFileTypeColor() {
    if (mimeType == null) return AppTheme.primary;
    
    final type = mimeType!.toLowerCase();
    
    if (type.startsWith('image/')) return Colors.blue;
    if (type.startsWith('video/')) return Colors.red[700] ?? Colors.red;
    if (type.startsWith('audio/')) return Colors.purple;
    if (type.contains('pdf')) return Colors.red[700] ?? Colors.red;
    if (type.contains('zip') || type.contains('rar') || type.contains('archive'))
      return Colors.orange[700] ?? Colors.orange;
    
    return AppTheme.primary;
  }
}
