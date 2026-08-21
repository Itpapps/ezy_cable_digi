import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// Charge type LOV item (`chargeTypes` → `charge_types`).
class ChargeType {
  final String id; // charge_type_id
  final String name; // charge_type_name
  const ChargeType(this.id, this.name);
}

/// One row of `getOneTimeCharges` → `onetime_charges` (Android `Onetimemodel`).
class OnetimeChargeItem {
  final String onetimeChargeId;
  final String chargeTypeName;
  final String amount;
  final String date;
  final String bankName;
  final String branchName;
  final String chequeDdNo;
  final String remarks;
  final String paidUnpaid;
  final String billNo;
  final String receiptNo;
  final String chequeDate;

  const OnetimeChargeItem({
    this.onetimeChargeId = '',
    this.chargeTypeName = '',
    this.amount = '',
    this.date = '',
    this.bankName = '',
    this.branchName = '',
    this.chequeDdNo = '',
    this.remarks = '',
    this.paidUnpaid = '',
    this.billNo = '',
    this.receiptNo = '',
    this.chequeDate = '',
  });

  static String _s(Map j, String k) => '${j[k] ?? ''}';

  factory OnetimeChargeItem.fromJson(Map<String, dynamic> j) => OnetimeChargeItem(
        onetimeChargeId: _s(j, 'onetime_charge_id'),
        chargeTypeName: _s(j, 'charge_type_name'),
        amount: _s(j, 'amount'),
        date: _s(j, 'date'),
        bankName: _s(j, 'bank_name'),
        branchName: _s(j, 'branch_name'),
        chequeDdNo: _s(j, 'cheque_dd_no'),
        remarks: _s(j, 'remarks'),
        paidUnpaid: _s(j, 'paid_unpaid'),
        billNo: _s(j, 'bill_no'),
        receiptNo: _s(j, 'receipt_no'),
        chequeDate: _s(j, 'cheque_date'),
      );
}

class ChargeTypesResult {
  final int statusCode;
  final String statusMessage;
  final List<ChargeType> types;
  const ChargeTypesResult(this.statusCode, this.statusMessage, this.types);
}

class OnetimeSaveResult {
  final int statusCode; // 0 = saved
  final String statusMessage;
  const OnetimeSaveResult(this.statusCode, this.statusMessage);
  bool get isSuccess => statusCode == 0;
}

class OnetimeHistoryResult {
  final int statusCode; // 0 ok · 1 no records · 3 transport
  final String statusMessage;
  final List<OnetimeChargeItem> items;
  const OnetimeHistoryResult(this.statusCode, this.statusMessage, this.items);
}

/// One Time Charges — PLAIN REST `/packagelist/{chargeTypes,saveOnetimeCharges,
/// getOneTimeCharges}` (Android OneTimeCharges_Frag / Onetime_history).
/// Defensive: any failure returns a safe result; never throws to the UI.
class OnetimeChargesRepository {
  OnetimeChargesRepository._();
  static final OnetimeChargesRepository instance = OnetimeChargesRepository._();

  String _url(String m) =>
      '${ServerUrlResolver.instance.namespace}/packagelist/$m';

  Map<String, String> get _auth => {
        'dealer_id': SessionService.instance.dealerId,
        'imei': AppConfig.deviceImei,
        'authtoken': SessionService.instance.authToken,
      };

  // ── chargeTypes (dynamic dropdown) ──────────────────────────────────────────
  Future<ChargeTypesResult> fetchChargeTypes(String customerId) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('chargeTypes'),
        {
          'dealer_id': SessionService.instance.dealerId,
          // Android sends the key with a trailing space ("customer_id ") — kept
          // verbatim for parity (OneTimeCharges_Frag :337).
          'customer_id ': customerId,
          'imei': AppConfig.deviceImei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final types = <ChargeType>[];
      if (status == 0) {
        final list = decodeDynamic(data['charge_types']);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              types.add(ChargeType(
                '${e['charge_type_id'] ?? ''}',
                '${e['charge_type_name'] ?? ''}',
              ));
            }
          }
        }
      }
      return ChargeTypesResult(status, msg, types);
    } on TimeoutException {
      return const ChargeTypesResult(3, 'Request timed out.', []);
    } catch (_) {
      return const ChargeTypesResult(3, 'Could not connect to server.', []);
    }
  }

  // ── saveOnetimeCharges ──────────────────────────────────────────────────────
  Future<OnetimeSaveResult> save({
    required String customerId,
    required String chargeType, // charge_type_id
    required String amount,
    required String chqDd,
    required String bank,
    required String branch,
    required String chqDdDate, // yyyy-MM-dd or ''
    required String remarks,
    required String createdDate, // yyyy-MM-dd
    required int checkPaidUnpaid, // 1 = cheque/instrument · 2 = cash
    // EDIT support (Android Editonetime_Frag → same `sotc` endpoint):
    //   • onetimeChargeId '0' = create (unchanged); real id = edit.
    //   • edit sets ot_type='1' and sends receipt_no (Editonetime_Frag:556-560).
    // Defaults keep the CREATE payload byte-identical.
    String onetimeChargeId = '0',
    String receiptNo = '',
  }) async {
    try {
      final isEdit = onetimeChargeId != '0';
      final body = {
        ..._auth,
        'customer_id': customerId,
        'charge_type': chargeType,
        'amount': amount,
        'chq_dd': chqDd,
        'bank': bank,
        'branch': branch,
        'chq_dd_date': chqDdDate,
        'remarks': remarks,
        'created_date': createdDate,
        'check_paid_unpaid': '$checkPaidUnpaid',
        'onetime_charge_id': onetimeChargeId,
        'ot_type': isEdit ? '1' : '0',
      };
      if (isEdit) body['receipt_no'] = receiptNo; // Android sends it only on edit
      final data = await RestClient.instance.postForm(
        _url('saveOnetimeCharges'),
        body,
        timeout: const Duration(seconds: 70),
      );
      return OnetimeSaveResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const OnetimeSaveResult(3, 'Request timed out.');
    } catch (_) {
      return const OnetimeSaveResult(3, 'Could not connect to server.');
    }
  }

  // ── getOneTimeCharges (history) ─────────────────────────────────────────────
  Future<OnetimeHistoryResult> fetchHistory(String customerId) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getOneTimeCharges'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final items = <OnetimeChargeItem>[];
      if (status == 0) {
        final list = decodeDynamic(data['onetime_charges']);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              items.add(
                  OnetimeChargeItem.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
      return OnetimeHistoryResult(status, msg, items);
    } on TimeoutException {
      return const OnetimeHistoryResult(3, 'Request timed out.', []);
    } catch (_) {
      return const OnetimeHistoryResult(3, 'Could not connect to server.', []);
    }
  }
}
