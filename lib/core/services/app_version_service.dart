import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/server_url_resolver.dart';
import '../network/soap_client.dart';

class AppVersionResult {
  final bool forceUpdate;
  final String message;
  const AppVersionResult(this.forceUpdate, this.message);
  static const ok = AppVersionResult(false, '');
}

/// iOS + Android force update via the existing SOAP appVersionCheck.
/// The server's answer alone decides (same as the native Android app).
/// Any error or offline -> ok (never blocks).
class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  /// Version code sent to the server from iOS. Keep it equal to the Android
  /// build number (the `+42` in pubspec.yaml `version: 5.2.0+42`) and update
  /// it on every release.
  static const String serverVersionCode = '42';

  Future<AppVersionResult>? _result;

  /// Runs once per app launch; later calls reuse the same result.
  Future<AppVersionResult> check() => _result ??= _check();

  Future<AppVersionResult> _check() async {
    try {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      final isAndroid = defaultTargetPlatform == TargetPlatform.android;
      if (kIsWeb || (!isIOS && !isAndroid)) {
        return AppVersionResult.ok;
      }
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return AppVersionResult.ok;
      }

      final info = await PackageInfo.fromPlatform();
      final installed = info.version; // e.g. 5.2.0
      // iOS build numbers can't be reused on App Store Connect, so the store
      // build (44, 45, ...) drifts from Android. The server compares the
      // Android code, so iOS sends that instead.
      final build = isIOS ? serverVersionCode : info.buildNumber;
      if (installed.isEmpty || build.isEmpty) return AppVersionResult.ok;

      // 1) Server: is this build current?
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/appVersionCheck',
        methodName: 'appVersionCheck',
        wrapper: 'versionCheck',
        wrapperType: 'appVersionCheckRequest',
        fields: {
          'appVersionName': _serverVersionName(installed),
          'appVersionCode': build,
        },
        timeout: const Duration(seconds: 10),
      );
      if (SoapClient.readField(xml, 'statusCode') != '1') {
        return AppVersionResult.ok;
      }
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';

      return AppVersionResult(
        true,
        message.isNotEmpty
            ? message
            : 'Please update your application to the latest version.',
      );
    } catch (e) {
      debugPrint('AppVersionService: $e');
      return AppVersionResult.ok;
    }
  }

  /// Flutter pads the iOS version to 3 parts (5.2 becomes 5.2.0) but the
  /// server compares the 2-part name, so drop a trailing .0 before sending.
  static String _serverVersionName(String v) {
    final p = v.split('.');
    return (p.length == 3 && p[2] == '0') ? '${p[0]}.${p[1]}' : v;
  }
}
