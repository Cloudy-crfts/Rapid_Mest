import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';

/// Connection Request Dialog
///
/// Shown on the receiver's phone (from anywhere in the app, via the global
/// navigator key) when another Rapid Mesh device sends a connection request.
class ConnectionRequestDialog extends StatelessWidget {
  final String deviceName;
  final String address;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const ConnectionRequestDialog({
    super.key,
    required this.deviceName,
    required this.address,
    required this.onAccept,
    required this.onReject,
  });

  static Future<void> show(
    BuildContext context, {
    required String deviceName,
    required String address,
    required VoidCallback onAccept,
    required VoidCallback onReject,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConnectionRequestDialog(
        deviceName: deviceName,
        address: address,
        onAccept: onAccept,
        onReject: onReject,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(Icons.bluetooth_connected, color: AppTheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Connection Request')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$deviceName" wants to connect with you.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'If you accept, they will be able to:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ...[
            'Send you messages',
            'Share files with you',
          ].map((item) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Text(item),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          Text(
            address,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'If you reject, they cannot try again for 5 minutes.',
                    style: TextStyle(fontSize: 13, color: AppTheme.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: 130,
          height: 48,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              onReject();
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.error, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'REJECT',
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 130,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onAccept();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'ACCEPT',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
