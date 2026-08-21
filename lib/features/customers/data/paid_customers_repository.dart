import 'dart:async';

import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'paid_customer.dart';

class PaidCustomersResult {
  final int statusCode; // 0 ok · 1 no records · 3 transport
  final String statusMessage;
  final List<PaidCustomer> customers;
  const PaidCustomersResult(
      this.statusCode, this.statusMessage, this.customers);
}

/// Paid Customers list — Android parity (`getPaidCustomer_Detail` / `gpcd`,
/// `PaidlistFragment`). Plain `/packagelist/` REST POST; params exactly Android's
/// (`dealer_id`, `employeeId`, `paid_month` = "M-yyyy" — month NOT zero-padded).
/// Response `Paid_customer_details` is a JSON-array string. status 0 = ok ·
/// 1 = "No Details Found" · 3 = transport. Never throws.
class PaidCustomersRepository {
  PaidCustomersRepository._();
  static final PaidCustomersRepository instance = PaidCustomersRepository._();

  Future<PaidCustomersResult> getPaidCustomers({
    required String paidMonth, // "M-yyyy" e.g. "7-2026"
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        '${ServerUrlResolver.instance.namespace}/packagelist/getPaidCustomer_Detail',
        {
          'dealer_id': SessionService.instance.dealerId,
          'employeeId': SessionService.instance.employeeId,
          'paid_month': paidMonth,
        },
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final customers = <PaidCustomer>[];
      if (status == 0) {
        final list = decodeDynamic(data['Paid_customer_details']);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              customers
                  .add(PaidCustomer.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
      return PaidCustomersResult(status, msg, customers);
    } on TimeoutException {
      return const PaidCustomersResult(3, 'Request timed out.', []);
    } catch (_) {
      return const PaidCustomersResult(3, 'Failed.', []);
    }
  }

}
