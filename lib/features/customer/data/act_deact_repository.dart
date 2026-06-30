import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// One row of `package_act_deact_report` (Android `ActdeactModel`).
class ActDeactItem {
  final String packageName;
  final String boxNumber;
  final String operationType;
  final String createdDate;
  final String errorMessage;
  final String createdBy;

  const ActDeactItem({
    required this.packageName,
    required this.boxNumber,
    required this.operationType,
    required this.createdDate,
    required this.errorMessage,
    required this.createdBy,
  });

  static String _s(Map j, String k) => '${j[k] ?? ''}';

  factory ActDeactItem.fromJson(Map<String, dynamic> j) => ActDeactItem(
        packageName: _s(j, 'name'),
        boxNumber: _s(j, 'box_number'),
        operationType: _s(j, 'operation_type'),
        createdDate: _s(j, 'created_on'),
        errorMessage: _s(j, 'error_msg'),
        createdBy: _s(j, 'created_name'),
      );
}

/// Result of `packageActDeactReport`. `statusCode`: 0 = ok · 1 = no records
/// (show message) · 3 = transport failure.
class ActDeactResult {
  final int statusCode;
  final String statusMessage;
  final List<ActDeactItem> items;
  const ActDeactResult(this.statusCode, this.statusMessage, this.items);
}

/// Act/Deactivate Report — PLAIN REST `/packagelist/packageActDeactReport`.
/// Android `Act_Deact_Report`. The response can contain stray `<br>` tags which
/// must be stripped before JSON decoding (Android :110). Defensive; never throws.
class ActDeactRepository {
  ActDeactRepository._();
  static final ActDeactRepository instance = ActDeactRepository._();

  Future<ActDeactResult> fetch(String customerId) async {
    try {
      final url =
          '${ServerUrlResolver.instance.namespace}/packagelist/packageActDeactReport';
      // Raw body first — the response may contain <br> (invalid JSON) that
      // Android strips before parsing.
      var body = await RestClient.instance.postRaw(
        url,
        {
          'dealer_id': SessionService.instance.dealerId,
          'employee_id': SessionService.instance.employeeId,
          'customer_id': customerId,
          'imei': AppConfig.deviceImei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 100),
      );
      body = body.replaceAll('<br>', '');
      final data = jsonDecode(body);
      if (data is! Map) {
        return const ActDeactResult(3, 'Unexpected response.', []);
      }
      final sc = data['status_code'];
      final status = sc is int ? sc : (int.tryParse('$sc') ?? 3);
      final msg = '${data['status_msg'] ?? ''}';
      final items = <ActDeactItem>[];
      if (status == 0) {
        final raw = data['package_act_deact_report'];
        final list = raw is String ? jsonDecode(raw) : raw;
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              items.add(ActDeactItem.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
      return ActDeactResult(status, msg, items);
    } on TimeoutException {
      return const ActDeactResult(3, 'Request timed out.', []);
    } catch (_) {
      return const ActDeactResult(3, 'Could not connect to server.', []);
    }
  }
}
