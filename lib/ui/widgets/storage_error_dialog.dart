import 'package:flutter/material.dart';
import '../../utils/helpers.dart';
import '../theme/dark_theme.dart';

/// No Enough Storage Dialog
/// 
/// Shows when there's insufficient storage to receive a file.
/// Exact specification from user:
/// - Message: "no enough storage in your device"
/// - Single "OK" button centered at bottom
/// 
/// Layout:
/// ┌─────────────────────────────┐
│                             │
│      ⚠️  (Warning Icon)       │
│                             │
│  no enough storage in your  │
│  device                     │
│                             │
│          [ OK ]             │
└─────────────────────────────┘

class StorageErrorDialog extends StatelessWidget {
  final String? message;
  final long? requiredSpace;
  final long? availableSpace;
  final VoidCallback? onOk;

  const StorageErrorDialog({
    super.key,
    this.message,
    this.requiredSpace,
    this.availableSpace,
    this.onOk,
  });

  /// Show the dialog with exact user-specified message
  static Future<void> show({
    required BuildContext context,
    long? requiredSpace,
    long? availableSpace,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StorageErrorDialog(
        requiredSpace: requiredSpace,
        availableSpace: availableSpace,
        onOk: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: AppTheme.error,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // EXACT MESSAGE AS SPECIFIED BY USER
            Text(
              'no enough storage in your device',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Optional: Show space details if provided
            if (requiredSpace != null && availableSpace != null) ...[
              const SizedBox(height: 20),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildSpaceRow('Needed', requiredSpace!, AppTheme.error),
                    const SizedBox(height: 8),
                    _buildSpaceRow('Available', availableSpace!, AppTheme.warning),
                    const SizedBox(height: 8),
                    Divider(color: AppTheme.borderLight),
                    const SizedBox(height: 8),
                    _buildSpaceRow(
                      'Shortage', 
                      (requiredSpace! - availableSpace!).abs(), 
                      AppTheme.error,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // OK BUTTON CENTERED AT BOTTOM (as specified)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onOk ?? () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a space information row
  Widget _buildSpaceRow(String label, long bytes, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isBold ? color : AppTheme.onSurfaceVariant,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          Helpers.formatFileSize(bytes),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
