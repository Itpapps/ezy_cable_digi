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
  // A4: current-month counts for the confirm popup (Android :1474-1484).
  final int paymentsCount;               // payments_count
  final int adjustmentCount;             // adjustment_count
  // A-B3: billing-scheme discount / penalty (Android :1520-1560).
  final PendingScheme scheme;
  const PendingAmountResult(this.statusCode, this.statusMessage,
      this.pendingAmount, this.billingId, this.cablePendingAmount,
      this.broadcasterPendingAmount, [this.lastPaidAmount = 0.0,
      this.paymentsCount = 0, this.adjustmentCount = 0,
      this.scheme = const PendingScheme()]);
}

/// A-B3: the GPA billing-scheme fields Android parses
/// (CustomerMgmt_MakePayment_Fragment :1520-1560). [flag] is the 4-character
/// discount_penalty_flag (e.g. "DA00" automatic / "DM00" manual discount).
class PendingScheme {
  final double discountAmount;            // discount_amount
  final double totalAfterDiscount;        // total_payment_after_discount
  final String discountStart;             // discount_start_date (yyyy-MM-dd)
  final String discountEnd;               // discount_end_date
  final double penaltyAmount;             // penalty_amount
  final double totalAfterPenalty;         // total_payment_after_penalty
  final String penaltyStart;              // penalty_start_date
  final String penaltyEnd;                // penalty_end_date
  final String flag;                      // discount_penalty_flag
  const PendingScheme({
    this.discountAmount = 0,
    this.totalAfterDiscount = 0,
    this.discountStart = '',
    this.discountEnd = '',
    this.penaltyAmount = 0,
    this.totalAfterPenalty = 0,
    this.penaltyStart = '',
    this.penaltyEnd = '',
    this.flag = '0000',
  });
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
    // A4: Android parses these from the same GPA reply (:1474-1484) and shows
    // them in the confirm popup; 0 when absent or unparsable, like Android.
    final paymentsCount = int.tryParse(
            (SoapClient.readField(xml, 'payments_count') ?? '').trim()) ??
        0;
    final adjustmentCount = int.tryParse(
            (SoapClient.readField(xml, 'adjustment_count') ?? '').trim()) ??
        0;
    // A-B3: billing-scheme fields (Android :1520-1560; a missing number → 0,
    // a missing/empty date → '' = no scheme).
    double num(String k) =>
        double.tryParse((SoapClient.readField(xml, k) ?? '').trim()) ?? 0.0;
    String str(String k) {
      final v = (SoapClient.readField(xml, k) ?? '').trim();
      return v == 'anyType{}' ? '' : v;
    }
    final flag = str('discount_penalty_flag');
    final scheme = PendingScheme(
      discountAmount: num('discount_amount'),
      totalAfterDiscount: num('total_payment_after_discount'),
      discountStart: str('discount_start_date'),
      discountEnd: str('discount_end_date'),
      penaltyAmount: num('penalty_amount'),
      totalAfterPenalty: num('total_payment_after_penalty'),
      penaltyStart: str('penalty_start_date'),
      penaltyEnd: str('penalty_end_date'),
      flag: flag.length >= 4 ? flag : '0000',
    );
    return PendingAmountResult(status, message, pending, billingId, cablePending,
        broadcasterPending, lastPaid, paymentsCount, adjustmentCount, scheme);
  }
}
