import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/database/daos/message_dao.dart';
import '../../core/database/models/file_transfer.dart';
import '../../core/database/models/message.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/file_progress_widget.dart';

/// Chat Screen
///
/// One-to-one chat with a connected device. Messages are loaded from the local
/// database (no sample data), and files are streamed over Bluetooth with the
/// file transfer engine exposed by [BluetoothService].
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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final MessageDao _messageDao = MessageDao();

  bool _isConnected = false;
  bool _loading = true;

  List<Message> _messages = [];

  /// Active file transfers in this chat, keyed by transfer id.
  final Map<String, _ActiveTransfer> _activeTransfers = {};

  StreamSubscription<ConnectionEvent>? _eventSub;

  String get _address => widget.deviceAddress ?? '';

  @override
  void initState() {
    super.initState();
    _isConnected = _address.isNotEmpty &&
        (BluetoothService.instance.getConnectionInfo(_address)?.isConnected ??
            false);
    _eventSub = BluetoothService.instance.events.listen(_handleConnectionEvent);
    _loadMessages();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_address.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final list = await _messageDao.getByDevice(deviceId: _address);
    if (!mounted) return;
    setState(() {
      _messages = list;
      _loading = false;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isConnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: AppTheme.error.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth_disabled,
                        size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Text(
                      'Disconnected - messages are saved and send when connected',
                      style: TextStyle(color: AppTheme.error, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildMessagesList()),
            if (_activeTransfers.isNotEmpty) _buildActiveTransfersSection(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final avatarPath =
        BluetoothService.instance.getConnectionInfo(_address)?.avatarPath;
    final avatarFile =
        (avatarPath != null && File(avatarPath).existsSync()) ? avatarPath : null;

    return AppBar(
      leadingWidth: 48,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatarFile != null) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primary.withOpacity(0.2),
              foregroundImage: FileImage(File(avatarFile)),
            ),
            const SizedBox(width: 10),
          ],
          Column(
            children: [
              Text(
                widget.deviceName,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
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
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: () => _showMoreOptions(context),
          icon: const Icon(Icons.more_vert),
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56, color: AppTheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              _isConnected
                  ? 'No messages yet. Say hello!'
                  : 'Connect to this device to start chatting.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageItem(msg, index);
      },
    );
  }

  Widget _buildMessageItem(Message msg, int index) {
    final isGrouped = index > 0 &&
        _messages[index - 1].isOutgoing == msg.isOutgoing &&
        msg.createdAt
                .difference(_messages[index - 1].createdAt)
                .inMinutes <
            2;

    return ChatBubble(
      message: msg,
      isSent: msg.isOutgoing,
      showTimestamp: true,
      isGrouped: isGrouped,
      onTap: () => _onMessageTap(msg),
      onLongPress: () => _onMessageLongPress(msg),
    );
  }

  Widget _buildActiveTransfersSection() {
    final transfers = _activeTransfers.values.toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView(
        shrinkWrap: true,
        children: transfers
            .map((t) => FileProgressWidget(
                  transfer: _toFileTransfer(t),
                  compact: true,
                  onPause: () => BluetoothService.instance.fileTransfers
                      .pauseTransfer(t.transferId),
                  onResume: () => BluetoothService.instance.fileTransfers
                      .resumeTransfer(t.transferId),
                  onCancel: () => BluetoothService.instance.fileTransfers
                      .cancelTransfer(t.transferId),
                ))
            .toList(),
      ),
    );
  }

  FileTransfer _toFileTransfer(_ActiveTransfer t) {
    return FileTransfer(
      transferId: t.transferId,
      deviceId: _address,
      fileName: t.fileName,
      fileSize: t.fileSize,
      mimeType: '*/*',
      direction: t.outgoing ? 0 : 1,
      status: t.status,
      bytesTransferred: t.bytesTransferred,
      currentSpeed: t.speedBps,
    );
  }

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
          IconButton(
            onPressed: () => _showAttachmentOptions(context),
            icon: Icon(Icons.attach_file_rounded,
                color: AppTheme.onSurfaceVariant),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 5,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SENDING ====================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final address = _address;
    if (address.isEmpty || !_isConnected) {
      _showSnack('Connect to this device to send messages');
      return;
    }

    // Wire-level id (unique per message across devices).
    final messageId = 'm${DateTime.now().microsecondsSinceEpoch}';
    final message = Message(
      messageId: messageId,
      deviceId: address,
      messageType: MessageType.text,
      content: text,
      status: MessageStatus.sending,
      isOutgoing: true,
    );

    final saved = await _messageDao.insert(message);
    if (!mounted) return;
    setState(() {
      _messages.add(saved);
      _messageController.clear();
    });
    _scrollToBottom();

    final ok = await BluetoothService.instance.sendTextMessage(
      address: address,
      messageId: messageId,
      text: text,
    );
    if (!mounted) return;

    if (ok) {
      if (saved.id != null) {
        await _messageDao.updateStatus(
            saved.id!, MessageStatus.sent);
      }
    } else {
      if (saved.id != null) {
        await _messageDao.updateStatus(
            saved.id!, MessageStatus.failed);
      }
    }
    _loadMessages();
  }

  // ==================== FILE PICKING ====================

  Future<void> _pickAndSendFile(FileType type) async {
    final address = _address;
    if (address.isEmpty || !_isConnected) {
      _showSnack('Connect to this device to send files');
      return;
    }

    final file = await FilePicker.pickFile(type: type);
    if (file == null) return;

    final path = file.path;
    if (path == null) {
      _showSnack('Could not read the selected file');
      return;
    }

    final transferId = await BluetoothService.instance.fileTransfers.startSend(
      address: address,
      filePath: path,
      fileName: file.name,
      fileSize: file.lengthSync() ?? 0,
      mimeType: Helpers.getMimeType(file.name),
    );

    if (transferId == null) {
      _showSnack('Could not start the transfer');
    }
  }

  // ==================== EVENTS ====================

  void _handleConnectionEvent(ConnectionEvent event) {
    if (_address.isEmpty || event.address != _address) return;
    if (!mounted) return;

    if (event is TextMessageReceivedEvent) {
      setState(() => _isConnected = true);
      _loadMessages();
    } else if (event is TextMessageAckEvent) {
      _loadMessages();
    } else if (event is FileTransferProgressEvent) {
      setState(() {
        _activeTransfers[event.transferId] = _ActiveTransfer(
          transferId: event.transferId,
          fileName: event.fileName,
          fileSize: event.totalBytes,
          outgoing: event.outgoing,
          bytesTransferred: event.bytesTransferred,
          speedBps: event.speedBps.toInt(),
          status: TransferStatus.transferring,
        );
      });
    } else if (event is FileTransferCompletedEvent) {
      setState(() {
        _activeTransfers.remove(event.transferId);
      });
      _loadMessages();
      if (event.success && !event.outgoing) {
        _showSnack('✓ Received ${event.fileName}');
      } else if (!event.success) {
        _showSnack('✗ ${event.fileName}: ${event.error ?? 'failed'}');
      }
    } else if (event is ConnectionLostEvent) {
      setState(() => _isConnected = false);
    } else if (event is ConnectionEstablishedEvent) {
      setState(() => _isConnected = true);
      _loadMessages();
    }
  }

  // ==================== UI HELPERS ====================

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onMessageTap(Message msg) {
    // Tapping a file message could open the received file; for now nothing.
  }

  void _onMessageLongPress(Message msg) {
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
              onTap: () {
                Navigator.pop(context);
                if (msg.content != null) {
                  Clipboard.setData(ClipboardData(text: msg.content!));
                  _showSnack('Copied');
                }
              },
            ),
            if (msg.isOutgoing) ...[
              const Divider(color: AppTheme.borderLight),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.error),
                title:
                    Text('Delete for me', style: TextStyle(color: AppTheme.error)),
                onTap: () async {
                  Navigator.pop(context);
                  if (msg.id != null) {
                    await _messageDao.deleteForMe(msg.id!);
                    _loadMessages();
                  }
                },
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
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                children: [
                  _attachOption(
                      Icons.image, 'Gallery', Colors.purple, FileType.image),
                  _attachOption(
                      Icons.videocam, 'Video', Colors.red, FileType.video),
                  _attachOption(Icons.audiotrack, 'Audio', Colors.orange,
                      FileType.audio),
                  _attachOption(Icons.insert_drive_file, 'File', Colors.green,
                      FileType.any),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption(
      IconData icon, String label, Color color, FileType fileType) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _pickAndSendFile(fileType);
      },
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Device info'),
              subtitle: Text(_address.isEmpty ? 'Not connected' : _address),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.error),
              title:
                  Text('Clear chat', style: TextStyle(color: AppTheme.error)),
              onTap: () async {
                Navigator.pop(context);
                if (_address.isNotEmpty) {
                  await _messageDao.clearChat(_address);
                  _loadMessages();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight in-flight transfer state for the chat header progress list.
class _ActiveTransfer {
  final String transferId;
  final String fileName;
  final int fileSize;
  final bool outgoing;
  final int bytesTransferred;
  final int speedBps;
  final int status;

  _ActiveTransfer({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.outgoing,
    required this.bytesTransferred,
    required this.speedBps,
    required this.status,
  });
}
