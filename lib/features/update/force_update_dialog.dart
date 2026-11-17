import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';

/// Blocking force-update alert (iOS + Android): cannot be dismissed by tapping
/// outside or Back, and its only button opens the store. Tapping Update keeps
/// the alert up, so returning to the app without updating still blocks.
Future<void> showForceUpdateDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Update Application!'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: _openStore,
            child: const Text('Update'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openStore() async {
  try {
    final Uri url;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Package name follows the build flavor (e.g. com.magik.cable.digi).
      final info = await PackageInfo.fromPlatform();
      url = Uri.parse(
          'https://play.google.com/store/apps/details?id=itp.com.magikdigi');
    } else {
      url = Uri.parse(AppConfig.appStoreUrl);
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('ForceUpdateDialog: $e');
  }
}
