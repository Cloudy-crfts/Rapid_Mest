# ============================================
# Rapid Mesh - ProGuard / R8 rules
# ============================================

# Flutter engine & framework (kept in case the default template rules change)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Rapid Mesh app code
-keep class com.rapidmesh.app.** { *; }

# flutter_local_notifications (uses reflection for scheduled notifications)
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# flutter_bluetooth_serial_plus
-keep class com.angie.flutterbluetoothserialplus.** { *; }

# flutter_blue_plus
-keep class com.boskokg.flutter_blue_plus.** { *; }

# Ignore missing classes referenced by third-party libs
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
