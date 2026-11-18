import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

/// Result of `updateCustomerlocation`. Android (MapsFragmentlocupdate
/// onPostExecute :556-620): statusCode 0 = success · 1 = rejected ("No Records
/// Found!" + statusMessage) · 2 = "statusMessage: Contact Support" · no reply →
/// "Server is busy or Un reachable!" (here [statusCode] 3).
class LocationUpdateResult {
  final int statusCode;
  final String statusMessage;
  const LocationUpdateResult(this.statusCode, this.statusMessage);
  bool get isSuccess => statusCode == 0;
}

class CustomerLocationRepository {
  CustomerLocationRepository._();
  static final CustomerLocationRepository instance =
      CustomerLocationRepository._();

  Future<LocationUpdateResult> update({
    required String lcoCustomerId,
    required double latitude,
    required double longitude,
  }) async {
    final url = ServerUrlResolver.instance.loginServerUrl;
    final ns = ServerUrlResolver.instance.namespace;
    if (url.isEmpty || ns.isEmpty) return const LocationUpdateResult(3, '');
    try {
      final xml = await SoapClient.instance.call(
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
        // Android HttpTransportSE(URL, 70000) on mobile data.
        timeout: const Duration(seconds: 70),
      );
      final code = int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '');
      if (code == null) return const LocationUpdateResult(3, '');
      return LocationUpdateResult(
          code, SoapClient.readField(xml, 'statusMessage') ?? '');
    } on SoapException {
      return const LocationUpdateResult(3, '');
    } catch (_) {
      return const LocationUpdateResult(3, '');
    }
  }
}
