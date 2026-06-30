import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'expense_models.dart';

class ExpenseMasterResult {
  final int statusCode; // 0 ok · 1 server error · 3 transport
  final String statusMessage;
  final ExpenseMasterData data;
  const ExpenseMasterResult(this.statusCode, this.statusMessage, this.data);
}

class ExpenseListResult {
  final int statusCode;
  final String statusMessage;
  final List<ExpenseListItem> items;
  const ExpenseListResult(this.statusCode, this.statusMessage, this.items);
}

class ExpenseWriteResult {
  final bool success;
  final String message;
  const ExpenseWriteResult(this.success, this.message);
}

/// Expenses — REST (`/digi_rest_api/...`), Android parity (`ExpensesList` +
/// `AddExpensesFragment`). Defensive: failures return safe results, never throw.
/// Nested response fields are double-encoded JSON strings — decoded safely.
class ExpensesRepository {
  ExpensesRepository._();
  static final ExpensesRepository instance = ExpensesRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

  Map<String, String> get _base => {
        'imei': _imei,
        'authtoken': SessionService.instance.authToken,
        'dealer_id': SessionService.instance.dealerId,
        'employee_id': SessionService.instance.employeeId,
        'request_from': 'FromDigiApp',
      };

  static dynamic _decode(dynamic raw) {
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  // ── expense_dashboard (master data: categories, tax types, payment modes) ───
  Future<ExpenseMasterResult> getMasterData() async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('expense_dashboard'),
        {..._base},
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return ExpenseMasterResult(
            1, '${data['Error_Message'] ?? 'Failed'}', const ExpenseMasterData());
      }
      final fields = _decode(data['create_required_data_fields']);
      if (fields is! Map) {
        return const ExpenseMasterResult(0, '', ExpenseMasterData());
      }
      final modes = <String>[];
      final pm = _decode(fields['payment_modes']);
      if (pm is List) {
        for (final m in pm) {
          modes.add(m.toString());
        }
      }
      final categories = <ExpenseCategory>[];
      final ct = _decode(fields['category_types']);
      if (ct is List) {
        for (final c in ct) {
          if (c is Map) {
            categories.add(ExpenseCategory.fromJson(Map<String, dynamic>.from(c)));
          }
        }
      }
      final taxTypes = <ExpenseTaxType>[];
      final tt = _decode(fields['tax_types']);
      if (tt is List) {
        for (final t in tt) {
          if (t is Map) {
            taxTypes.add(ExpenseTaxType.fromJson(Map<String, dynamic>.from(t)));
          }
        }
      }
      return ExpenseMasterResult(
        0,
        '',
        ExpenseMasterData(
            paymentModes: modes, categories: categories, taxTypes: taxTypes),
      );
    } on TimeoutException {
      return const ExpenseMasterResult(3, 'Request timed out.', ExpenseMasterData());
    } catch (_) {
      return const ExpenseMasterResult(
          3, 'Could not connect to server.', ExpenseMasterData());
    }
  }

  // ── expense_data (list, date-range filtered) ────────────────────────────────
  Future<ExpenseListResult> getExpenseList({
    required String startDate, // yyyy-MM-dd
    required String endDate,
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('expense_data'),
        {
          ..._base,
          'employee_id': '', // Android parity: default empty employee filter
          'selected_employee_id': '',
          'payment_method': '',
          'expense_category': '',
          'expense_start_date': startDate,
          'expense_end_date': endDate,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return ExpenseListResult(
            1, '${data['Error_Message'] ?? 'No records'}', const []);
      }
      final items = <ExpenseListItem>[];
      final list = _decode(data['expenses_list']);
      if (list is List) {
        for (final e in list) {
          if (e is Map) {
            items.add(ExpenseListItem.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      return ExpenseListResult(0, '', items);
    } on TimeoutException {
      return const ExpenseListResult(3, 'Request timed out.', []);
    } catch (_) {
      return const ExpenseListResult(3, 'Could not connect to server.', []);
    }
  }

  // ── expense_data_create (create / edit) ─────────────────────────────────────
  // VERIFIED (AddExpensesFragment:508-535): expense_tax_type_id="0", total_amount="",
  // tax_type carries the selected tax-type id. Response: Error_code/Error_Message →
  // fail; else status_message → success.
  Future<ExpenseWriteResult> createExpense({
    required String title,
    required String categoryId,
    required String date, // yyyy-MM-dd
    required String baseAmount,
    required String paymentMethod,
    required String taxTypeId,
    required String taxAmount,
    String invoiceNumber = '',
    String remarks = '',
    String expenseId = '',
    String isEdited = '0',
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('expense_data_create'),
        {
          ..._base,
          'is_edited': isEdited,
          'expense_title': title,
          'expense_id': expenseId,
          'expense_category_id': categoryId,
          'expense_tax_type_id': '0',
          'expense_date': '$date 00:00:00',
          'total_amount': '',
          'base_amount': baseAmount,
          'payment_method': paymentMethod,
          'expense_invoice_number': invoiceNumber,
          'remarks': remarks,
          'tax_type': taxTypeId,
          'tax_amount': taxAmount,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return ExpenseWriteResult(false, '${data['Error_Message'] ?? 'Failed'}');
      }
      return ExpenseWriteResult(true, '${data['status_message'] ?? 'Saved'}');
    } on TimeoutException {
      return const ExpenseWriteResult(false, 'Request timed out.');
    } catch (_) {
      return const ExpenseWriteResult(false, 'Could not connect to server.');
    }
  }
}
