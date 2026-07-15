import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'data/login_notification.dart';

/// The login-notification popup (blue title bar, scrollable body, single blue
/// OK). Overflow-proof: ConstrainedBox caps the height; Flexible +
/// SingleChildScrollView let a long body scroll instead of overflowing.
class LoginNotificationDialog extends StatelessWidget {
  final LoginNotification notification;
  const LoginNotificationDialog({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Blue title bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: AppColors.primary,
              child: Text(
                notification.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  notification.body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            // Single blue OK button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
