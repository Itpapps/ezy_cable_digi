import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

/// Result of the dashboard KPI call (`dashBoardDetails`).
///
/// Android (`DashboardHomeFragment.DashboardDetails`) parses these `key=value;`
/// pairs from the SOAP response. Every numeric field is parsed defensively and
/// defaults to 0 — a missing field must never break the others (Android wraps
/// each field in its own try/catch). See server docs/DASHBOARD_FLOW.md §2.1.
class DashboardKpiResult {
  final int statusCode; // 0 = ok; 1 = no details; 2 = error; 3 = null/unreachable
  final String statusMessage;
  final double outstandingAmount;       // outStandingAmount  → "Due Amount"
  final double billAmount;              // billAmount         → "Month Billing"
  final double collectionAmount;        // collectionAmount   → "Collections" (dealer)
  final double employeeCollectionAmount;// employeeCollectionAmount → "Collections" (employee)
  final double onetimeChargeAmount;     // onetimeChargeAmount→ "Onetime Charges"

  const DashboardKpiResult({
    required this.statusCode,
    required this.statusMessage,
    required this.outstandingAmount,
    required this.billAmount,
    required this.collectionAmount,
    required this.employeeCollectionAmount,
    required this.onetimeChargeAmount,
  });

  bool get isSuccess => statusCode == 0;
}

/// Dashboard KPI cards (config key `dbd`).
/// Android: `dashBoardDetails`, wrapper `dashInfo` (i:type `dashBoard`),
/// request fields `authToken` + `imei`. SOAP timeout 70s when online.
class DashboardRepository {
  DashboardRepository._();
  static final DashboardRepository instance = DashboardRepository._();

  static String get _imei => AppConfig.deviceImei;

  Future<DashboardKpiResult> fetchKpis() async {
    final ns = ServerUrlResolver.instance.namespace;
    final xml = await SoapClient.instance.call(
      url: ServerUrlResolver.instance.loginServerUrl,
      namespace: ns,
      soapAction: '$ns/dashBoardDetails',
      methodName: 'dashBoardDetails',
      wrapper: 'dashInfo',
      wrapperType: 'dashBoard',
      fields: {
        'authToken': SessionService.instance.authToken,
        'imei': _imei,
      },
      timeout: const Duration(seconds: 70), // Android: 70000ms when connected
    );

    double num(String field) =>
        double.tryParse(SoapClient.readField(xml, field) ?? '') ?? 0.0;

    final status =
        int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
    final message = SoapClient.readField(xml, 'statusMessage') ?? '';

    return DashboardKpiResult(
      statusCode: status,
      statusMessage: message,
      outstandingAmount: num('outStandingAmount'),
      billAmount: num('billAmount'),
      collectionAmount: num('collectionAmount'),
      employeeCollectionAmount: num('employeeCollectionAmount'),
      onetimeChargeAmount: num('onetimeChargeAmount'),
    );
  }
}
