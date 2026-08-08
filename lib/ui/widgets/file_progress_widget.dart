import 'package:flutter/material.dart';
import '../../core/database/models/file_transfer.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';

/// File Transfer Progress Widget
/// 
/// Displays progress information for active file transfers:
/// - File name and icon
/// - Progress bar with percentage
/// - Transfer speed
/// - Estimated time remaining
/// - Pause/Resume/Cancel buttons
/// - Status indicator (transferring, paused, completed, etc.)

class FileProgressWidget extends StatelessWidget {
  final FileTransfer transfer;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;
  final bool showDetails;
  final bool compact;

  const FileProgressWidget({
    super.key,
    required this.transfer,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onTap,
    this.showDetails = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    
    return _buildFull(context);
  }

  /// Build full detailed widget
  Widget _buildFull(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Icon, filename, status
          Row(
            children: [
              // File type icon
              _buildFileIcon(),
              
              const SizedBox(width: 12),
              
              // Filename and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 2),
                    
                    Row(
                      children: [
                        // Status badge
                        _buildStatusBadge(),
                        
                        const SizedBox(width: 8),
                        
                        // Direction indicator
                        Icon(
                          transfer.direction == 0 ? Icons.upload : Icons.download,
                          size: 14,
                          color: AppTheme.onSurfaceVariant,
                        ),
                        
                        const Spacer(),
                        
                        // Percentage
                        Text(
                          '${transfer.progress.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action buttons (if applicable)
              if (_showActionButtons()) ...[
                const SizedBox(width: 8),
                _buildActionButton(),
              ],
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: transfer.progress / 100,
              minHeight: 6,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(),
              ),
            ),
          ),
          
          if (showDetails && transfer.isActive) ...[
            const SizedBox(height: 10),
            
            // Details row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Transferred size / total size
                Text(
                  '${Helpers.formatFileSize(transfer.bytesTransferred)} / ${Helpers.formatFileSize(transfer.fileSize)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                
                // Speed
                if (transfer.currentSpeed > 0)
                  Text(
                    Helpers.formatTransferSpeed(transfer.currentSpeed),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.primary,
                    ),
                  )
                else
                  Text(
                    'Waiting...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                
                // ETA
                if (transfer.estimatedTimeRemainingSeconds != null &&
                    transfer.estimatedTimeRemainingSeconds! > 0)
                  Text(
                    Helpers.formatDuration(transfer.estimatedTimeRemainingSeconds!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            
            // Chunks info (for resumable transfers)
            if (transfer.totalChunks > 1) ...[
              const SizedBox(height: 6),
              Text(
                'Chunk ${transfer.lastChunkIndex + 1} of ${transfer.totalChunks}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Build compact version (for inline use in chat)
  Widget _buildCompact(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // Small file icon
            Icon(
              _getCompactIcon(),
              size: 32,
              color: _getStatusColor().withOpacity(0.8),
            ),
            
            const SizedBox(width: 10),
            
            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.fileName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Mini progress bar or status text
                  if (transfer.status == AppConstants.TransferStatus.transferring ||
                      transfer.status == AppConstants.TransferStatus.paused)
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: transfer.progress / 100,
                            minHeight: 3,
                            backgroundColor: AppTheme.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation(_getProgressColor()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${transfer.progress.toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    )
                  else
                    Text(
                      transfer.getStatusText(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _getStatusColor(),
                      ),
                    ),
                ],
              ),
            ),
            
            // Status icon
            Icon(
              _getStatusIconData(),
              size: 20,
              color: _getStatusColor(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build file type icon
  Widget _buildFileIcon() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _getFileIconColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _getFileIconData(),
        color: _getFileIconColor(),
        size: 24,
      ),
    );
  }

  /// Get file icon based on MIME type/extension
  IconData _getFileIconData() {
    final mimeType = transfer.mimeType.toLowerCase();
    
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('document') || mimeType.contains('word')) return Icons.description;
    if (mimeType.contains('sheet') || mimeType.contains('excel')) return Icons.table_chart;
    if (mimeType.contains('zip') || mimeType.contains('archive') || mimeType.contains('rar'))
      return Icons.folder_zip;
    if (mimeType.contains('apk') || mimeType.contains('android')) return Icons.android;
    
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor() {
    final mimeType = transfer.mimeType.toLowerCase();
    
    if (mimeType.startsWith('image/')) return Colors.blue;
    if (mimeType.startsWith('video/')) return Colors.red;
    if (mimeType.startsWith('audio/')) return Colors.purple;
    if (mimeType.contains('pdf')) return Colors.red[700] ?? Colors.red;
    if (mimeType.contains('document') || mimeType.contains('word')) return Colors.blue[700] ?? Colors.blue;
    if (mimeType.contains('sheet') || mimeType.contains('excel')) return Colors.green[700] ?? Colors.green;
    if (mimeType.contains('zip') || mimeType.contains('archive')) return Colors.orange[700] ?? Colors.orange;
    
    return AppTheme.primary;
  }

  /// Build status badge
  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _getStatusLabel(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _getStatusColor(),
        ),
      ),
    );
  }

  String _getStatusLabel() {
    switch (transfer.status) {
      case AppConstants.TransferStatus.transferring:
        return 'Transferring';
      case AppConstants.TransferStatus.paused:
        return 'Paused';
      case AppConstants.TransferStatus.completed:
        return 'Completed';
      case AppConstants.TransferStatus.failed:
        return 'Failed';
      default:
        return transfer.getStatusText();
    }
  }

  Color _getStatusColor() {
    switch (transfer.status) {
      case AppConstants.TransferStatus.transferring:
        return AppTheme.info;
      case AppConstants.TransferStatus.paused:
        return AppTheme.warning;
      case AppConstants.TransferStatus.completed:
        return AppTheme.success;
      case AppConstants.TransferStatus.failed:
      case AppConstants.TransferStatus.rejected:
      case AppConstants.TransferStatus.cancelled:
        return AppTheme.error;
      default:
        return AppTheme.onSurfaceVariant;
    }
  }

  Color _getProgressColor() {
    switch (transfer.status) {
      case AppConstants.TransferStatus.transferring:
        return AppTheme.primary;
      case AppConstants.TransferStatus.paused:
        return AppTheme.warning;
      case AppConstants.TransferStatus.completed:
        return AppTheme.success;
      case AppConstants.TransferStatus.failed:
        return AppTheme.error;
      default:
        return AppTheme.primary;
    }
  }

  IconData _getStatusIconData() {
    switch (transfer.status) {
      case AppConstants.TransferStatus.transferring:
        return Icons.sync;
      case AppConstants.TransferStatus.paused:
        return Icons.pause_circle;
      case AppConstants.TransferStatus.completed:
        return Icons.check_circle;
      case AppConstants.TransferStatus.failed:
        return Icons.error;
      case AppConstants.TransferStatus.cancelled:
        return Icons.cancel;
      case AppConstants.TransferStatus.pending:
        return Icons.schedule;
      default:
        return Icons.more_horiz;
    }
  }

  IconData _getCompactIcon() => _getFileIconData();

  /// Check if action buttons should be shown
  bool _showActionButtons() {
    return transfer.status == AppConstants.TransferStatus.transferring ||
           transfer.status == AppConstants.TransferStatus.paused;
  }

  /// Build action button (pause/resume/cancel)
  Widget _buildActionButton() {
    if (transfer.status == AppConstants.TransferStatus.transferring) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPause,
            icon: const Icon(Icons.pause, size: 20),
            tooltip: 'Pause',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      );
    } else if (transfer.status == AppConstants.TransferStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow, size: 20),
            tooltip: 'Resume',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Cancel',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      );
    }
    
    return const SizedBox.shrink();
  }
}
