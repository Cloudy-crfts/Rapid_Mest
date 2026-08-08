# 📱 Rapid Mesh

<p align="center">
  <strong>Offline P2P Bluetooth Messaging & File Sharing</strong><br>
  <em>No Internet. No Servers. No Logins. Just Direct Device-to-Device Communication.</em>
</p>

---

## ✨ Features

### 🔵 Bluetooth-Powered (Zero Internet Required)
- **BLE 5.0** for device discovery & messaging
- **Classic Bluetooth** for high-speed file transfers (2-3 Mbps)
- **Hybrid transport** — automatic selection based on data type
- **LE 2M PHY + DLE optimization** for maximum throughput

### 💬 Messaging
- **Text messages** with delivery receipts
- **Voice messages** with recording UI
- **Image sharing** from gallery/camera
- **Contact cards** sharing
- **Location sharing**
- **"Delete for me" / "Delete for everyone"** options

### 📁 File Transfer
- **Unlimited file size** support via chunked transfer
- **Pause/Resume** on disconnection
- **SHA-256 integrity verification** per chunk
- **Parallel transfers** to multiple devices
- **Fair bandwidth allocation** across connections

### 🔒 Security & Privacy
- **AES-256-GCM end-to-end encryption** on all data
- **Zero network permissions** — no internet, Wi-Fi, or cellular access
- **Sandboxed storage** — files inaccessible to other apps
- **No servers, no accounts, no tracking**
- **Pure local identity** via nickname only

### ⚡ Performance
- **Thermal monitoring** with aggressive throttling
- **Battery-aware** dynamic speed adjustment
- **Foreground service** with connection count notification
- **Sliding window protocol** with ACK-based reliable transfer

