import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Make Payment (config key `mpay`) — STB ONLY (Phase-1).
// Android: makePayments, wrapper `paymentInfo` (i:type makePaymentsInfo).
// CustomerMgmt_MakePayment_Fragment (build ~1814–1975) + complexclasses/makePaymentsInfo.java.
//
// SCOPE (verified evidence only):
//   • STB cash payment. modeType = "cash". broadband_payment_amount = 0.0.
//   • amount = due_amount − discount_applied (server validates).
//   • billingId comes from the GPA response.
//   • receiptNumber is SERVER-issued — never fabricated here.
// OUT OF SCOPE (architecture-aware, not implemented): broadband (async via
//   broadband_payment_staging → broadband_payment_details, billing_id=0, no discount),
//   STB+Broadband combined, other modes (bank/card/upi). See server docs/MAKE_PAYMENT.md.
// ─────────────────────────────────────────────────────────────────────────────

/// Parsed `makePayments` response. The receipt is built from these server fields.
class MakePaymentResult {
  final int statusCode; // 0 = success
  final String statusMessage;
  final String receiptNumber; // server-issued (CR{dealer}/{seq}/{counter})
  final String billNumber;
  final String customerName;
  final double amount;
  final double billAmount; // receipt "Bill Amount" (server response field)
  final String dealerBusinessName;
  final String billForMonth;
  // A-B5: GST lines tax_displayname1-6 / tax_amount1-6 (Android
  // CustomerMgmt_MakePayment_Fragment :2135-2278). Always 6 entries; a missing
  // or "anyType{}" name → "NA", a missing amount → 0.
  final List<ReceiptTax> taxes;
  const MakePaymentResult({
    required this.statusCode,
    required this.statusMessage,
    required this.receiptNumber,
    required this.billNumber,
    required this.customerName,
    required this.amount,
    required this.billAmount,
    required this.dealerBusinessName,
    required this.billForMonth,
    this.taxes = const [],
  });

  bool get isSuccess => statusCode == 0;
}

/// A-B5: one GST line of the payment receipt.
class ReceiptTax {
  final String name;
  final double amount;
  const ReceiptTax(this.name, this.amount);
}

class MakePaymentRepository {
  MakePaymentRepository._();
  static final MakePaymentRepository instance = MakePaymentRepository._();

  static String get _imei => AppConfig.deviceImei;

