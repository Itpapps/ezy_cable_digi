import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';
import 'employee_collection.dart';

class EmployeeCollectionsResult {
  final int statusCode; // 0 ok · 1 server error · 3 transport
  final String statusMessage;
  final List<EmployeeCollection> items;
  const EmployeeCollectionsResult(
      this.statusCode, this.statusMessage, this.items);
}

/// Employee Track (collection report) — SOAP `empCollection` (Android
/// EmployeeTrackFragment). Wrapper `collectInfo`/`checkCollectionInfo`, fields
/// `authToken, fromDate, toDate, imei` (dates `yyyy-MM-dd`). Response = repeated
/// `collectionResult` + `statusCode`/`statusMessage`. Defensive; never throws.
class EmployeeTrackRepository {
  EmployeeTrackRepository._();
  static final EmployeeTrackRepository instance = EmployeeTrackRepository._();

  static String get _imei => AppConfig.deviceImei;

  Future<EmployeeCollectionsResult> getCollections({
    required String fromDate, // yyyy-MM-dd
    required String toDate,
  }) async {
    final ns = ServerUrlResolver.instance.namespace;
    final url = ServerUrlResolver.instance.loginServerUrl;
    if (ns.isEmpty || url.isEmpty) {
      return const EmployeeCollectionsResult(3, 'Server not ready.', []);
    }
    try {
      final xml = await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/empCollection',
        methodName: 'empCollection',
        wrapper: 'collectInfo',
        wrapperType: 'checkCollectionInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'fromDate': fromDate,
          'toDate': toDate,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '0') ?? 0;
      final msg = SoapClient.readField(xml, 'statusMessage') ?? '';
      final items = <EmployeeCollection>[];
      for (final it in SoapClient.readAll(xml, 'collectionResult')) {
        items.add(EmployeeCollection(
          employeeId: SoapClient.readField(it, 'employee_id') ?? '',
          name: SoapClient.readField(it, 'name') ?? '',
          dealerName: SoapClient.readField(it, 'dealer_name') ?? '',
          dealerId: SoapClient.readField(it, 'dealer_id') ?? '',
          amount: SoapClient.readField(it, 'Amt') ?? '',
        ));
      }
      return EmployeeCollectionsResult(status, msg, items);
    } on SoapException {
      return const EmployeeCollectionsResult(3, 'Server error.', []);
    } catch (_) {
      return const EmployeeCollectionsResult(
          3, 'Could not connect to server.', []);
    }
  }
}
