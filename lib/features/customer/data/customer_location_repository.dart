import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

class CustomerLocationRepository {
  CustomerLocationRepository._();
  static final CustomerLocationRepository instance =
      CustomerLocationRepository._();

  Future<bool> update({
    required String lcoCustomerId,
    required double latitude,
    required double longitude,
  }) async {
    final url = ServerUrlResolver.instance.loginServerUrl;
    final ns = ServerUrlResolver.instance.namespace;
    if (url.isEmpty || ns.isEmpty) return false;
    try {
      await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/updateCustomerlocation',
        methodName: 'updateCustomerlocation',
        wrapper: 'updateCustomerlocationInfo',
        wrapperType: 'updateCustomerlocationInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': AppConfig.deviceImei,
          'customerid': int.tryParse(lcoCustomerId) ?? 0,
          'lat': latitude.toString(),
          'lang': longitude.toString(),
        },
      );
      return true;
    } on SoapException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
