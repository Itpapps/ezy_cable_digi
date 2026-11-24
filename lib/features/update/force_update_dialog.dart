import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_colors.dart';

/// Which force-update UI to show. Change [forceUpdateStyle] to switch.
enum ForceUpdateStyle { bottomSheet, fullScreen }

const ForceUpdateStyle forceUpdateStyle = ForceUpdateStyle.fullScreen;

/// Blocking force-update UI (iOS + Android): cannot be dismissed by tapping
/// outside, swiping or Back, and its only button opens the store. Tapping
/// Update keeps it up, so returning to the app without updating still blocks.
///
/// [message] is the server's statusMessage, shown as the description.
Future<void> showForceUpdateDialog(BuildContext context, String message) {
  if (forceUpdateStyle == ForceUpdateStyle.fullScreen) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PopScope(
          canPop: false,
          child: _ForceUpdatePage(message: message),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => PopScope(
      canPop: false,
      child: _ForceUpdateSheet(message: message),
    ),
  );
}

/// The server message, or a default when the server sends none.
String _description(String message) {
  final text = message.trim();
  return text.isNotEmpty
      ? text
      : 'Please update your application to the latest version.';
}

class _UpdateButton extends StatelessWidget {
  const _UpdateButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _openStore,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text(
          'Update now',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Option D: full-screen page, nothing of the login screen behind it.
class _ForceUpdatePage extends StatelessWidget {
  const _ForceUpdatePage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final description = _description(message);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.system_update_rounded,
                              color: AppColors.primary, size: 60),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Update required',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _VersionChip(),
                        const SizedBox(height: 14),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _UpdateButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Option A: rich bottom sheet over the login screen.
class _ForceUpdateSheet extends StatelessWidget {
  const _ForceUpdateSheet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final description = _description(message);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 16),
          const Text(
            'New version available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const _VersionChip(),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const _UpdateButton(),
        ],
      ),
    );
  }
}

/// Shows the installed version, e.g. "Current version 5.1.0".
class _VersionChip extends StatelessWidget {
  const _VersionChip();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final version = snap.data?.version;
        if (version == null || version.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Current version $version',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }
}

Future<void> _openStore() async {
  try {
    final Uri url;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Each flavor opens its own live Play listing, like native
      // (AppVersionCheck_Activity:556-559 uses its own package name).
      // Magik keeps the exact same link as before.
      final playId = AppConfig.instance.flavor == Flavor.ezy
          ? 'com.itp.ezycabledigi.androidapp' // "Ezycabledigi" on Play
          : 'itp.com.magikdigi'; // "MagikSoft - Digi" on Play
      url = Uri.parse(
          'https://play.google.com/store/apps/details?id=$playId');
    } else {
      url = Uri.parse(AppConfig.appStoreUrl);
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('ForceUpdateDialog: $e');
  }
}
