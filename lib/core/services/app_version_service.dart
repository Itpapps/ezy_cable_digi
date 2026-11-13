import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../network/server_url_resolver.dart';
import '../network/soap_client.dart';

class AppVersionResult {
  final bool forceUpdate;
  final String message;
  const AppVersionResult(this.forceUpdate, this.message);
  static const ok = AppVersionResult(false, '');
}

/// iOS force update via the existing SOAP appVersionCheck.
/// Force only when the server says update AND the App Store really has a
/// newer version. Any error or offline -> ok (never blocks the user).
class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  Future<AppVersionResult>? _result;

  /// Runs once per app launch; later calls reuse the same result.
  Future<AppVersionResult> check() => _result ??= _check();

  Future<AppVersionResult> _check() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        return AppVersionResult.ok;
      }
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return AppVersionResult.ok;
      }

      final info = await PackageInfo.fromPlatform();
      final installed = info.version; // e.g. 5.2.0
      final build = info.buildNumber; // e.g. 43
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

      // 2) App Store: is a newer version really live?
      final res = await http
          .get(Uri.parse(
              'https://itunes.apple.com/lookup?id=${AppConfig.appStoreId}&country=in'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return AppVersionResult.ok;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? const <dynamic>[];
      if (results.isEmpty) return AppVersionResult.ok;
      final storeVersion =
          '${(results.first as Map<String, dynamic>)['version'] ?? ''}';
      if (!_isNewer(storeVersion, installed)) return AppVersionResult.ok;

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

  /// true if [store] is newer than [installed], compared as numbers.
  static bool _isNewer(String store, String installed) {
    final a = store.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final b = installed.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
