import 'dart:convert';

import 'package:ezy_cable_digi/core/config/app_config.dart';
import 'package:ezy_cable_digi/core/network/rest_client.dart';
import 'package:ezy_cable_digi/core/network/server_url_resolver.dart';
import 'package:ezy_cable_digi/core/network/soap_client.dart';
import 'package:ezy_cable_digi/core/services/error_handler_service.dart';
import 'package:ezy_cable_digi/core/services/offline_mode_service.dart';
import 'package:ezy_cable_digi/core/services/secure_storage_service.dart';
import 'package:ezy_cable_digi/core/services/session_service.dart';

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
    // Device last-known location, captured by the login UI (Android parity:
    // GPSTracker → userInfo.lat/lang). Defaults to 0.0/0.0 when unavailable so
    // existing callers and location-failure paths behave exactly as before.
    double lat = 0.0,
    double lang = 0.0,
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
          'lat': lat.toString(),
          'lang': lang.toString(),
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
      // send_sms (Android LoginActivity.send_sms): 1 = pre-check the payment-SMS
      // box so a receipt SMS is sent by default. Default 0 (off) — safe-fails to
      // today's behaviour if the field is absent.
      final sendSms =
          int.tryParse(SoapClient.readField(xml, 'send_sms') ?? '') ?? 0;
      // CRF prefixes for Search-by-CRF (Android LoginActivity.userCode from
      // `usercode=`). Empty → CRF search keeps the single full-number field.
      final userCode = (SoapClient.readField(xml, 'usercode') ?? '').trim();
      final crfPrefixes = userCode.isEmpty
          ? const <String>[]
          : userCode
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

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
      // D-B6: Android LoginActivity :633-637 (missing/unparsable → 0).
      final commonEmployee = int.tryParse(
              (SoapClient.readField(xml, 'common_employee') ?? '').trim()) ??
          0;
      final restrictPartial = int.tryParse(
              SoapClient.readField(xml, 'lovvalue_restrict_partial_payment') ??
                  '') ??
          0;
      // A-B4: dealer amount rounding (Android LoginActivity :645-651; missing →
      // "ACTUAL"). Server: wsmodel checkAmountRound → lovtable AMOUNT_ROUND.
      final amountRound =
          (SoapClient.readField(xml, 'amount_round') ?? 'ACTUAL').trim();
      // useLcoDeposit (Android LoginActivity.userLcoDeposit): 1 = LCO-deposit dealer
      // → lock STB amount to full + show wallet card. Default 0 (feature off).
      final useLcoDeposit =
          int.tryParse(SoapClient.readField(xml, 'useLcoDeposit') ?? '') ?? 0;
      // show_custom_packages (Android LoginActivity, int 0/1) → Custom Packages
      // tile in Customer Operations. Default 0 (hidden).
      final showCustomPackages =
          (SoapClient.readField(xml, 'show_custom_packages') ?? '0').trim() ==
              '1';
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
        sendSms: sendSms,
        crfPrefixes: crfPrefixes,
        boxWiseServiceExtension: boxWiseExt,
        machineNumber: machineNum,
        offlineUserCode: offlineUserCode,
        offlineStatus: offlineStatus,
        commonEmployee: commonEmployee,
        restrictPartialPayment: restrictPartial,
        amountRound: amountRound,
        useLcoDeposit: useLcoDeposit,
        serverCurrentDate: serverDate,
        useCaf: useCaf,
        customerAppSearch: customerAppSearch,
        showCustomPackages: showCustomPackages,
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

      // D-B6 / Android LoginActivity :800-803 + Commonempcrf() :951-1020: a
      // common employee enters the app ONLY after packagelist/commonEmpCRF
      // succeeds, and its lco_code list is their CRF prefix list (Android uses
      // LoginActivity.crfs instead of userCode for them). Remember-Me is already
      // saved above, as Android does before this branch; the offline-entry date
      // below is saved only on success, as in Android's success branch.
      if (commonEmployee == 1) {
        final gate = await _fetchCommonEmployeeCrf();
        if (gate.status != 0) {
          // Android stays on the login screen; also drop the half-filled
          // session so nothing (e.g. offline "Back to online") can use it.
          SessionService.instance.clear();
          if (gate.status == 1) {
            return LoginResult(false, gate.message,
                dialogTitle: 'No employee details found !');
          }
          return const LoginResult(false, 'Failed.'); // Android Toast "Failed."
        }
        SessionService.instance.crfPrefixes = gate.crfs;
      }

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

  /// D-B6 / Android LoginActivity.Commonempcrf() (:951-1020): REST POST
  /// `packagelist/commonEmpCRF` (dealer_id, imei, authtoken), 100 s like
  /// Android's retry policy. status 0 → the `result` lco_code list; status 1 →
  /// Android's "No employee details found !" dialog; anything else (transport
  /// error, other status) → status 3. Never throws.
  Future<({int status, String message, List<String> crfs})>
      _fetchCommonEmployeeCrf() async {
    try {
      final data = await RestClient.instance.postForm(
        '${ServerUrlResolver.instance.namespace}/packagelist/commonEmpCRF',
        {
          'dealer_id': SessionService.instance.dealerId,
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 100),
      );
      final status = int.tryParse('${data['status_code']}'.trim()) ?? 3;
      final message = '${data['status_msg'] ?? ''}';
      if (status == 1) return (status: 1, message: message, crfs: const <String>[]);
      if (status != 0) return (status: 3, message: message, crfs: const <String>[]);
      final raw = data['result'];
      final list = raw is String ? jsonDecode(raw) : raw;
      final crfs = <String>[];
      if (list is List) {
        for (final e in list) {
          if (e is Map) {
            final code = '${e['lco_code'] ?? ''}'.trim();
            if (code.isNotEmpty) crfs.add(code);
          }
        }
      }
      return (status: 0, message: message, crfs: crfs);
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'AuthService.commonEmpCRF');
      return (status: 3, message: '', crfs: const <String>[]);
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

      // Android blocks Make Payment only on an explicit make_payment=="0"
      // (default allow). Distinct from the deny-default perms above.
      final mpNode = rp['make_payment'];
      final makePaymentAllowed =
          !(mpNode is Map && '${mpNode['permission']}' == '0');

      // share_option (Android default "1"; hide Share icon only on explicit "0").
      final soNode = rp['share_option'];
      final shareOption = !(soNode is Map && '${soNode['permission']}' == '0');

      SessionService.instance.setRolePermissions(
        packageActivation: perm('package_activation'),
        packageDeactivation: perm('package_deactivation'),
        scheduleService: perm('schedule_service'),
        serviceExtension: perm('service_extension'),
        // Customer Operations grid flags (Android reads these same keys).
        renew: perm('renew'),
        onetimeCharges: perm('onetime_charges'),
        unpaidCustomerDeactivation: perm('unpaid_customer_deactivation'),
        unpaidCustomerActivation: perm('unpaid_customer_activation'),
        makePaymentAllowed: makePaymentAllowed,
        shareOption: shareOption,
        // A-B2: Android customer_discount (deny unless "1", LoginActivity :1083).
        customerDiscount: perm('customer_discount'),
        // D-B3: Android addexpense (deny unless "1", LoginActivity :1126).
        addExpense: perm('expenses'),
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
  // D-B6: when set, the login screen shows [message] in a dialog with this
  // title (Android's non-cancellable AlertDialog) instead of a snackbar.
  final String? dialogTitle;
  const LoginResult(this.success, this.message, {this.dialogTitle});
}
