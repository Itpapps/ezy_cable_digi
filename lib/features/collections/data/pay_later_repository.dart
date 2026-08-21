import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'pay_later.dart';

/// Result of a Pay Later WRITE (`scheduled_collection_create`).
class PayLaterWriteResult {
  final bool success;
  final String message;
  const PayLaterWriteResult(this.success, this.message);
}

/// Result of the Pay Later LIST (`scheduled_collection_data`). One response carries
/// the schedule rows + the employee LOV + the status LOV (Android PayLaterReport).
class PayLaterListResult {
  final int statusCode; // 0 ok · 1 no records / server error · 3 transport
  final String statusMessage;
  final List<PayLaterSchedule> schedules;
  final List<PayLaterEmployee> employees;
  final List<String> statuses;
  const PayLaterListResult(this.statusCode, this.statusMessage, this.schedules,
      this.employees, this.statuses);
}

/// Pay Later / Collection Schedule — REST (`/digi_rest_api/...`), server-side
/// (Android source of truth: CustomerMgmt_MakePayment_Fragment + PayLaterReport).
/// Defensive: any failure returns a safe result, never throws to the UI. Nested
/// response fields are double-encoded JSON strings — decoded safely.
class PayLaterRepository {
  PayLaterRepository._();
  static final PayLaterRepository instance = PayLaterRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

  Map<String, String> get _base => {
        'dealer_id': SessionService.instance.dealerId,
        'imei': _imei,
        'authtoken': SessionService.instance.authToken,
      };

  // ── scheduled_collection_create (Android updatepaylater) ────────────────────
  // VERIFIED (CustomerMgmt_MakePayment_Fragment:2507-2531,2767-2799): employee_id =
  // the logged-in employee; resp Error_code/Error_Message → fail, else status_message.
  Future<PayLaterWriteResult> submitPayLater({
    required String customerId,
    required String scheduledDate, // yyyy-MM-dd
    required String status,
    required String remarks,
    String isEdited = '0',
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('scheduled_collection_create'),
        {
          ..._base,
          'customer_id': customerId,
          'employee_id': SessionService.instance.employeeId,
          'scheduled_date': scheduledDate,
          'status': status,
          'is_edited': isEdited,
          'remarks': remarks,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return PayLaterWriteResult(
            false, '${data['Error_Message'] ?? 'Failed'}');
      }
      return PayLaterWriteResult(
          true, '${data['status_message'] ?? 'Scheduled'}');
    } on TimeoutException {
      return const PayLaterWriteResult(false, 'Request timed out.');
    } catch (_) {
      return const PayLaterWriteResult(false, 'Could not connect to server.');
    }
  }

  // ── scheduled_collection_data (Android paylaterList) ────────────────────────
  // VERIFIED (PayLaterReport:253-428). `customerId` filters to one customer (the
  // payment-screen lookup passes the alt id); the report screen passes ''.
  Future<PayLaterListResult> getPayLaterList({
    String customerId = '',
    String customerName = '',
    String accountNumber = '',
    String crfNumber = '',
    required String scheduledStartDate,
    required String scheduledEndDate,
    String status = '',
    String employeeId = '',
    bool fromDashboard = false,
  }) async {
    try {
      final params = <String, String>{
        ..._base,
        'customer_id': customerId,
        'customer_name': customerName,
        'account_number': accountNumber,
        'crf_number': crfNumber,
        'scheduled_start_date': scheduledStartDate,
        'scheduled_end_date': scheduledEndDate,
        'status': status,
        'from_dashboard': fromDashboard ? '1' : '0',
      };
      // Android's dashboard call (gethitapipaylaterlist) sends ONLY the above +
      // from_dashboard=1. The report / per-customer paths additionally send
      // selected_employee_id, request_from and is_list — keep those off the
      // dashboard call (an empty employee filter returns zero rows).
      if (!fromDashboard) {
        params['selected_employee_id'] = employeeId;
        params['request_from'] = 'FromDigiApp';
        params['is_list'] = '1';
      }
      final data = await RestClient.instance.postEncrypted(
        _url('scheduled_collection_data'),
        params,
        timeout: const Duration(seconds: 70),
      );
      // Android shows a "Fail!" dialog + no-records view on Error_code.
      if (data.containsKey('Error_code')) {
        return PayLaterListResult(
            1, '${data['Error_Message'] ?? 'No records'}', const [], const [], const []);
      }
      final schedules = <PayLaterSchedule>[];
      final list = decodeDynamic(data['customer_data']);
      if (list is List) {
        for (final r in list) {
          if (r is Map) {
            schedules.add(PayLaterSchedule.fromJson(Map<String, dynamic>.from(r)));
          }
        }
      }
      final employees = <PayLaterEmployee>[];
      final emp = decodeDynamic(data['emp_details']);
      if (emp is List) {
        for (final e in emp) {
          if (e is Map) {
            employees.add(PayLaterEmployee.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      final statuses = <String>[];
      final settings = decodeDynamic(data['setting_values']);
      if (settings is Map) {
        final dd = decodeDynamic(settings['status_drop_down']);
        if (dd is List) {
          for (final s in dd) {
            statuses.add(s.toString());
          }
        }
      }
      return PayLaterListResult(0, '', schedules, employees, statuses);
    } on TimeoutException {
      return const PayLaterListResult(3, 'Request timed out.', [], [], []);
    } catch (_) {
      return const PayLaterListResult(3, 'Could not connect to server.', [], [], []);
    }
  }
}
