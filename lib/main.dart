import 'package:flutter/material.dart';
import 'ui/screens/home_screen.dart';
import 'core/database/app_database.dart';
import 'core/bluetooth/bluetooth_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  await AppDatabase.instance.database;
  
  // Initialize Bluetooth service (does not start scanning automatically)
  final bluetoothService = BluetoothService.instance;
  await bluetoothService.initialize();
  
  runApp(const RapidMeshApp());
}

class RapidMeshApp extends StatelessWidget {
  const RapidMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rapid Mesh',
      debugShowCheckedModeBanner: false,
      
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
        
        // Typography - Inter font family
        fontFamily: 'Inter',
        
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
            fontFamily: 'Inter',
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
        
        // Divider Theme
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2A2A2A),
          thickness: 1,
        ),
        
        // Floating Action Button Theme
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF7B68EE),
          foregroundColor: Color(0xFFFFFFFF),
        ),
        
        // Chip Theme
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2D2D2D),
          selectedColor: const Color(0xFF7B68EE).withOpacity(0.2),
          labelStyle: const TextStyle(color: Color(0xFFFFFFFF)),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        
        // Progress Indicator Theme
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF7B68EE),
          linearTrackColor: Color(0xFF2D2D2D),
        ),
        
        // Switch Theme
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7B68EE);
            }
            return const Color(0xFF666666);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7B68EE).withOpacity(0.5);
            }
            return const Color(0xFF3D3D3D);
          }),
        ),
        
        // Scaffold Background Color
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      
      home: const HomeScreen(),
    );
  }
}
