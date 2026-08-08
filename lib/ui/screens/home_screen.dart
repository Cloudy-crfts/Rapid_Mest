import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/dark_theme.dart';
import '../../utils/constants.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
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
              child: const Icon(Icons.bluetooth_search, color: Colors.white),
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
                '2', // Would be dynamic from BluetoothService
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
              onTap: () => Navigator.pop(context),
            ),
            
            _buildMenuItem(
              icon: Icons.folder_outlined,
              label: 'Received Files',
              onTap: () => Navigator.pop(context),
            ),
            
            _buildMenuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => Navigator.pop(context),
            ),
            
            Divider(color: AppTheme.borderLight, height: 1),
            
            _buildMenuItem(
              icon: Icons.info_outline,
              label: 'About Rapid Mesh',
              onTap: () => Navigator.pop(context),
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

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample data - would come from database in real implementation
    final sampleChats = [
      _ChatItem(name: "John's Phone", message: "Hey! Check out this file 📎", time: "2 min ago", unread: 2, hasFile: true),
      _ChatItem(name: "Sarah's Tablet", message: "Thanks for the photos!", time: "1 hour ago", unread: 0, hasFile: false),
      _ChatItem(name: "Mike's Device", message: "📷 Image received", time: "Yesterday", unread: 5, hasFile: true),
      _ChatItem(name: "Emma's Phone", message: "Voice message", time: "Yesterday", unread: 0, hasFile: true),
      _ChatItem(name: "Work Laptop", nameAlias: "Office PC", message: "Document.pdf sent", time: "2 days ago", unread: 0, hasFile: true),
    ];

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: sampleChats.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSearchHeader(context);
          }
          
          final chat = sampleChats[index - 1];
          return _buildChatItem(context, chat);
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

  Widget _buildChatItem(BuildContext context, _ChatItem chat) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, '/chat', arguments: chat.name);
      },
      onLongPress: () => _showChatOptions(context, chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary.withOpacity(0.2),
                  child: Text(
                    chat.name[0].toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                    ),
                  ),
                ),
                
                // Online indicator (if connected)
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
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Name or alias
                      Expanded(
                        child: Text(
                          chat.nameAlias ?? chat.name,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Time
                      Text(
                        chat.time,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 4),
                  
                  Row(
                    children: [
                      // Message preview
                      Expanded(
                        child: Row(
                          children: [
                            if (chat.hasFile)
                              Icon(
                                Icons.attach_file,
                                size: 16,
                                color: AppTheme.primary.withOpacity(0.6),
                              ),
                            Expanded(
                              child: Text(
                                chat.message,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Unread badge
                      if (chat.unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

  void _showChatOptions(BuildContext context, _ChatItem chat) {
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
              onTap: () => Navigator.pop(context),
            ),
            
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context),
            ),
            
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Pin Chat'),
              onTap: () => Navigator.pop(context),
            ),
            
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.error),
              title: Text('Delete Chat', style: TextStyle(color: AppTheme.error)),
              onTap: () => Navigator.pop(context),
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ==================== DEVICES TAB ====================

class DevicesTab extends StatelessWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample data - would come from BLE scanning in real implementation
    final nearbyDevices = [
      _DeviceItem(name: "Alex's iPhone", address: "AA:BB:CC:DD:EE:FF", rssi: -45, isRapidMesh: true),
      _DeviceItem(name: "Samsung Galaxy S23", address: "11:22:33:44:55:66", rssi: -62, isRapidMesh: true),
      _DeviceItem(name: "Unknown Device", address: "77:88:99:AA:BB:CC", rssi: -78, isRapidMesh: false),
    ];
    
    final savedDevices = [
      _DeviceItem(name: "John's Phone", address: "DE:AD:BE:EF:CA:FE", rssi: null, isSaved: true),
      _DeviceItem(name: "Sarah's Tablet", address: "BA:DC:0F:EB:AD:00", rssi: null, isSaved: true),
    ];

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Scan button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/scan');
              },
              icon: const Icon(Icons.bluetooth_search),
              label: const Text(
                'SCAN FOR DEVICES',
                style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Nearby devices section
          ..._buildSection(
            context,
            title: 'Nearby Devices',
            subtitle: 'Tap to connect',
            isEmpty: nearbyDevices.isEmpty,
            emptyMessage: 'No devices found. Tap scan to search.',
            children: nearbyDevices.map((d) => _buildDeviceCard(context, d)).toList(),
          ),
          
          const SizedBox(height: 24),
          
          // Saved devices section
          ..._buildSection(
            context,
            title: 'Saved Devices',
            subtitle: 'Your trusted connections',
            isEmpty: savedDevices.isEmpty,
            emptyMessage: 'No saved devices yet.',
            children: savedDevices.map((d) => _buildSavedDeviceCard(context, d)).toList(),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<Widget> _buildSection(
    BuildContext context, {
    required String title,
    String? subtitle,
    required bool isEmpty,
    String? emptyMessage,
    required List<Widget> children,
  }) {
    return [
      Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      
      const SizedBox(height: 12),
      
      if (isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.devices_other_outlined,
                  size: 48,
                  color: AppTheme.onSurfaceVariant.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  emptyMessage ?? 'Empty',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
      else
        ...children,
    ];
  }

  Widget _buildDeviceCard(BuildContext context, _DeviceItem device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showConnectDialog(context, device),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Device icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: device.isRapidMesh 
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  device.isRapidMesh ? Icons.hub : Icons.bluetooth,
                  color: device.isRapidMesh ? AppTheme.primary : AppTheme.onSurfaceVariant,
                  size: 26,
                ),
              ),
              
              const SizedBox(width: 14),
              
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        
                        if (device.isRapidMesh)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'RM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    Row(
                      children: [
                        if (device.rssi != null) ...[
                          Icon(
                            Icons.signal_cellular_alt,
                            size: 14,
                            color: _getSignalColor(device.rssi!),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${device.rssi} dBm',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                        ],
                        
                        Icon(
                          Icons.fingerprint,
                          size: 14,
                          color: AppTheme.onSurfaceVariant.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          device.address,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Connect arrow
              Icon(
                Icons.chevron_right,
                color: AppTheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedDeviceCard(BuildContext context, _DeviceItem device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/chat', arguments: device.name);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Saved device avatar
              CircleAvatar(
                radius: 25,
                backgroundColor: AppTheme.success.withOpacity(0.15),
                child: Text(
                  device.name[0].toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              
              const SizedBox(width: 14),
              
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        
                        // Saved badge
                        Icon(
                          Icons.bookmark,
                          size: 18,
                          color: AppTheme.success,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Saved • ${device.address}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Open chat arrow
              Icon(
                Icons.chat_bubble_outline,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return AppTheme.success;
    if (rssi >= -60) return AppTheme.success.withOpacity(0.7);
    if (rssi >= -70) return AppTheme.warning;
    return AppTheme.error;
  }

  void _showConnectDialog(BuildContext context, _DeviceItem device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Connect to ${device.name}?'),
        content: Text(
          'Send a connection request to this device.\n\n'
          'Address: ${device.address}\n'
          '${device.isRapidMesh ? "✓ This is a Rapid Mesh device" : "⚠ Unknown device type"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Initiate connection
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Connecting to ${device.name}...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

// ==================== DATA MODELS ====================

class _ChatItem {
  final String name;
  final String? nameAlias;
  final String message;
  final String time;
  final int unread;
  final bool hasFile;

  _ChatItem({
    required this.name,
    this.nameAlias,
    required this.message,
    required this.time,
    required this.unread,
    required this.hasFile,
  });
}

class _DeviceItem {
  final String name;
  final String address;
  final int? rssi;
  final bool isRapidMesh;
  final bool isSaved;

  _DeviceItem({
    required this.name,
    required this.address,
    this.rssi,
    this.isRapidMesh = false,
    this.isSaved = false,
  });
}
