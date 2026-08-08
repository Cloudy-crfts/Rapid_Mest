import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/device_scan_screen.dart';
import 'ui/widgets/connection_request_dialog.dart';
import 'core/database/app_database.dart';
import 'core/bluetooth/bluetooth_service.dart';

/// Global navigator key so the connection-request dialog can be shown from
/// anywhere in the app, even when no screen is actively listening.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Request the Bluetooth permissions the app needs at runtime
  await _requestBluetoothPermissions();

  // Initialize database
  await AppDatabase.instance.database;

  // Initialize Bluetooth service (starts RFCOMM server + BLE advertising)
  await BluetoothService.instance.initialize();

  // Show the Accept/Reject dialog when another phone requests a connection
  _setupConnectionRequestListener();

  runApp(const RapidMeshApp());
}

/// Request the runtime permissions needed for BLE scanning, advertising and
/// connecting over Bluetooth (Android 12+) plus legacy location on old Android.
Future<void> _requestBluetoothPermissions() async {
  try {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }
  } catch (_) {
    // Permissions are surfaced again when the user starts a scan
  }
}

/// Listens for real connection events and shows the global Accept/Reject
/// dialog (or a success snackbar) no matter which screen is open.
void _setupConnectionRequestListener() {
  final bt = BluetoothService.instance;
  bt.events.listen((event) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    if (event is IncomingRequestEvent) {
      ConnectionRequestDialog.show(
        ctx,
        deviceName: event.name,
        address: event.address,
        onAccept: () => bt.acceptIncomingConnection(event.address),
        onReject: () => bt.rejectIncomingConnection(event.address),
      );
    } else if (event is ConnectionEstablishedEvent) {
      final navigator = navigatorKey.currentState;
      final currentRoute = ModalRoute.of(ctx)?.settings.name;
      final scanScreenOpen = currentRoute == '/scan' || currentRoute == '/chat';

      if (navigator != null && !scanScreenOpen) {
        // We are not on the scan screen: open the chat directly (e.g. the
        // other phone accepted while we were on the home screen).
        navigator.pushNamed(
          '/chat',
          arguments: {'name': event.name, 'address': event.address},
        );
      } else {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('✓ Connected to ${event.name}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  });
}

class RapidMeshApp extends StatelessWidget {
  const RapidMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rapid Mesh',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      
      // Dark Theme - Instagram Style (Color Scheme B)
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        
        // Color Scheme B - Material Dark + Slate Blue
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7B68EE),           // Medium Slate Blue - Sent bubbles, primary actions
          onPrimary: Color(0xFFFFFFFF),          // White text on primary
          secondary: Color(0xFF9370DB),          // Medium Purple - Accents, highlights
          onSecondary: Color(0xFF000000),        // Black text on secondary
          surface: Color(0xFF1E1E1E),            // Charcoal - Cards, surfaces
          onSurface: Color(0xFFFFFFFF),          // White text on surface
          error: Color(0xFFFF5252),              // Red for errors
          onError: Color(0xFFFFFFFF),
          background: Color(0xFF121212),         // Material Dark background
          onBackground: Color(0xFFFFFFFF),       // White text on background
          
          // Tertiary colors for variety
          tertiary: Color(0xFF2D2D2D),           // Dark gray for received bubbles
          outline: Color(0xFF3D3D3D),            // Borders, dividers
          outlineVariant: Color(0xFF2A2A2A),     // Subtle dividers
          surfaceContainerHighest: Color(0xFF252525), // Elevated surfaces
          inverseSurface: Color(0xFF7B68EE),     // Inverse background
          inversePrimary: Color(0xFF000000),     // Text on inverse
        ),
        
        // App Bar Theme
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Color(0xFFFFFFFF),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFFFFFFFF)),
          titleTextStyle: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        // Card Theme
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        // Input Decoration Theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: Color(0xFF7B68EE), width: 2),
          ),
          hintStyle: const TextStyle(color: Color(0xFF666666)),
        ),
        
        // Bottom Navigation Theme
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF121212),
          selectedItemColor: Color(0xFF7B68EE),
          unselectedItemColor: Color(0xFF666666),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        
        // Dialog Theme
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        // SnackBar Theme
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2D2D2D),
          contentTextStyle: const TextStyle(color: Color(0xFFFFFFFF)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        
        // Scaffold Background Color
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      
      home: const HomeScreen(),
      
      // Named routes used by the UI
      routes: {
        '/scan': (context) => const DeviceScanScreen(),
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is Map) {
            return ChatScreen(
              deviceName: (args['name'] as String?) ?? 'Device',
              deviceAddress: args['address'] as String?,
            );
          }
          return ChatScreen(deviceName: (args as String?) ?? 'Device');
        },
      },
    );
  }
}