  /// STB cash payment.
  /// [altCustomerId] = customer_id. [billingId]/[dueAmount] come from GPA.
  /// [amount] = what the customer pays (= due − discount). [discountApplied] = STB discount.
  Future<MakePaymentResult> pay({
    required int altCustomerId,
    required int billingId,
    required double amount,
    required double dueAmount,
    required double discountApplied,
    required String modeType, // "cash" or "bank"
    required bool sendSms,
    required String remarks,
    required String mobileNumber,
    // Bank/Cheque leg — Android sends these ONLY in the "bank" branch
    // (CustomerMgmt_MakePayment_Fragment :1876-1879). For cash they stay empty,
    // so the default '' keeps the cash payload byte-identical.
    String chequeNo = '',
    String bank = '',
    String branch = '',
    String chequeDate = '',
    // A-B3 / Android :1836 discount_penalty_flag_update ("0000" / "DA00" /
    // "DM00" / "00PA" / "00PM").
    String discountPenaltyFlag = '0000',
    // Broadband leg — empty/0 for STB-only (Android sets these only when the
    // broadband account id is non-empty).
    double broadbandAmount = 0.0,
    String broadbandUserId = '',
    String broadbandDue = '',
    String isForRenewal = '',
    // Payment GPS — Android sends last-known coords with a 0.0 fallback
    // (CustomerMgmt_MakePayment_Fragment :339-348 / :1837-1838). Audit metadata
    // only; the server never blocks payment on it, so 0.0 is the safe default.
    String latitude = '0.0',
    String longitude = '0.0',
    // A1 / Android :1945-1951: makePayments waits 100 s on mobile data,
    // otherwise 200 s (the caller decides; default = Android's 200 s branch).
    Duration timeout = const Duration(seconds: 200),
  }) async {
    final ns = ServerUrlResolver.instance.namespace;
    // Full 28-field makePaymentsInfo in Android's EXACT index order (parity with
    // CustomerMgmt_MakePayment_Fragment :1816–1859 + makePaymentsInfo.java :60–116).
    // Cash STB: cheque/card/broadband fields are empty/0 (Android leaves them null/0).
    final xml = await SoapClient.instance.call(
      url: ServerUrlResolver.instance.loginServerUrl,
      namespace: ns,
      soapAction: '$ns/makePayments',
      methodName: 'makePayments',
      wrapper: 'paymentInfo',
      wrapperType: 'makePaymentsInfo',
      timeout: timeout, // A1
      fields: {
        'altCustomerId': altCustomerId,                 // 0
        'authToken': SessionService.instance.authToken, // 1
        'amount': amount,                               // 2  float (= due − discount)
        'chequeNo': chequeNo,                           // 3  (bank only; '' for cash)
        'bank': bank,                                   // 4  (bank only; '' for cash)
        'branch': branch,                               // 5  (bank only; '' for cash)
        'chequeDate': chequeDate,                       // 6  (bank only; '' for cash)
        'billingId': billingId,                         // 7  from GPA
        'remarks': remarks,                             // 8
        'imei': _imei,                                  // 9
        'modeType': modeType,                           // 10 "cash"
        'rrnNo': '',                                    // 11 (card only)
        'cardholderName': '',                           // 12 (card only)
        'paynearpaymentdetails': '',                    // 13 (card only)
        'mobileNumber': mobileNumber,                   // 14
        'sendsms': sendSms ? 1 : 0,                     // 15
        'payment_flag': 4,                              // 16 mobile-app online payment
        'discount_penalty_flag': discountPenaltyFlag,  // 17 4-char (A-B3)
        'latitude': latitude,                           // 18 last-known GPS (Android parity; 0.0 fallback)
        'longitude': longitude,                         // 19 last-known GPS (Android parity; 0.0 fallback)
        'discount_applied': discountApplied,            // 20 float STB discount
        'transaction_number': '',                       // 21 empty for fresh online
        'broadband_payment_amount': broadbandAmount,    // 22 (0.0 for STB-only)
        'broadband_user_id': broadbandUserId,           // 23 (empty for STB-only)
        'broadband_due': broadbandDue,                  // 24 (empty for STB-only)
        'is_for_renewal': isForRenewal,                 // 25 (empty for STB-only)
        'due_amount': dueAmount,                        // 26 float — the pending
        // 27: from login (Android: LoginActivity.MAX_DISCOUNT_PERCENT_ALLOWED).
        'max_discount_percentage_allowed':
            SessionService.instance.maxDiscountPercentAllowed,
      },
    );

    final status =
        int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
    final result = MakePaymentResult(
      statusCode: status,
      statusMessage: SoapClient.readField(xml, 'statusMessage') ?? '',
      receiptNumber: SoapClient.readField(xml, 'receiptNumber') ?? '',
      billNumber: SoapClient.readField(xml, 'billNumber') ?? '',
      customerName: SoapClient.readField(xml, 'customerName') ?? '',
      amount:
          double.tryParse(SoapClient.readField(xml, 'amount') ?? '') ?? amount,
      // Receipt "Bill Amount" — Android reads `billAmount` from this response
      // (CustomerMgmt_MakePayment_Fragment :2076), not from the customer list.
      billAmount:
          double.tryParse(SoapClient.readField(xml, 'billAmount') ?? '') ?? 0.0,
      dealerBusinessName: SoapClient.readField(xml, 'dealerBusinessName') ?? '',
      billForMonth: SoapClient.readField(xml, 'bill_for_month') ?? '',
      taxes: [
        for (var i = 1; i <= 6; i++)
          ReceiptTax(
            () {
              final n =
                  (SoapClient.readField(xml, 'tax_displayname$i') ?? '').trim();
              return (n.isEmpty || n == 'anyType{}') ? 'NA' : n;
            }(),
            double.tryParse(
                    (SoapClient.readField(xml, 'tax_amount$i') ?? '').trim()) ??
                0.0,
          ),
      ],
    );

    return result;
  }
}
