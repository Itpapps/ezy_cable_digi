import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'soap_client.dart';

/// Resolves the data-server URL exactly the way the native Android app does.
///
/// Ezy (CloudDigi): native Ezy uses the BMS-returned ipAddress for login and
/// every API (LoginActivity:167-171). EzyStartGate saves it; the getters below
/// return it for Ezy. Everything that follows describes KCCL (MagikDigi):
///

/// POSTs `validateLogin` to `NAMESPACE + "/wsController"` and IGNORES the
/// BMS-returned `ipAddress` for the login URL:
///   • LoginActivity:  login_serverUrl = NAMESPACE + "/wsController"  // static default
///   • LoginActivity: the prefs-override block runs ONLY for non-production
///                       packages, so the production app keeps the static default.
///   • AppVersionCheck stores the BMS ipAddress to prefs, but production
///     LoginActivity never reads it.
/// → login_serverUrl is driven by NAMESPACE (the commentable const in AppConfig),
///   NOT by BMS. We mirror that exactly.
///
/// BMS (resolve()) is still called for registration / logo parity, but it does
/// NOT determine the login URL.
class ServerUrlResolver {
  ServerUrlResolver._();
  static final ServerUrlResolver instance = ServerUrlResolver._();

  static const String _kAppLogoPath = 'app_logo_path';

  static String get _imeiOverride => AppConfig.deviceImei;

  String _appLogoPath = '';

  /// Ezy only: the data-server URL the BMS assigned to this device
  /// (…/wsController), saved by EzyStartGate. Empty → old fixed namespace.
  String _ezyLoginUrl = '';

  /// KCCL: always false, so both getters below return exactly the old values.
  bool get _useEzyBmsUrl =>
      AppConfig.instance.flavor == Flavor.ezy && _ezyLoginUrl.isNotEmpty;

  /// The login URL. KCCL: NAMESPACE + "/wsController" (unchanged).
  /// Ezy: the BMS-given URL (native LoginActivity:169-171).
  String get loginServerUrl => _useEzyBmsUrl
      ? _ezyLoginUrl
      : '${AppConfig.namespace}/wsController';

  /// NAMESPACE (Android: EzyCableDigiConstants.NAMESPACE). Ezy: the BMS URL
  /// without "/wsController", like native.
  String get namespace => _useEzyBmsUrl
      ? _ezyLoginUrl.replaceAll('/wsController', '')
      : AppConfig.namespace;

  String get appLogoPath => _appLogoPath;

  /// Load the cached logo, and for Ezy the saved BMS data-server URL.
  Future<void> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    _appLogoPath = prefs.getString(_kAppLogoPath) ?? _appLogoPath;
    _ezyLoginUrl = prefs.getString(_kEzyLoginUrl) ?? _ezyLoginUrl;
  }

  /// Calls BMS for registration / logo parity (Android: CloudAuth at startup).
  /// Does NOT set the login URL — production Android ignores the BMS ipAddress
  /// for login. Safe to fail (e.g. BMS busy): login_serverUrl is independent.
  Future<bool> resolve() async {
    try {
      final xml = await SoapClient.instance.call(
        url: '${AppConfig.namespaceBms}/validateAuthentication',
        namespace: AppConfig.namespaceBms,
        soapAction: '${AppConfig.namespaceBms}/validateUserAuthentication',
        methodName: 'validateUserAuthentication',
        wrapper: 'userInfo',
        wrapperType: 'validateAuthenticationInfo',
        fields: {
          'smsCode': '',
          'imei': _imeiOverride,
          'appTypeId': AppConfig.instance.appTypeId,
          'appTypeAutoId': AppConfig.instance.appTypeAutoId,
        },
      );
      final statusCode = SoapClient.readField(xml, 'statusCode');
      _appLogoPath = SoapClient.readField(xml, 'appLogoPath') ?? _appLogoPath;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAppLogoPath, _appLogoPath);
      return statusCode == '0';
    } catch (_) {
      return false; // BMS unreachable/busy — login_serverUrl is independent.
    }
  }

  // ── Ezy (CloudDigi) only ─────────────────────────────────────────────────
  // Native Ezy start-up (AppVersionCheck_Activity + CloudAuthentication). KCCL
  // never calls these; it keeps resolve() above exactly as before.
  static const String _kEzyLoginUrl = 'ezy_bms_login_url'; // native "loginurl"
  static const String _kEzyCheckDate = 'ezy_bms_check_date'; // native "SAVEDATE"

  /// One BMS validateUserAuthentication call, exactly as native Ezy sends it:
  /// [smsCode] is empty at start-up (CloudAuth) and the typed registration key
  /// on the registration screen (CloudAuthentication). Never throws: any
  /// failure or unreadable reply is [BmsAuthResult.noReply] (native: response
  /// == null → "Server is busy or unreachable").
  Future<BmsAuthResult> authenticate({String smsCode = ''}) async {
    try {
      final xml = await SoapClient.instance.call(
        url: '${AppConfig.namespaceBms}/validateAuthentication',
        namespace: AppConfig.namespaceBms,
        soapAction: '${AppConfig.namespaceBms}/validateUserAuthentication',
        methodName: 'validateUserAuthentication',
        wrapper: 'userInfo',
        wrapperType: 'validateAuthenticationInfo',
        fields: {
          'smsCode': smsCode,
          'imei': _imeiOverride,
          'appTypeId': AppConfig.instance.appTypeId,
          'appTypeAutoId': AppConfig.instance.appTypeAutoId,
        },
      );
      final code = int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '');
      if (code == null) return const BmsAuthResult.noReply();
      if (code == 0) {
        // Native saves the BMS logo on success (both screens).
        _appLogoPath = SoapClient.readField(xml, 'appLogoPath') ?? _appLogoPath;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAppLogoPath, _appLogoPath);
      }
      return BmsAuthResult(
        code,
        SoapClient.readField(xml, 'statusMessage') ?? '',
        SoapClient.readField(xml, 'ipAddress') ?? '',
      );
    } catch (_) {
      return const BmsAuthResult.noReply();
    }
  }

  /// Native checkDate(): the BMS check runs once per day; true when it already
  /// succeeded today (then native skips the BMS and uses the saved server).
  Future<bool> ezyCheckedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEzyCheckDate) == _today();
  }

  /// Native, on BMS statusCode 0: save the BMS data-server URL (ipAddress) and
  /// today's date. From now on every Ezy API uses this URL (getters above).
  Future<void> saveEzyCheck(String ipAddress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEzyLoginUrl, ipAddress);
    await prefs.setString(_kEzyCheckDate, _today());
    _ezyLoginUrl = ipAddress;
  }

  static String _today() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}'; // native yyyy-MM-dd
  }
}

/// Result of one BMS validateUserAuthentication call (Ezy only).
class BmsAuthResult {
  const BmsAuthResult(this.statusCode, this.statusMessage, this.ipAddress);
  const BmsAuthResult.noReply()
      : statusCode = null,
        statusMessage = '',
        ipAddress = '';

  /// 0 = registered, 1 = not registered, 2+ = other refusal,
  /// null = no reply (server busy / unreachable).
  final int? statusCode;
  final String statusMessage;

  /// The data-server URL the BMS assigns to this device (…/wsController).
  final String ipAddress;
}
