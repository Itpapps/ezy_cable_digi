import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

// Typed result so the caller knows success (statusCode) AND the value (amount).
class PendingAmountResult {
  final int statusCode; // 0 = ok
  final String statusMessage;
  final double pendingAmount; // overall total due (cable + broadcaster) — display only
  final int billingId;        // bill to settle — passed to mpay (verified: from GPA)
  final double cablePendingAmount;       // STB/cable leg — the STB amount + due_amount for mpay
  final double broadcasterPendingAmount; // broadband pending (0 for STB-only)
  final double lastPaidAmount;           // Android last_paid_amount (from GPA :1459)
  const PendingAmountResult(this.statusCode, this.statusMessage,
      this.pendingAmount, this.billingId, this.cablePendingAmount,
      this.broadcasterPendingAmount, [this.lastPaidAmount = 0.0]);
}

/// Get Pending Amount (config key `gpa`).
/// Android: getPendingAmount, wrapper `pendingAmountInfo` (i:type getPendingAmountInfo).
class PendingAmountRepository {
  PendingAmountRepository._();
  static final PendingAmountRepository instance = PendingAmountRepository._();

  static String get _imei => AppConfig.deviceImei;

  /// [altCustomerId] = the customer's customer_id (NOT alt_cust_id — Android :1186/:1331).
  Future<PendingAmountResult> fetch(int altCustomerId) async {
    final ns = ServerUrlResolver.instance.namespace;
    final xml = await SoapClient.instance.call(
      url: ServerUrlResolver.instance.loginServerUrl,
      namespace: ns,
      soapAction: '$ns/getPendingAmount',
      methodName: 'getPendingAmount',
      wrapper: 'pendingAmountInfo',
      wrapperType: 'getPendingAmountInfo',
      fields: {
        'altCustomerId': altCustomerId,
        'authToken': SessionService.instance.authToken,
        'imei': _imei,
      },
    );
    final status =
        int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
    final message = SoapClient.readField(xml, 'statusMessage') ?? '';
    final pending =
        double.tryParse(SoapClient.readField(xml, 'pendingAmount') ?? '') ?? 0.0;
    final billingId =
        int.tryParse(SoapClient.readField(xml, 'billingId') ?? '') ?? 0;
    // STB/cable leg (Android: cable_pending_amount) — the value Android prefills
    // into the STB amount box and sends as due_amount. Defaults to the overall
    // pending when absent so STB-only customers are unaffected.
    final cablePending = double.tryParse(
            SoapClient.readField(xml, 'cable_pending_amount') ?? '') ??
        pending;
    // Broadband pending (Android: broadcaster_pending_amount). 0 for STB-only.
    final broadcasterPending = double.tryParse(
            SoapClient.readField(xml, 'broadcaster_pending_amount') ?? '') ??
        0.0;
    // Android's ACTUAL last paid amount (CustomerMgmt_MakePayment_Fragment :1459
    // parses `last_paid_amount=` from this same GPA response). This is NOT the
    // pending/bill amount — it's what the customer last paid.
    final lastPaid = double.tryParse(
            SoapClient.readField(xml, 'last_paid_amount') ?? '') ??
        0.0;
    return PendingAmountResult(status, message, pending, billingId, cablePending,
        broadcasterPending, lastPaid);
  }
}
