import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/database/daos/device_dao.dart';
import '../../core/database/daos/message_dao.dart';
import '../../core/database/models/device.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';

/// Home Screen
/// 
/// Main screen with two tabs:
/// 1. **Chats Tab**: Shows list of conversations with saved devices
/// 2. **Devices Tab**: Shows nearby Bluetooth devices for scanning/connecting
/// 
/// Navigation: WhatsApp-style bottom tab bar
/// Theme: Instagram-dark (Color Scheme B)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  int _connectionCount = 0;
  StreamSubscription<ConnectionEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _connectionCount = BluetoothService.instance.connectionCount;

    // Keep the connection badge live.
    _eventSub = BluetoothService.instance.events.listen((_) {
      if (!mounted) return;
      final count = BluetoothService.instance.connectionCount;
      if (count != _connectionCount) {
        setState(() => _connectionCount = count);
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _currentIndex = _tabController.index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // App Bar with branding
            _buildAppBar(),
            
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  ChatsTab(),
                  DevicesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      
      // Bottom Navigation (WhatsApp-style)
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
              _tabController.animateTo(index);
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices_other_outlined),
              activeIcon: Icon(Icons.devices_other),
              label: 'Devices',
            ),
          ],
        ),
      ),
      
      // Floating Action Button (for new scan)
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: () {
                // Navigate to device scan screen
                Navigator.pushNamed(context, '/scan');
              },
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.bluetooth_searching, color: Colors.white),
            )
          : null,
    );
  }

  /// Build app bar with Rapid Mesh branding
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo/Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.hub_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          
          const SizedBox(width: 10),
          
          // App name
          Text(
            'Rapid Mesh',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.secondary],
                ).createShader(const Rect.fromLTWH(0, 0, 120, 30)),
            ),
          ),
        ],
      ),
      actions: [
        // Connection status indicator
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bluetooth_connected,
                size: 20,
                color: AppTheme.primary.withOpacity(0.8),
              ),
              const SizedBox(width: 4),
              Text(
                '$_connectionCount',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        
        // Menu button
        IconButton(
          onPressed: () => _showMenu(context),
          icon: const Icon(Icons.more_vert),
        ),
      ],
      
      // Tab bar below title
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.onSurfaceVariant,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        tabs: const [
          Tab(text: 'Chats'),
          Tab(text: 'Devices'),
        ],
      ),
    );
  }

  /// Show options menu
  void _showMenu(BuildContext context) {
    final navigator = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            _buildMenuItem(
              icon: Icons.person_outline,
              label: 'My Profile',
              onTap: () {
                navigator.pop();
                navigator.pushNamed('/settings');
              },
            ),
            
            _buildMenuItem(
              icon: Icons.folder_outlined,
              label: 'Received Files',
              onTap: () => navigator.pop(),
            ),
            
            _buildMenuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                navigator.pop();
                navigator.pushNamed('/settings');
              },
            ),
            
            Divider(color: AppTheme.borderLight, height: 1),
            
            _buildMenuItem(
              icon: Icons.info_outline,
              label: 'About Rapid Mesh',
              onTap: () => navigator.pop(),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.onSurfaceVariant, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== CHATS TAB ====================

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final MessageDao _messageDao = MessageDao();
  List<Conversation> _conversations = [];
  bool _loading = true;
  StreamSubscription<ConnectionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh whenever a message or connection changes.
    _sub = BluetoothService.instance.events.listen((e) {
      if (e is TextMessageReceivedEvent ||
          e is TextMessageAckEvent ||
          e is FileTransferCompletedEvent ||
          e is ConnectionEstablishedEvent ||
          e is ConnectionLostEvent) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _messageDao.getConversations();
    if (!mounted) return;
    setState(() {
      _conversations = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: _conversations.length + 1, // +1 for search header
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSearchHeader(context);
          }
          return _buildChatItem(context, _conversations[index - 1]);
        },
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.onSurfaceVariant),
          suffixIcon: IconButton(
            icon: const Icon(Icons.filter_list, color: AppTheme.onSurfaceVariant),
            onPressed: () {},
          ),
        ),
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, Conversation chat) {
    final isOnline = BluetoothService.instance
            .getConnectionInfo(chat.address)
            ?.isConnected ==
        true;
    final isFile = chat.lastMessageType == MessageType.image ||
        chat.lastMessageType == MessageType.video ||
        chat.lastMessageType == MessageType.audio ||
        chat.lastMessageType == MessageType.file;

    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, '/chat', arguments: {
          'name': chat.displayName,
          'address': chat.address,
        });
      },
      onLongPress: () => _showChatOptions(context, chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary.withOpacity(0.2),
                  child: Text(
                    chat.displayName.isEmpty
                        ? '?'
                        : chat.displayName[0].toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        border: Border.all(color: AppTheme.background, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chat.lastTime != null)
                        Text(
                          Helpers.getRelativeTime(chat.lastTime!),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                                fontSize: 12,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (isFile) ...[
                              Icon(Icons.attach_file,
                                  size: 16,
                                  color: AppTheme.primary.withOpacity(0.6)),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                chat.preview,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppTheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (chat.unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${chat.unread}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatOptions(BuildContext context, Conversation chat) {
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
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open Chat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/chat', arguments: {
                  'name': chat.displayName,
                  'address': chat.address,
                });
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ==================== DEVICES TAB ====================

class DevicesTab extends StatefulWidget {
  const DevicesTab({super.key});

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<DevicesTab> {
  final DeviceDao _deviceDao = DeviceDao();
  List<Device> _devices = [];
  StreamSubscription<ConnectionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = BluetoothService.instance.events.listen((e) {
      if (e is ConnectionEstablishedEvent ||
          e is ConnectionLostEvent ||
          e is IncomingRequestEvent) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final devices = await _deviceDao.getAll();
    if (!mounted) return;
    setState(() => _devices = devices);
  }

  @override
  Widget build(BuildContext context) {
    // Currently connected devices (live, from the Bluetooth service).
    final connected = BluetoothService.instance.connections.entries.toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/scan'),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text(
                'SCAN FOR DEVICES',
                style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Connected now', 'Active Bluetooth links'),
          const SizedBox(height: 12),
          if (connected.isEmpty)
            _emptyState(context, 'Not connected to anyone right now.')
          else
            ...connected
                .map((e) => _connectedCard(context, e.key, e.value.remoteName)),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Device log', 'Devices you have connected to'),
          const SizedBox(height: 12),
          if (_devices.isEmpty)
            _emptyState(context,
                'No devices yet. Scan and connect to someone to see them here.')
          else
            ..._devices.map((d) => _deviceCard(context, d)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.devices_other_outlined,
                size: 48, color: AppTheme.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectedCard(BuildContext context, String address, String? name) {
    final displayName = (name != null && name.isNotEmpty) ? name : address;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.bluetooth_connected,
                  color: AppTheme.success, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(address,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline,
                  color: AppTheme.primary),
              onPressed: () => Navigator.pushNamed(context, '/chat', arguments: {
                'name': displayName,
                'address': address,
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(BuildContext context, Device device) {
    final displayName = device.displayName;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/chat', arguments: {
            'name': displayName,
            'address': device.bluetoothAddress,
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppTheme.primary.withOpacity(0.15),
                child: Text(
                  displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (device.isSaved)
                          Icon(Icons.bookmark,
                              size: 14, color: AppTheme.success),
                        if (device.isSaved) const SizedBox(width: 4),
                        Text(
                          device.bluetoothAddress,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${device.totalMessagesSent + device.totalMessagesReceived} msgs',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chat_bubble_outline, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

