import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// One payment row from `getPaymentHistorylist` (`total_payment_list[]`).
/// Field names mirror the Android `PaymentHistoryModel` JSON keys exactly.
class PaymentRecord {
  final String mobileNumber;
  final String customerName;
  final String city;
  final String state;
  final String amount;
  final String billAmount;
  final String taxAmount;
  final String paidOn;
  final String pending;
  final String paymentType;
  final String receiptNumber;
  final String customNumber;
  final String billForMonth;

  const PaymentRecord({
    required this.mobileNumber,
    required this.customerName,
    required this.city,
    required this.state,
    required this.amount,
    required this.billAmount,
    required this.taxAmount,
    required this.paidOn,
    required this.pending,
    required this.paymentType,
    required this.receiptNumber,
    required this.customNumber,
    required this.billForMonth,
  });

  static String _s(Map j, String k) => '${j[k] ?? ''}';

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        mobileNumber: _s(j, 'mobileNumber'),
        customerName: _s(j, 'customerName'),
        city: _s(j, 'city'),
        state: _s(j, 'state'),
        amount: _s(j, 'amount'),
        billAmount: _s(j, 'billAmount'),
        taxAmount: _s(j, 'tax_amount'),
        paidOn: _s(j, 'paid_on'),
        pending: _s(j, 'pending'),
        paymentType: _s(j, 'payment_type'),
        receiptNumber: _s(j, 'receiptNumber'),
        customNumber: _s(j, 'customNumber'),
        billForMonth: _s(j, 'bill_for_month'),
      );

  /// `paid_on` (yyyy-MM-dd…) → dd/MM/yyyy, mirroring `PaymentHistory_Adapter`.
  String get paidDateDisplay {
    if (paidOn.length < 10) return paidOn;
    final d = paidOn.substring(0, 10); // yyyy-MM-dd
    final p = d.split('-');
    if (p.length != 3) return d;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  /// `payment_type` → label, mirroring `PaymentHistory_Adapter`.
  String get paymentTypeLabel {
    switch (paymentType) {
      case '1':
        return 'STB Payment';
      case '2':
        return 'BroadBand Payment';
      case '3':
        return 'Discount';
      default:
        return paymentType;
    }
  }
}

/// Result of `getPaymentHistorylist`. `statusCode`: 0 = ok · 1 = no records
/// (show message) · 3 = transport failure.
class PaymentHistoryResult {
  final int statusCode;
  final String statusMessage;
  final List<PaymentRecord> payments;
  const PaymentHistoryResult(
      this.statusCode, this.statusMessage, this.payments);
}

/// Payment History — PLAIN REST `/packagelist/getPaymentHistorylist`.
/// Android: `CustomerOperations_Fragment.getpayhist()` (`getpayhistlist`).
/// Defensive: any failure returns `statusCode 3` with an empty list — never
/// throws to the UI.
class PaymentHistoryRepository {
  PaymentHistoryRepository._();
  static final PaymentHistoryRepository instance = PaymentHistoryRepository._();

  Future<PaymentHistoryResult> fetch(String customerId) async {
    try {
      final url =
          '${ServerUrlResolver.instance.namespace}/packagelist/getPaymentHistorylist';
      final data = await RestClient.instance.postForm(
        url,
        {
          'dealer_id': SessionService.instance.dealerId,
          'customerId': customerId,
          'imei': AppConfig.deviceImei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      final sc = data['status_code'];
      final status = sc is int ? sc : (int.tryParse('$sc') ?? 3);
      final msg = '${data['status_msg'] ?? ''}';
      final payments = <PaymentRecord>[];
      if (status == 0) {
        final raw = data['total_payment_list'];
        final list = raw is String ? jsonDecode(raw) : raw;
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              payments.add(PaymentRecord.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
      return PaymentHistoryResult(status, msg, payments);
    } on TimeoutException {
      return const PaymentHistoryResult(3, 'Request timed out.', []);
    } catch (_) {
      return const PaymentHistoryResult(3, 'Could not connect to server.', []);
    }
  }
}
