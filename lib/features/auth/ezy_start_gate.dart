import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/server_url_resolver.dart';
import 'device_registration_screen.dart';
import 'ezy_alert_dialog.dart';
import 'login_screen.dart';

/// Ezy (CloudDigi) start-up — the native Ezy flow
/// (SplashScreenActivity → AppVersionCheck_Activity.CloudAuth). KCCL never
/// opens this screen; it starts on LoginScreen exactly as before.
///
///  • no internet              → login (native splash: offline → LoginActivity)
///  • BMS already OK today      → login (native checkDate())
///  • BMS 0  (registered)       → save server URL + date + logo → login
///  • BMS 1  (not registered)   → "Authorization Failed !" → registration screen
///  • BMS 2+                    → "Authorization Failed!" (stays here, as native)
///  • no reply                  → "Server connectivity error!" → app closes
class EzyStartGate extends StatefulWidget {
  const EzyStartGate({super.key});

  @override
  State<EzyStartGate> createState() => _EzyStartGateState();
}

class _EzyStartGateState extends State<EzyStartGate> {
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    // Load the saved BMS server URL first, so every path below (offline,
    // already-checked-today) reaches login with the right Ezy server.
    await ServerUrlResolver.instance.loadCached();
    if (!mounted) return;
    final connectivity = await Connectivity().checkConnectivity();
    if (!mounted) return;
    if (connectivity.contains(ConnectivityResult.none)) {
      _openLogin();
      return;
    }

    if (await ServerUrlResolver.instance.ezyCheckedToday()) {
      if (mounted) _openLogin();
      return;
    }

    final r = await ServerUrlResolver.instance.authenticate();
    if (!mounted) return;
    final code = r.statusCode;

    if (code == 0) {
      await ServerUrlResolver.instance.saveEzyCheck(r.ipAddress);
      if (mounted) _openLogin();
      return;
    }

    setState(() => _busy = false);

    if (code == 1) {
      // Native AppVersionCheck_Activity:305-329 (non-cancellable).
      await _showDialog(
        title: 'Authorization Failed !',
        message:
            '${r.statusMessage}. You are not authorized to use this application.',
        dismissible: false,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
            builder: (_) => const DeviceRegistrationScreen()),
      );
      return;
    }

    if (code != null) {
      // Native :330-347 — non-cancellable; OK only closes the dialog and the
      // app stays on this screen.
      await _showDialog(
        title: 'Authorization Failed!',
        message: '${r.statusMessage}. You are not authorized to use this '
            'application. Please check your details and login again.',
        dismissible: false,
        icon: Icons.gpp_bad_rounded,
      );
      return;
    }

    // No reply. Native :354-371 — OK closes the app (finish()).
    final ok = await _showDialog(
      title: 'Server connectivity error!',
      message: 'Server is busy or unreachable. Please try again after sometime',
      dismissible: true,
      type: EzyAlertType.warning,
      icon: Icons.cloud_off_rounded,
    );
    if (ok) await SystemNavigator.pop();
  }

  void _openLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  /// Returns true when OK was pressed (false if dismissed outside / X).
  Future<bool> _showDialog({
    required String title,
    required String message,
    required bool dismissible,
    EzyAlertType type = EzyAlertType.error,
    IconData? icon,
  }) {
    return showEzyAlert(
      context,
      title: title,
      message: message,
      type: type,
      icon: icon,
      dismissible: dismissible,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/ezy_digi_pics.png',
              // Medium size: ~42% of the width, never tiny or huge.
              width: (w * 0.42).clamp(150.0, 230.0),
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: _busy
                  ? const CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.primary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
