import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/network/server_url_resolver.dart';
import '../../core/services/offline_mode_service.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_goNext());
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final connectivity = await Connectivity().checkConnectivity();
    final noNetwork = connectivity.contains(ConnectivityResult.none);
    if (!mounted) return;

    // Android parity (SplashScreenActivity): with no network, go to the LOGIN
    // screen — not straight to the offline dashboard. The login screen disables
    // the fields, prefills remembered credentials, and applies the 2-day offline
    // gate when the user presses Login.
    if (noNetwork) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
      return;
    }

    // If internet is available, always start in online mode.
    // This prevents "stale" offline flag from showing the offline dashboard first.
    await OfflineModeService.instance.setOfflineMode(false);

    // Resolve the real data-server URL from BMS (Android: CloudAuthentication).
    // On success this stores login_serverUrl, used by Login + every later API.
    try {
      final resolved = await ServerUrlResolver.instance.resolve();
      if (!resolved) {
        // BMS refused / not registered → fall back to the last known URL, if any.
        await ServerUrlResolver.instance.loadCached();
      }
    } catch (_) {
      await ServerUrlResolver.instance.loadCached();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMagik = AppConfig.instance.flavor == Flavor.magik;
    final logoAsset = isMagik
        ? 'assets/mainlogo.png'
        : 'assets/ezy_digi_pics.png';
    final w = MediaQuery.sizeOf(context).width;

    // Android parity (splashscreen.xml): plain white background with the logo
    // centered and large (match_parent width), no text.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          logoAsset,
          width: w * 0.6,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
