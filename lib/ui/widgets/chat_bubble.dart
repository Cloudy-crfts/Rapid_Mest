import 'package:flutter/material.dart';
import '../../core/database/models/message.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';

/// Chat Bubble Widget
/// 
/// Displays a single message bubble with:
/// - Sent/received styling (different colors)
/// - Message content (text, image preview, file info)
/// - Timestamp
/// - Delivery status indicators
/// - Reply indicator

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool isSent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading; // Avatar or icon for received messages
  final Widget? trailing; // Status indicators for sent messages
  final bool showTimestamp;
  final bool isGrouped; // If true, hide avatar and timestamp (consecutive messages)

  const ChatBubble({
    super.key,
    required this.message,
    required this.isSent,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.trailing,
    this.showTimestamp = false,
    this.isGrouped = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSent ? 48 : 12,
        right: isSent ? 12 : 48,
        top: isGrouped ? 2 : 8,
        bottom: isGrouped ? 2 : 8,
      ),
      child: Row(
        mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Leading widget (avatar) for received messages
          if (!isSent && !isGrouped && leading != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: AppConstants.avatarSizeChat,
                height: AppConstants.avatarSizeChat,
                child: leading,
              ),
            ),
          ],
          
          // Bubble content
          Flexible(
            child: Column(
              crossAxisAlignment: isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Timestamp above bubble if shown and not grouped
                if (showTimestamp && !isGrouped)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      Helpers.formatTime(message.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ),
                
                // Main bubble
                GestureDetector(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: isSent 
                        ? AppTheme.sentBubbleDecoration 
                        : AppTheme.receivedBubbleDecoration,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: _buildContent(context),
                  ),
                ),
                
                // Status and time row for sent messages
                if (isSent && !isGrouped)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Time
                        Text(
                          Helpers.formatTime(message.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.onSurfaceVariant.withOpacity(0.6),
                            fontSize: 11,
                          ),
                        ),
                        
                        const SizedBox(width: 4),
                        
                        // Delivery status icon
                        _buildStatusIcon(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          // Trailing widget (status) for sent messages
          if (isSent && trailing != null && !isGrouped)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: trailing,
            ),
        ],
      ),
    );
  }

  /// Build message content based on type
  Widget _buildContent(BuildContext context) {
    switch (message.messageType) {
      case AppConstants.MessageType.text:
        return _buildTextContent(context);
        
      case AppConstants.MessageType.image:
        return _buildImageContent(context);
        
      case AppConstants.MessageType.video:
        return _buildVideoContent(context);
        
      case AppConstants.MessageType.audio:
        return _buildAudioContent(context);
        
      case AppConstants.MessageType.file:
        return _buildFileContent(context);
        
      case AppConstants.MessageType.contact:
        return _buildContactContent(context);
        
      case AppConstants.MessageType.location:
        return _buildLocationContent(context);
        
      default:
        return _buildTextContent(context);
    }
  }

  /// Build text content
  Widget _buildTextContent(BuildContext context) {
    return Text(
      message.content ?? '',
      style: TextStyle(
        color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
        fontSize: 16,
        height: 1.4,
      ),
    );
  }

  /// Build image content with thumbnail
  Widget _buildImageContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image thumbnail
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: message.thumbnailPath != null
                ? Image.asset(
                    message.thumbnailPath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(Icons.image, 'Photo'),
                  )
                : _buildPlaceholder(Icons.image, 'Photo'),
          ),
        ),
        
        // Caption if present
        if (message.content != null && message.content!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message.content!,
            style: TextStyle(
              color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  /// Build video content
  Widget _buildVideoContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video thumbnail with play button
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 220,
                height: 150,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: message.thumbnailPath != null
                    ? Image.asset(
                        message.thumbnailPath!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(Icons.videocam, 'Video'),
                      )
                    : _buildPlaceholder(Icons.videocam, 'Video'),
              ),
            ),
            
            // Play button overlay
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ],
        ),
        
        // File name and size
        if (message.fileName != null) ...[
          const SizedBox(height: 8),
          Text(
            message.fileName!,
            style: TextStyle(
              color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (message.fileSize != null)
            Text(
              Helpers.formatFileSize(message.fileSize!),
              style: TextStyle(
                color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.7),
                fontSize: 11,
              ),
            ),
        ],
      ],
    );
  }

  /// Build audio/voice message content
  Widget _buildAudioContent(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play button
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isSent ? AppTheme.primary : AppTheme.secondary).withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow,
            color: isSent ? AppTheme.primary : AppTheme.secondary,
            size: 24,
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Waveform placeholder (simplified)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform bars (simplified visual)
              Row(
                children: List.generate(20, (index) {
                  final height = 8.0 + (index % 5 * 4).toDouble();
                  return Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: height,
                    decoration: BoxDecoration(
                      color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }),
              ),
              
              const SizedBox(height: 4),
              
              // Duration
              Text(
                message.metadata?['duration'] ?? '0:00',
                style: TextStyle(
                  fontSize: 11,
                  color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build file attachment content
  Widget _buildFileContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // File icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isSent ? AppTheme.primary : AppTheme.secondary).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getFileIcon(),
              color: isSent ? AppTheme.primary : AppTheme.secondary,
              size: 24,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // File details
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  message.fileName ?? 'File',
                  style: TextStyle(
                    color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              if (message.fileSize != null)
                Text(
                  Helpers.formatFileSize(message.fileSize!),
                  style: TextStyle(
                    fontSize: 12,
                    color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.7),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build contact card content
  Widget _buildContactContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Contact avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: isSent ? AppTheme.primary : AppTheme.secondary,
            child: const Icon(Icons.person, color: Colors.white, size: 22),
          ),
          
          const SizedBox(width: 12),
          
          // Contact info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content ?? 'Contact',
                style: TextStyle(
                  color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Tap to save contact',
                style: TextStyle(
                  fontSize: 12,
                  color: (isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText).withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build location sharing content
  Widget _buildLocationContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Map preview placeholder
        Container(
          width: 200,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isSent ? AppTheme.primary : AppTheme.secondary).withOpacity(0.3),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.map_outlined,
                  size: 32,
                  color: (isSent ? AppTheme.primary : AppTheme.secondary).withOpacity(0.5),
                ),
              ),
              
              // Location pin
              Positioned(
                center: const Offset(0, -10),
                child: Icon(
                  Icons.location_on,
                  color: isSent ? AppTheme.primary : AppTheme.secondary,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Location text
        Text(
          message.content ?? 'Shared location',
          style: TextStyle(
            color: isSent ? AppTheme.bubbleSentText : AppTheme.bubbleReceivedText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  /// Build placeholder for missing media
  Widget _buildPlaceholder(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: AppTheme.onSurfaceVariant.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.onSurfaceVariant.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Get appropriate file icon based on extension
  IconData _getFileIcon() {
    if (message.fileName == null) return Icons.insert_drive_file;
    
    final ext = Helpers.getFileExtension(message.fileName!).toLowerCase();
    
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.folder_zip;
    if (['apk'].contains(ext)) return Icons.android;
    if (['txt', 'md'].contains(ext)) return Icons.text_snippet;
    
    return Icons.insert_drive_file;
  }

  /// Build delivery status icon
  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    double size = 16;

    switch (message.status) {
      case AppConstants.MessageStatus.sending:
        icon = Icons.schedule;
        color = AppTheme.statusSending;
        break;
      case AppConstants.MessageStatus.sent:
        icon = Icons.check;
        color = AppTheme.statusSent;
        break;
      case AppConstants.MessageStatus.delivered:
        icon = Icons.done_all;
        color = AppTheme.statusDelivered;
        break;
      case AppConstants.MessageStatus.read:
        icon = Icons.done_all;
        color = AppTheme.statusRead;
        break;
      case AppConstants.MessageStatus.failed:
        icon = Icons.error_outline;
        color = AppTheme.statusFailed;
        break;
      default:
        icon = Icons.schedule;
        color = AppTheme.statusSending;
    }

    return Icon(icon, color: color, size: size);
  }
}
