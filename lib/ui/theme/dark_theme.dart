import 'package:flutter/material.dart';

/// Rapid Mesh Dark Theme
/// 
/// Instagram-inspired dark theme with Material 3.
/// Color Scheme B: Material Dark + Slate Blue accents
/// 
/// Color Palette:
/// - Background: #121212 (Material Dark)
/// - Surface: #1E1E1E (Charcoal)
/// - Primary: #7B68EE (Medium Slate Blue) - Sent bubbles, primary actions
/// - Secondary: #9370DB (Medium Purple) - Accents, highlights
/// - Received Bubble: #2D2D2D (Dark Gray)
/// - Text: #FFFFFF (White)

class AppTheme {
  // Prevent instantiation
  AppTheme._();

  // ==================== COLOR CONSTANTS ====================
  
  /// Primary colors
  static const Color primary = Color(0xFF7B68EE);           // Medium Slate Blue
  static const Color onPrimary = Color(0xFFFFFFFF);          // White on primary
  static const Color primaryContainer = Color(0xFF5A4FCF);   // Darker primary
  
  /// Secondary colors
  static const Color secondary = Color(0xFF9370DB);          // Medium Purple
  static const Color onSecondary = Color(0xFF000000);        // Black on secondary
  
  /// Surface colors
  static const Color background = Color(0xFF121212);         // Main background
  static const Color surface = Color(0xFF1E1E1E);            // Cards, dialogs
  static const Color surfaceVariant = Color(0xFF252525);     // Elevated surfaces
  static const Color onSurface = Color(0xFFFFFFFF);           // Text on surface
  static const Color onSurfaceVariant = Color(0xFFB3B3B3);   // Secondary text
  
  /// Chat bubble colors
  static const Color bubbleSent = Color(0xFF7B68EE);         // Sent message (primary)
  static const Color bubbleReceived = Color(0xFF2D2D2D);    // Received message
  static const Color bubbleSentText = Color(0xFFFFFFFF);
  static const Color bubbleReceivedText = Color(0xFFFFFFFF);
  
  /// Status colors
  static const Color error = Color(0xFFFF5252);              // Error red
  static const Color success = Color(0xFF4CAF50);            // Success green
  static const Color warning = Color(0xFFFFC107);            // Warning amber
  static const Color info = Color(0xFF2196F3);               // Info blue
  
  /// Message status colors
  static const Color statusSending = Color(0xFF666666);      // Gray
  static const Color statusSent = Color(0xFF666666);         // Gray
  static const Color statusDelivered = Color(0xFF4FC3F7);    // Light blue
  static const Color statusRead = Color(0xFF81C784);         // Light green
  static const Color statusFailed = Color(0xFFFF5252);       // Red
  
  /// Border & divider colors
  static const Color border = Color(0xFF3D3D3D);
  static const Color borderLight = Color(0xFF2A2A2A);
  static const Color divider = Color(0xFF2A2A2A);
  
  /// Overlay & scrim
  static const Color overlay = Color(0x80000000);             // 50% black
  static const Color scrim = Color(0xCC000000);              // 80% black

  // ==================== THEME DATA ====================
  
  /// Get the complete dark theme data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // Color scheme
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        surface: surface,
        onSurface: onSurface,
        error: error,
        onError: Color(0xFFFFFFFF),
        background: background,
        onBackground: Color(0xFFFFFFFF),
        
        tertiary: Color(0xFF2D2D2D),
        outline: border,
        outlineVariant: borderLight,
        inverseSurface: primary,
        inversePrimary: Color(0xFF000000),
        surfaceContainerHighest: surfaceVariant,
      ),
      
      // Font family
      fontFamily: 'Inter',
      
      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: const TextStyle(color: Color(0xFF666666)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      
      // Bottom navigation bar theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF666666),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
      
      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      
      // SnackBar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      
      // Divider theme
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      
      // FAB theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 4,
        shape: CircleBorder(),
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        selectedColor: primary.withOpacity(0.2),
        labelStyle: const TextStyle(color: onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      
      // Progress indicator theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: Color(0xFF3D3D3D),
        circularTrackColor: Color(0xFF3D3D3D),
      ),
      
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return const Color(0xFF666666);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withOpacity(0.5);
          }
          return const Color(0xFF3D3D3D);
        }),
      ),
      
      // Checkbox theme
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onPrimary),
        side: const BorderSide(color: border, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      
      // Radio button theme
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return Colors.transparent;
        }),
      ),
      
      // List tile theme
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        minLeadingWidth: 40,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        subtitleTextStyle: TextStyle(
          color: onSurfaceVariant,
          fontSize: 14,
        ),
        leadingAndTrailingTextStyle: TextStyle(
          color: onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      
      // Bottom sheet theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      
      // Popup menu theme
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(color: onSurface),
      ),
      
      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: onSurface),
      ),
      
      // Scaffold background
      scaffoldBackgroundColor: background,
      
      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          color: onSurface,
          letterSpacing: -0.25,
        ),
        displayMedium: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
          color: onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: onSurface,
          letterSpacing: 0.5,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: onSurface,
          letterSpacing: 0.25,
          height: 1.43,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: onSurfaceVariant,
          letterSpacing: 0.4,
          height: 1.33,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: onSurface,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: onSurfaceVariant,
        ),
      ),
      
      // Button themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ==================== CUSTOM WIDGET STYLES ====================
  
  /// Chat bubble decoration for sent messages
  static BoxDecoration sentBubbleDecoration = BoxDecoration(
    color: bubbleSent,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(AppConstants.chatBubbleRadius),
      topRight: Radius.circular(AppConstants.chatBubbleRadius),
      bottomLeft: Radius.circular(AppConstants.chatBubbleRadius),
      bottomRight: Radius.circular(4),
    ),
  );
  
  /// Chat bubble decoration for received messages
  static BoxDecoration receivedBubbleDecoration = BoxDecoration(
    color: bubbleReceived,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(AppConstants.chatBubbleRadius),
      bottomLeft: Radius.circular(AppConstants.chatBubbleRadius),
      bottomRight: Radius.circular(AppConstants.chatBubbleRadius),
    ),
  );
  
  /// Gradient for app header/branding
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7B68EE), // Primary
      Color(0xFF9370DB), // Secondary
    ],
  );
  
  /// Subtle gradient for cards
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1E1E1E),
      Color(0xFF1A1A1A),
    ],
  );

  // ==================== SHADOWS ====================
  
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
  
  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];
}
