import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

/// One `invoice_details` row from the `InvoiceService` SOAP response.
/// Field names mirror Android's `Invoiceresult` parsing.
class InvoiceRecord {
  final String billingId;
  final String billDate;
  final String dueDate;
  final String billNo;
  final String billAmount;
  final String taxAmount;
  final String pendingAmount;
  final String totalAmount;
  final String packageName;

  const InvoiceRecord({
    required this.billingId,
    required this.billDate,
    required this.dueDate,
    required this.billNo,
    required this.billAmount,
    required this.taxAmount,
    required this.pendingAmount,
    required this.totalAmount,
    required this.packageName,
  });
}

/// Result of `InvoiceService`. `statusCode`: 0 = ok · 1 = no records (show
/// message) · 3 = transport failure.
class InvoiceHistoryResult {
  final int statusCode;
  final String statusMessage;
  final List<InvoiceRecord> invoices;
  const InvoiceHistoryResult(
      this.statusCode, this.statusMessage, this.invoices);
}

/// Invoice History — SOAP `InvoiceService` (Android `InvoiceHistory`).
/// Wrapper `activSerInfo`/`InvoiceService`, fields `authToken, customer_id,
/// dealer_id, imei`. Response = repeated `invoice_details` + `statusCode`/
/// `statusMessage`. Defensive; never throws to the UI.
class InvoiceHistoryRepository {
  InvoiceHistoryRepository._();
  static final InvoiceHistoryRepository instance =
      InvoiceHistoryRepository._();

  static String get _imei => AppConfig.deviceImei;

  Future<InvoiceHistoryResult> fetch(String customerId) async {
    final ns = ServerUrlResolver.instance.namespace;
    final url = ServerUrlResolver.instance.loginServerUrl;
    if (ns.isEmpty || url.isEmpty) {
      return const InvoiceHistoryResult(3, 'Server not ready.', []);
    }
    try {
      final xml = await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/InvoiceService',
        methodName: 'InvoiceService',
        wrapper: 'activSerInfo',
        wrapperType: 'InvoiceService',
        fields: {
          'authToken': SessionService.instance.authToken,
          'customer_id': customerId,
          'dealer_id': SessionService.instance.dealerId,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '0') ?? 0;
      final msg = SoapClient.readField(xml, 'statusMessage') ?? '';
      final invoices = <InvoiceRecord>[];
      for (final it in SoapClient.readAll(xml, 'invoice_details')) {
        // Android strips the word "Package" from package_name.
        final pkg = (SoapClient.readField(it, 'package_name') ?? '')
            .replaceAll('Package', '');
        invoices.add(InvoiceRecord(
          billingId: SoapClient.readField(it, 'billing_id') ?? '',
          billDate: SoapClient.readField(it, 'bill_date') ?? '',
          dueDate: SoapClient.readField(it, 'due_date') ?? '',
          billNo: SoapClient.readField(it, 'bill_no') ?? '',
          billAmount: SoapClient.readField(it, 'bill_amount') ?? '',
          taxAmount: SoapClient.readField(it, 'tax_amount') ?? '',
          pendingAmount: SoapClient.readField(it, 'pending_amount') ?? '',
          totalAmount: SoapClient.readField(it, 'total_amount') ?? '',
          packageName: pkg,
        ));
      }
      return InvoiceHistoryResult(status, msg, invoices);
    } on SoapException {
      return const InvoiceHistoryResult(3, 'Server error.', []);
    } catch (_) {
      return const InvoiceHistoryResult(3, 'Could not connect to server.', []);
    }
  }
}
