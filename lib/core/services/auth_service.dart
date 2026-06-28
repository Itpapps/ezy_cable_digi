import 'dart:convert';

import 'package:ezi_cable_digi/core/config/app_config.dart';
import 'package:ezi_cable_digi/core/network/rest_client.dart';
import 'package:ezi_cable_digi/core/network/server_url_resolver.dart';
import 'package:ezi_cable_digi/core/network/soap_client.dart';
import 'package:ezi_cable_digi/core/services/error_handler_service.dart';
import 'package:ezi_cable_digi/core/services/secure_storage_service.dart';
import 'package:ezi_cable_digi/core/services/session_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _authTokenKey = 'auth_token';
  static const String _rememberMeKey = 'remember_me';

  static String get _imei => AppConfig.deviceImei;

  /// Real login against the Digi backend — Android: LoginActivity `validateLogin`.
  /// Reuses the login_serverUrl resolved by BMS (ServerUrlResolver) and the
  /// shared SoapClient. On success it fills SessionService (the Flutter twin of
  /// LoginActivity's static authToken/dealerId/userType).
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final url = ServerUrlResolver.instance.loginServerUrl; // NAMESPACE + "/wsController" (or BMS override)
    final ns = ServerUrlResolver.instance.namespace;
    if (url.isEmpty || ns.isEmpty) {
      return const LoginResult(false, 'Server not ready. Please restart the app.');
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
          'imei': _imei,
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
        username: username,
        employeeName: employeeName,
        lastLogin: lastLogin,
        businessName: businessName,
      );

      // Role permissions (getRolePermissions) — needed for the Package Hub gating.
      // Loaded once here; failures keep safe (deny) defaults and never block login.
      await _fetchRolePermissions();

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

  Future<void> logout() async {
    SessionService.instance.clear();
    await SecureStorageService.instance.delete(_authTokenKey);
    await SecureStorageService.instance.delete(_rememberMeKey);
  }
}

/// Result of a real login attempt: success flag + a user-facing message
/// (the server's statusMessage on failure).
class LoginResult {
  final bool success;
  final String message;
  const LoginResult(this.success, this.message);
}
