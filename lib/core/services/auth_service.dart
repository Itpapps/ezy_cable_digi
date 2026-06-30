import 'dart:convert';

import 'package:ezi_cable_digi/core/config/app_config.dart';
import 'package:ezi_cable_digi/core/network/rest_client.dart';
import 'package:ezi_cable_digi/core/network/server_url_resolver.dart';
import 'package:ezi_cable_digi/core/network/soap_client.dart';
import 'package:ezi_cable_digi/core/services/error_handler_service.dart';
import 'package:ezi_cable_digi/core/services/offline_mode_service.dart';
import 'package:ezi_cable_digi/core/services/secure_storage_service.dart';
import 'package:ezi_cable_digi/core/services/session_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _authTokenKey = 'auth_token';
  static const String _rememberMeKey = 'remember_me';
  // Remember-Me credentials — Android stores these plaintext in SharedPreferences
  // ("vidslogin": username/password). Flutter keeps the SAME behaviour (prefill
  // on next launch) but in flutter_secure_storage (encrypted) — no plaintext.
  static const String _rememberUserKey = 'remember_username';
  static const String _rememberPassKey = 'remember_password';

  static String get _imei => AppConfig.deviceImei;

  /// Real login against the Digi backend — Android: LoginActivity `validateLogin`.
  /// Reuses the login_serverUrl resolved by BMS (ServerUrlResolver) and the
  /// shared SoapClient. On success it fills SessionService (the Flutter twin of
  /// LoginActivity's static authToken/dealerId/userType).
  Future<LoginResult> login({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    final url = ServerUrlResolver.instance.loginServerUrl; // NAMESPACE + "/wsController" (or BMS override)
    final ns = ServerUrlResolver.instance.namespace;
    if (url.isEmpty || ns.isEmpty) {
      return const LoginResult(false, 'Server not ready. Please restart the app.');
    }

    // Guard: never send an empty IMEI. If the native device id wasn't cached
    // yet (race / earlier failure), (re)initialise it before login.
    var imei = AppConfig.deviceImei;
    if (imei.isEmpty) {
      await AppConfig.initDeviceImei();
      imei = AppConfig.deviceImei;
    }

    try {
      final xml = await SoapClient.instance.call(
        url: url, // login_serverUrl (…/wsController)
        namespace: ns, // login_serverUrl with /wsController removed
        soapAction: '$ns/validateLogin',
        methodName: 'validateLogin',
        wrapper: 'userInfo',
        wrapperType: 'validateLoginInfo',
        fields: {
          'UserName': username,
          'PassWord': password,
          'imei': imei,
          // Android's `login` task leaves these at the int default 0
          // (LoginActivity.java:492-497) — production log confirms 0/0.
          'appTypeId': 0,
          'appTypeAutoId': 0,
          'lat': '0.0',
          'lang': '0.0',
        },
      );

      final status = SoapClient.readField(xml, 'statusCode');
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';

      if (status != '0') {
        return LoginResult(false, message.isEmpty ? 'Login failed' : message);
      }

      // Discount config (Android: enable_payment_discount default 0,
      // max_discount_percent_allowed default 100).
      final enableDiscount =
          int.tryParse(SoapClient.readField(xml, 'enable_payment_discount') ?? '') ?? 0;
      final maxDiscountPct =
          int.tryParse(SoapClient.readField(xml, 'max_discount_percent_allowed') ?? '') ?? 100;

      // Gates the Package Hub's Service Extension tile (validateLogin property,
      // default "0"). Same response parsed for the discount config above.
      final boxWiseExt =
          (SoapClient.readField(xml, 'box_wise_service_extension') ?? '0')
                  .trim() ==
              '1';

      // Offline-mode fields from the same validateLogin response.
      final machineNum =
          (SoapClient.readField(xml, 'machineNumber') ?? '').trim();
      final offlineUserCode =
          (SoapClient.readField(xml, 'offline_user_code') ?? '').trim();
      final offlineStatus =
          int.tryParse(SoapClient.readField(xml, 'offlineStatus') ?? '') ?? 0;
      final restrictPartial = int.tryParse(
              SoapClient.readField(xml, 'lovvalue_restrict_partial_payment') ??
                  '') ??
          0;
      final serverDate =
          (SoapClient.readField(xml, 'current_date') ?? '').trim();
      // use_crf (Android LoginActivity.use_caf): 1 = dealer uses CRF → the CRF
      // row is shown in search results / customer details.
      final useCaf =
          int.tryParse(SoapClient.readField(xml, 'use_crf') ?? '') ?? 0;
      // customerAppSearch (Android LoginActivity.customerAppSearch): comma-separated
      // allowed searchType ids → drives the Search Customer dropdown options.
      final customerAppSearch =
          (SoapClient.readField(xml, 'customerAppSearch') ?? '').trim();
      final employeeName =
          (SoapClient.readField(xml, 'employeeName') ?? '').trim();
      final lastLogin =
          (SoapClient.readField(xml, 'last_login') ?? 'NA').trim();
      final businessName =
          (SoapClient.readField(xml, 'businessName') ?? 'itp').trim();

      SessionService.instance.setFromLogin(
        authToken: SoapClient.readField(xml, 'authToken') ?? '',
        dealerId: SoapClient.readField(xml, 'dealerId') ?? '',
        userType: SoapClient.readField(xml, 'userType') ?? '',
        employeeId: SoapClient.readField(xml, 'employeeId') ?? '',
        enablePaymentDiscount: enableDiscount,
        maxDiscountPercentAllowed: maxDiscountPct,
        boxWiseServiceExtension: boxWiseExt,
        machineNumber: machineNum,
        offlineUserCode: offlineUserCode,
        offlineStatus: offlineStatus,
        restrictPartialPayment: restrictPartial,
        serverCurrentDate: serverDate,
        useCaf: useCaf,
        customerAppSearch: customerAppSearch,
        username: username,
        employeeName: employeeName,
        lastLogin: lastLogin,
        businessName: businessName,
      );

      // Role permissions (getRolePermissions) — needed for the Package Hub gating.
      // Loaded once here; failures keep safe (deny) defaults and never block login.
      await _fetchRolePermissions();

      // Android parity (LoginActivity.java:791-798): on a successful ONLINE login,
      // save credentials if Remember-Me is checked, else clear them. Stored in
      // secure storage (not plaintext prefs) — same behaviour, no security downgrade.
      await _persistRememberMe(
        username: username,
        password: password,
        rememberMe: rememberMe,
      );

      // Android parity (LoginActivity.java:812): persist the server `current_date`
      // for the offline-entry 2-day gate (survives process death).
      await OfflineModeService.instance.saveLastOnlineLoginDate(serverDate);

      return LoginResult(true, message);
    } on SoapException catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace, reason: 'AuthService.login');
      return LoginResult(false, 'Server error (${error.statusCode ?? '-'})');
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace, reason: 'AuthService.login');
      return const LoginResult(false, 'Server is busy or not reachable.');
    }
  }

  /// Fetch role permissions (Android: `getRolePermissions`, key `grp`) and store
  /// the package-operation flags in SessionService. REST form-POST
  /// `dealer_id, imei, authtoken` → `{status_code, status_msg, rolePermission}`
  /// where `rolePermission` is a JSON STRING of `{ name: { permission: "1"/"0" } }`.
  /// Defensive: any failure / missing flag leaves the safe `false` (deny) default.
  Future<void> _fetchRolePermissions() async {
    try {
      final url =
          '${ServerUrlResolver.instance.namespace}/packagelist/getRolePermissions';
      final data = await RestClient.instance.postForm(url, {
        'dealer_id': SessionService.instance.dealerId,
        'imei': _imei,
        'authtoken': SessionService.instance.authToken,
      });
      if ('${data['status_code']}' != '0') return; // keep deny defaults
      final raw = data['rolePermission'];
      final rp = raw is String ? jsonDecode(raw) : raw;
      if (rp is! Map) return;
      bool perm(String key) {
        final node = rp[key];
        return node is Map && '${node['permission']}' == '1';
      }

      SessionService.instance.setRolePermissions(
        packageActivation: perm('package_activation'),
        packageDeactivation: perm('package_deactivation'),
        scheduleService: perm('schedule_service'),
        serviceExtension: perm('service_extension'),
      );
    } catch (_) {
      // keep safe deny defaults (all false)
    }
  }

  Future<bool> loginDemo({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      if (username == 'admin' && password == '123456') {
        final token = 'demo-token-${DateTime.now().millisecondsSinceEpoch}';
        await SecureStorageService.instance.write(_authTokenKey, token);
        if (rememberMe) {
          await SecureStorageService.instance.write(_rememberMeKey, 'true');
        }
        return true;
      }
      return false;
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace, reason: 'AuthService.loginDemo');
      return false;
    }
  }

  Future<String?> loadAuthToken() async {
    return await SecureStorageService.instance.read(_authTokenKey);
  }

  Future<bool> isRemembered() async {
    final value = await SecureStorageService.instance.read(_rememberMeKey);
    return value == 'true';
  }

  /// Save (Remember-Me on) or clear (off) the stored credentials.
  /// Mirrors Android: checked → save username+password; unchecked → clear both.
  Future<void> _persistRememberMe({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    if (rememberMe) {
      await SecureStorageService.instance.write(_rememberMeKey, 'true');
      await SecureStorageService.instance.write(_rememberUserKey, username);
      await SecureStorageService.instance.write(_rememberPassKey, password);
    } else {
      await SecureStorageService.instance.delete(_rememberMeKey);
      await SecureStorageService.instance.delete(_rememberUserKey);
      await SecureStorageService.instance.delete(_rememberPassKey);
    }
  }

  /// Remembered credentials for prefilling the login fields (Android restores
  /// these into the EditTexts on every LoginActivity open). Empty when none saved.
  Future<({String username, String password})> loadRememberedCredentials() async {
    final u = await SecureStorageService.instance.read(_rememberUserKey) ?? '';
    final p = await SecureStorageService.instance.read(_rememberPassKey) ?? '';
    return (username: u, password: p);
  }

  /// Logout — Android parity (MainActivity.java:238-240): clear only the active
  /// session. Remembered credentials, the last-online-login date, and the offline
  /// database are intentionally PRESERVED (Android does not clear them on logout).
  Future<void> logout() async {
    SessionService.instance.clear();
    await SecureStorageService.instance.delete(_authTokenKey);
  }
}

/// Result of a real login attempt: success flag + a user-facing message
/// (the server's statusMessage on failure).
class LoginResult {
  final bool success;
  final String message;
  const LoginResult(this.success, this.message);
}
