import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

/// Result of a change-password attempt. statusCode: 0 = ok · 1/2 = server-side
/// reject (message shown) · 3 = transport/not-ready.
class ChangePasswordResult {
  final int statusCode;
  final String statusMessage;
  const ChangePasswordResult(this.statusCode, this.statusMessage);
  bool get success => statusCode == 0;
}

/// Change Password — Android parity (UserProfile_ChangePsw_Fragment, SOAP
/// `passwordChange`). Wrapper `passInfo`, fields authToken/oldPassword/
/// newPassword/imei. Reuses the shared [SoapClient]; never logs passwords.
class ChangePasswordRepository {
  ChangePasswordRepository._();
  static final ChangePasswordRepository instance = ChangePasswordRepository._();

  Future<ChangePasswordResult> change({
    required String oldPassword,
    required String newPassword,
  }) async {
    final url = ServerUrlResolver.instance.loginServerUrl;
    final ns = ServerUrlResolver.instance.namespace;
    if (url.isEmpty || ns.isEmpty) {
      return const ChangePasswordResult(3, 'Server not ready. Please restart the app.');
    }
    try {
      final xml = await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/passwordChange',
        methodName: 'passwordChange',
        wrapper: 'passInfo',
        wrapperType: 'passwordChange',
        fields: {
          'authToken': SessionService.instance.authToken,
          'oldPassword': oldPassword,
          'newPassword': newPassword,
          'imei': AppConfig.deviceImei,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      final msg = SoapClient.readField(xml, 'statusMessage') ?? '';
      return ChangePasswordResult(status, msg);
    } on SoapException {
      return const ChangePasswordResult(3, 'Server is busy or not reachable.');
    } catch (_) {
      return const ChangePasswordResult(3, 'Could not connect to server.');
    }
  }
}
