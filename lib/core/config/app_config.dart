import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/services.dart';

enum Flavor { ezy, magik }

class AppConfig {
  final String appName;
  final String baseUrl;
  final Flavor flavor;
  final String trackingEndpoint;
  final String googleMapsApiKey;

  // Sent in BMS + Login requests (Android sends both).
  final int appTypeId; // 3 = CableDigi
  final int appTypeAutoId; // tenant id: 8 = MagikDigi / KCCL

  static late AppConfig instance;

  // ── Mirror of Android EzyCableDigiConstants (NAMESPACE / NAMESPACE_BMS) ──────
  // Switch environment : comment/uncomment a line.
  // NAMESPACE_BMS — the BMS server. The BMS
  // is a SEPARATE host from the data server (NAMESPACE):
  static const String namespaceBms = 'https://ezybms.itpworld.com/index.php';      // LIVE
  // static const String namespaceBms =
  //     'http://192.168.1.98/ezybms_m8/app/index.php'; // LOCAL (active)
  // static const String namespaceBms = 'http://192.168.1.16/ezybmsys/app/index.php'; // LOCAL alt
  //
  // NAMESPACE — the data server .
  // login_serverUrl defaults to NAMESPACE + "/wsController".
  // static const String namespace = 'https://digi.kccl.tv/index.php';      // LIVE MagikDigi
  // static const String namespace = 'https://digi.ezycable.com/index.php'; // LIVE CloudDigi
  static const String namespace =
      'http://192.168.1.16/testing/ezycabledigi_v2_H8_cloud_live/app/index.php'; // LOCAL (active)
      // static const String namespace = "https://digiv2.kccl.tv/index.php";
  // Device id sent as `imei`.
  // Resolution order:
  //   1) --dart-define=DEVICE_IMEI=…  → optional override for debugging or testing
  //   2) Android native identifier     → API <= 28: TelephonyManager.getDeviceId()
  //                                    API >= 29: Settings.Secure.ANDROID_ID
  //   3) fallback                    → only if native retrieval fails
  static const MethodChannel _deviceIdChannel = MethodChannel('ezy_cable_digi/device_id');
  static String _cachedDeviceImei = '';

  static String get deviceImei {
    if (_cachedDeviceImei.isNotEmpty) return _cachedDeviceImei;
    final overridden = const String.fromEnvironment('DEVICE_IMEI', defaultValue: '');
    if (overridden.isNotEmpty) return overridden;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      debugPrint('AppConfig.deviceImei: native device id not initialized yet');
    }
    return overridden;
  }

  static Future<void> initDeviceImei() async {
    if (_cachedDeviceImei.isNotEmpty) return;

    final overridden = const String.fromEnvironment('DEVICE_IMEI', defaultValue: '');
    if (overridden.isNotEmpty) {
      _cachedDeviceImei = overridden;
      return;
    }

    // Android + iOS both expose the native `getDeviceIdentifier` over the same
    // MethodChannel (Android: ANDROID_ID; iOS: identifierForVendor). Only web /
    // other platforms have no native id — they keep the empty fallback.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      _log('No native device id on this platform.');
      return;
    }

    final maxAttempts = defaultTargetPlatform == TargetPlatform.iOS ? 3 : 1;
    for (var i = 0; i < maxAttempts; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 200));
      try {
        final String? value =
            await _deviceIdChannel.invokeMethod<String>('getDeviceIdentifier');
        if (value != null && value.isNotEmpty) {
          _cachedDeviceImei = value;
          return;
        }
        _log('Device identifier call returned empty.');
      } on MissingPluginException {
        _log('Device id channel not ready (attempt ${i + 1}/$maxAttempts).');
      } on PlatformException catch (e) {
        _log('Device identifier lookup failed: ${e.message}');
        break;
      } catch (e) {
        _log('Device identifier lookup failed: $e');
        break;
      }
    }
  }

  static void _log(String message) {
    if (!kReleaseMode) {
      debugPrint('AppConfig.deviceImei: $message');
    }
  }

  AppConfig({
    required this.appName,
    required this.baseUrl,
    required this.flavor,
    this.trackingEndpoint = '',
    this.googleMapsApiKey = '',
    this.appTypeId = 3,
    required this.appTypeAutoId,
  });
}
