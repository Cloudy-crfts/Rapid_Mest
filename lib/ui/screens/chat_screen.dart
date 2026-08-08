import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/file_progress_widget.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

/// Chat Screen
/// 
/// Full chat interface with:
/// - WhatsApp/Instagram-style dark theme
/// - Sent messages: Slate Blue (#7B68EE) bubbles
/// - Received messages: Dark Gray (#2D2D2D) bubbles
/// - Message input with attachment options
/// - File transfer progress display
/// - Delivery status indicators
/// - Timestamps and read receipts

class ChatScreen extends StatefulWidget {
  final String deviceName;
  final String? deviceAddress;

  const ChatScreen({
    super.key,
    required this.deviceName,
    this.deviceAddress,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;
  bool _isConnected = true; // Would come from BluetoothService
  
  // Sample messages for demo
  late List<_SampleMessage> _messages;

  @override
  void initState() {
    super.initState();
    
    // Initialize with sample data
    _messages = [
      _SampleMessage(
        id: '1',
        content: 'Hey! How are you?',
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 30)),
        status: MessageStatus.read,
      ),
      _SampleMessage(
        id: '2',
        content: "I'm good! Just testing Rapid Mesh 🚀",
        isSent: true,
        time: DateTime.now().subtract(const Duration(minutes: 29)),
        status: MessageStatus.read,
      ),
      _SampleMessage(
        id: '3',
        content: 'This looks amazing! The dark theme is so clean.',
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 28)),
        status: MessageStatus.delivered,
      ),
      _SampleMessage(
        id: '4',
        content: "Right? I love how it's completely offline. No servers, no internet needed!",
        isSent: true,
        time: DateTime.now().subtract(const Duration(minutes: 27)),
        status: MessageStatus.delivered,
      ),
      _SampleMessage(
        id: '5',
        type: MessageType.file,
        content: null,
        fileName: 'vacation_photos.zip',
        fileSize: 157286400, // ~150 MB
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 25)),
        status: MessageStatus.delivered,
      ),
      _SampleMessage(
        id: '6',
        content: 'Check out these photos from our trip! 📸',
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 25)),
        status: MessageStatus.delivered,
        replyToId: '5',
      ),
      _SampleMessage(
        id: '7',
        content: "Wow, these are incredible! 😍",
        isSent: true,
        time: DateTime.now().subtract(const Duration(minutes: 24)),
        status: MessageStatus.sent,
        replyToId: '6',
      ),
      _SampleMessage(
        id: '8',
        type: MessageType.voice,
        content: null,
        duration: '0:23',
        isSent: true,
        time: DateTime.now().subtract(const Duration(minutes: 20)),
        status: MessageStatus.sent,
      ),
      _SampleMessage(
        id: '9',
        content: "I'm sending you that presentation we discussed. It's about 200MB.",
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 15)),
        status: MessageStatus.delivered,
      ),
      _SampleMessage(
        id: '10',
        type: MessageType.file,
        content: null,
        fileName: 'Q4_Presentation.pptx',
        fileSize: 209715200, // ~200 MB
        isSent: false,
        time: DateTime.now().subtract(const Duration(minutes: 14)),
        status: MessageStatus.transferring,
        transferProgress: 67.5,
        transferSpeed: 125000, // ~125 KB/s
      ),
    ];
    
    // Scroll to bottom after build
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Connection status bar (if disconnected)
            if (!_isConnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: AppTheme.error.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Text(
                      'Disconnected - Messages will be sent when connected',
                      style: TextStyle(color: AppTheme.error, fontSize: 12),
                    ),
                  ],
                ),
              ),
            
            // Messages list
            Expanded(child: _buildMessagesList()),
            
            // Active transfers section
            if (_hasActiveTransfers())
              _buildActiveTransfersSection(),
            
            // Input area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  /// Build app bar with device info
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      title: Column(
        children: [
          Text(
            widget.deviceName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnected ? AppTheme.success : AppTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isConnected ? 'Connected' : 'Offline',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: () => _showCallOptions(context),
          icon: Icon(Icons.call, color: AppTheme.primary),
        ),
        IconButton(
          onPressed: () => _showMoreOptions(context),
          icon: const Icon(Icons.more_vert),
        ),
      ],
    );
  }

  /// Build messages list
  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: _messages.length + 1, // +1 for date separator placeholder
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildDateSeparator(DateTime.now());
        }
        
        final msg = _messages[index - 1];
        return _buildMessageItem(msg);
      },
    );
  }

  /// Build date/time separator
  Widget _buildDateSeparator(DateTime date) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Today',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// Build individual message item
  Widget _buildMessageItem(_SampleMessage msg) {
    // Check if grouped with previous message (same sender, within 2 minutes)
    bool isGrouped = false;
    if (_messages.indexOf(msg) > 0) {
      final prevMsg = _messages[_messages.indexOf(msg) - 1];
      isGrouped = prevMsg.isSent == msg.isSent &&
                   msg.time.difference(prevMsg.time).inMinutes < 2;
    }

    // Create message object for ChatBubble
    final message = Message(
      deviceId: widget.deviceAddress ?? '',
      messageType: msg.type.index,
      content: msg.content,
      fileName: msg.fileName,
      fileSize: msg.fileSize,
      status: msg.status.index,
      isOutgoing: msg.isSent,
      createdAt: msg.time,
      metadata: msg.type == MessageType.voice 
          ? {'duration': msg.duration} 
          : null,
    );

    return ChatBubble(
      message: message,
      isSent: msg.isSent,
      showTimestamp: !isGrouped || _isLastInGroup(msg),
      isGrouped: isGrouped,
      onTap: () => _onMessageTap(msg),
      onLongPress: () => _onMessageLongPress(msg),
    );
  }

  bool _isLastInGroup(_SampleMessage msg) {
    final index = _messages.indexOf(msg);
    if (index >= _messages.length - 1) return true;
    
    final nextMsg = _messages[index + 1];
    return nextMsg.isSent != msg.isSent ||
           nextMsg.time.difference(msg.time).inMinutes >= 2;
  }

  /// Build active transfers section
  Widget _buildActiveTransfersSection() {
    final activeTransfer = _messages.where((m) => m.status == MessageStatus.transferring).firstOrNull;
    
    if (activeTransfer == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: FileProgressWidget(
        transfer: FileTransfer(
          transferId: 'transfer_123',
          deviceId: widget.deviceAddress ?? '',
          fileName: activeTransfer.fileName ?? 'File',
          fileSize: activeTransfer.fileSize ?? 0,
          mimeType: '*/*',
          direction: activeTransfer.isSent ? 0 : 1,
          status: TransferStatus.transferring,
          bytesTransferred: ((activeTransfer.transferProgress ?? 0) / 100 * (activeTransfer.fileSize ?? 0)).toInt(),
          currentSpeed: activeTransfer.transferSpeed?.toInt() ?? 0,
        ),
        compact: true,
        onPause: () {},
        onResume: () {},
        onCancel: () {},
      ),
    );
  }

  /// Build input area
  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Attachment button
          IconButton(
            onPressed: () => _showAttachmentOptions(context),
            icon: Icon(Icons.attach_file_rounded, color: AppTheme.onSurfaceVariant),
          ),
          
          // Input field
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              onChanged: (value) {
                setState(() {
                  _isTyping = value.isNotEmpty;
                });
              },
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 5,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          
          // Voice/Send toggle
          if (_isTyping)
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            )
          else
            GestureDetector(
              onLongPressStart: (_) => _startVoiceRecording(),
              onLongPressEnd: (_) => _stopVoiceRecording(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== ACTIONS ====================

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final newMessage = _SampleMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: _messageController.text.trim(),
      isSent: true,
      time: DateTime.now(),
      status: MessageStatus.sending,
    );

    setState(() {
      _messages.add(newMessage);
      _messageController.clear();
      _isTyping = false;
    });

    _scrollToBottom();

    // Simulate sending (would use BluetoothService in real app)
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        newMessage.status = MessageStatus.sent;
      });
      
      // Simulate delivery after another delay
      Future.delayed(const Duration(seconds: 1), () {
        setState(() {
          newMessage.status = MessageStatus.delivered;
        });
      });
    });
  }

  void _startVoiceRecording() {
    // Would start recording voice message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Recording voice message...'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 365), // Keep showing until stopped
      ),
    );
  }

  void _stopVoiceRecording() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // Would stop recording and send voice message
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _hasActiveTransfers() {
    return _messages.any((m) => m.status == MessageStatus.transferring);
  }

  void _onMessageTap(_SampleMessage msg) {
    // Handle message tap based on type
    switch (msg.type) {
      case MessageType.image:
        _viewImage(msg);
        break;
      case MessageType.video:
        _playVideo(msg);
        break;
      case MessageType.audio:
        _playAudio(msg);
        break;
      case MessageType.file:
        _openFile(msg);
        break;
      default:
        break;
    }
  }

  void _onMessageLongPress(_SampleMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(context),
            ),
            
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context),
            ),
            
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () => Navigator.pop(context),
            ),
            
            if (msg.isSent) ...[
              Divider(color: AppTheme.borderLight),
              
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.error),
                title: Text('Delete for me', style: TextStyle(color: AppTheme.error)),
                onTap: () => Navigator.pop(context),
              ),
              
              ListTile(
                leading: Icon(Icons.delete_sweep, color: AppTheme.error),
                title: Text('Delete for everyone', style: TextStyle(color: AppTheme.error)),
                onTap: () => Navigator.pop(context),
              ),
            ],
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Text(
                'Attach',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              
              const SizedBox(height: 24),
              
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                children: [
                  _attachOption(Icons.image, 'Gallery', Colors.purple),
                  _attachOption(Icons.camera_alt, 'Camera', Colors.blue),
                  _attachOption(Icons.audiotrack, 'Audio', Colors.orange),
                  _attachOption(Icons.videocam, 'Video', Colors.red),
                  _attachOption(Icons.insert_drive_file, 'File', Colors.green),
                  _attachOption(Icons.person, 'Contact', Colors.teal),
                  _attachOption(Icons.location_on, 'Location', Colors.cyan),
                  _attachOption(Icons.document_scanner, 'Document', Colors.amber),
                ].map((item) => InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _handleAttachment(item.label);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(item.icon, color: item.color, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(item.label, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )).toList(),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  _AttachOption _attachOption(IconData icon, String label, Color color) {
    return _AttachOption(icon: icon, label: label, color: color);
  }

  void _handleAttachment(String type) {
    switch (type) {
      case 'Gallery':
        // Open image picker
        break;
      case 'Camera':
        // Open camera
        break;
      case 'Audio':
        // Pick audio file
        break;
      case 'Video':
        // Pick video file
        break;
      case 'File':
        // Pick any file
        break;
      case 'Contact':
        // Share contact
        break;
      case 'Location':
        // Share location
        break;
      case 'Document':
        // Scan document
        break;
    }
  }

  void _viewImage(_SampleMessage msg) {}
  void _playVideo(_SampleMessage msg) {}
  void _playAudio(_SampleMessage msg) {}
  void _openFile(_SampleMessage msg) {}

  void _showCallOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call),
              title: const Text('Voice Call'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video Call'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Info'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search in Chat'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Mute Notifications'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.error),
              title: Text('Clear Chat', style: TextStyle(color: AppTheme.error)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              Icon(Icons.block, color: AppTheme.error),
              title: Text('Block Device', style: TextStyle(color: AppTheme.error)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ENUMS & DATA CLASSES ====================

enum MessageType { text, image, video, audio, file, contact, location }

enum MessageStatus { sending, sent, delivered, read, failed, queued }

class _SampleMessage {
  final String id;
  final String? content;
  final String? fileName;
  final long? fileSize;
  final int? duration; // For voice messages in seconds
  final bool isSent;
  final DateTime time;
  final MessageStatus status;
  final MessageType type;
  final String? replyToId;
  final double? transferProgress;
  final int? transferSpeed;

  _SampleMessage({
    required this.id,
    this.content,
    this.fileName,
    this.fileSize,
    this.duration,
    required this.isSent,
    required this.time,
    required this.status,
    this.type = MessageType.text,
    this.replyToId,
    this.transferProgress,
    this.transferSpeed,
  });
}

class _AttachOption {
  final IconData icon;
  final String label;
  final Color color;
  
  _AttachOption({required this.icon, required this.label, required this.color});
}