### 🎨 UI/UX
- **Instagram-dark theme** (#121212 background)
- **WhatsApp-style navigation**
- **Smooth animations** and modern design

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Flutter SDK](https://flutter.dev/docs/get-started/install) | 3.x+ | App framework |
| [Android SDK](https://developer.android.com/studio) | API 30+ (Android 11+) | Android platform |
| Git | Latest | Version control |
| Physical Android device | Bluetooth 4.0+ | Testing (emulators have limited BT) |

### Installation Steps

```bash
# 1. Clone this repository
git clone https://github.com/YOUR_USERNAME/rapid-mesh.git
cd rapid-mesh

# 2. Install Flutter dependencies
flutter pub get

# 3. Connect your Android device (USB Debugging ON)
#    Or launch emulator with Bluetooth support

# 4. Build the release APK (the "production" flavor is required)
flutter build apk --release --flavor production

# 5. Find your APK
ls -lh build/app/outputs/flutter-apk/app-production-release.apk
# Size: ~20-50 MB

# 6. Install on device
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Development Mode

```bash
# Run in debug mode (hot reload enabled)
flutter run

# Run on specific device
flutter run -d <device-id>

# View available devices
flutter devices
```

---

## 📱 Download APK

### From GitHub Releases (Recommended)

1. Go to **[Releases](../../releases)** page
2. Download latest `app-production-release.apk`
3. Enable "Install from Unknown Sources" on Android
4. Open the APK file to install

### Building from Source

See [Quick Start](#quick-start) above.

---

## 🏗️ Project Structure

```
lib/
├── main.dart                          # Entry point
│
├── core/
│   ├── bluetooth/
│   │   ├── bluetooth_service.dart     # Main BT orchestrator
│   │   ├── ble_service.dart           # BLE discovery + messaging
│   │   └── classic_bluetooth_service.dart # Large file transfers
│   │
│   ├── protocol/
│   │   ├── packet_definitions.dart    # Packet types & headers
│   │   ├── sliding_window.dart        # ACK-based reliable transfer
│   │   ├── chunk_manager.dart         # File chunking + reassembly
│   │   └── encryption_service.dart    # AES-256-GCM E2E encryption
│   │
│   ├── database/
│   │   ├── app_database.dart          # SQLite setup
│   │   ├── models/                    # Entity classes
│   │   └── daos/                      # Data Access Objects
│   │
│   ├── storage/
│   │   ├── file_storage_service.dart  # Sandboxed file I/O
│   │   └── storage_monitor.dart       # Free space checker
│   │
│   └── monitoring/
│       ├── thermal_service.dart       # Battery/temp monitoring
│       └── bandwidth_allocator.dart   # Fair speed distribution
│
├── ui/
│   ├── screens/
│   │   ├── home_screen.dart           # Chats + Devices tabs
│   │   ├── chat_screen.dart           # Chat interface
│   │   ├── device_scan_screen.dart    # Bluetooth scanner
│   │   └── settings_screen.dart       # App settings
│   │
│   ├── widgets/
│   │   ├── chat_bubble.dart           # Message bubbles
│   │   ├── file_progress_widget.dart  # Transfer progress
│   │   ├── permission_dialog.dart     # Accept/reject dialog
│   │   └── storage_error_dialog.dart  # Storage error popup
│   │
│   └── theme/
│       └── dark_theme.dart            # Instagram-dark palette
│
├── services/
│   └── notification_service.dart      # Connection notifications
│
└── utils/
    ├── constants.dart                 # App constants
    ├── helpers.dart                   # Utility functions
    └── logger.dart                    # Logging system
```

---

## 🔧 Configuration

### Android Permissions (Bluetooth Only!)

The app explicitly **excludes** all network permissions:

```xml
<!-- ✅ ALLOWED: Bluetooth permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- ❌ EXPLICITLY DENIED: No internet/Wi-Fi/cellular -->
<!-- No INTERNET permission -->
<!-- No ACCESS_NETWORK_STATE -->
<!-- No ACCESS_WIFI_STATE -->
<!-- No CHANGE_NETWORK_STATE -->
```

### Color Theme (Option B)

| Element | Color Code | Preview |
|---------|------------|---------|
| Background | `#121212` | ■■■■■ |
| Sent Bubble | `#7B68EE` | ■■■■■ |
| Received Bubble | `#1E1E1E` | ■■■■■ |
| Accent | `#9370DB` | ■■■■■ |

---

## 📊 How It Works

```
┌─────────────┐         BLUETOOTH          ┌─────────────┐
│   DEVICE A  │ ◄═════════════════════ ► │   DEVICE B  │
│             │                           │             │
│  • Scans    │──Scan Request────────▶│  • Advertises│
│  • Connects │◀──Accept/Reject───────│  • Receives  │
│  • Sends    │──Encrypted Chunks───►│  • Receives  │
│  • Receives │◀──Encrypted Chunks────│  • Sends     │
└─────────────┘         P2P            └─────────────┘
        │                                   │
        ▼                                   ▼
┌─────────────┐                     ┌─────────────┐
│ /data/data/ │                     │ /data/data/ │
│ com.rapidmesh│                    │ com.rapidmesh│
│ /received_  │                     │ /received_  │
│   files/    │                     │   files/    │
└─────────────┘                     └─────────────┘
```

### Connection Flow

1. **Device A** opens Rapid Mesh → taps "Scan"
2. **Device B** has Bluetooth visible → appears in scan results
3. **Device A** sends connection request → **Device B** sees popup:
   - Shows sender name
   - Buttons: **[✓ Accept]** or **[✗ Reject]**
4. If rejected → **5-minute cooldown** before retry
5. Once connected → **Bidirectional messaging & file transfer**

---

## 🔒 Security Audit Summary

| Check | Status | Details |
|-------|--------|---------|
| Network Isolation | ✅ PASS | Zero internet/Wi-Fi permissions |
| Encryption | ✅ PASS | AES-256-GCM on all payloads |
| Integrity | ✅ PASS | SHA-256 per chunk + full file hash |
| Sandboxing | ✅ PASS | Files in `/data/data/com.rapidmesh/` |
| No Tracking | ✅ PASS | No analytics, no ads, no servers |
| Message Privacy | ✅ PASS | E2E encrypted, not stored externally |
| Code Obfuscation | ✅ PASS | ProGuard/R8 enabled in release |

> See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for detailed analysis.

---

## 🛠️ Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.x (Dart) |
| Target Platform | Android 11+ (API 30+) |
| Database | SQLite (sqflite package) |
| BLE | flutter_blue_plus |
| Classic BT | flutter_bluetooth_serial |
| Encryption | cryptography (AES-256-GCM) |
| State Management | Provider |
| Background Service | flutter_background_service |

---

## 📋 Requirements for Users

- **Android 11+** (API 30 or higher)
- **Bluetooth 4.0+** (BLE support required)
- **Storage permission** for received files
- **Location permission** (Android requirement for BLE scanning)
- **No internet needed!** 🎉

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⭐ Star This Project!

If you find Rapid Mesh useful, please give it a star! ⭐

---

## 📞 Support

- 📝 **Issues**: [GitHub Issues](../../issues)
- 💬 **Discussions**: [GitHub Discussions](../../discussions)
- 📧 **Email**: your-email@example.com

---

<p align="center">
  <strong>Made with ❤️ for offline privacy</strong><br>
  <em>No servers. No tracking. Just P2P.</em>
</p>
