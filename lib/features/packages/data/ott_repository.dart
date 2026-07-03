import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// OTT credential change — Android parity (`OTTAdapter.gethitapiaddott`).
/// Encrypted REST (`/digi_rest_api/...`): `ott_change_username` / `ott_change_password`.
/// Returns statusCode 0 = success (status_message) · 1 = backend error
/// (Error_Message) · 3 = transport. Never throws.
class OttRepository {
  OttRepository._();
  static final OttRepository instance = OttRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

  Future<({int statusCode, String message})> changeUsername({
    required String boxId,
    required String username,
  }) =>
      _change(
          method: 'ott_change_username',
          boxId: boxId,
          key: 'username',
          value: username);

  Future<({int statusCode, String message})> changePassword({
    required String boxId,
    required String password,
  }) =>
      _change(
          method: 'ott_change_password',
          boxId: boxId,
          key: 'password',
          value: password);

  Future<({int statusCode, String message})> _change({
    required String method,
    required String boxId,
    required String key,
    required String value,
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url(method),
        {
          key: value,
          'selected_stb': boxId,
          'dealer_id': SessionService.instance.dealerId,
          'employee_id': SessionService.instance.employeeId,
          'request_from': 'FromDigiApp',
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return (statusCode: 1, message: '${data['Error_Message'] ?? 'Failed'}');
      }
      return (statusCode: 0, message: '${data['status_message'] ?? 'Success'}');
    } on TimeoutException {
      return (statusCode: 3, message: 'Request timed out.');
    } catch (_) {
      return (statusCode: 3, message: 'Could not connect to server.');
    }
  }
}
