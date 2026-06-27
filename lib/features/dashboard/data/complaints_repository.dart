import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';
import 'open_complaint.dart';

/// Result of the dashboard Complaints call (`getopencomplaintslist`).
class ComplaintsResult {
  final int statusCode; // 0 = ok · 1 = no records · 2 = error · 3 = failed
  final String statusMessage;
  final List<OpenComplaint> complaints;
  const ComplaintsResult(this.statusCode, this.statusMessage, this.complaints);
}

/// Result of a complaint write action (e.g. `closeComplaint`).
class ComplaintActionResult {
  final int statusCode; // 0 = ok · 1 = invalid details · 2 = support · 3 = failed
  final String statusMessage;
  const ComplaintActionResult(this.statusCode, this.statusMessage);
  bool get isSuccess => statusCode == 0;
}

/// The safe default status options, used when the `complaintTypes` LOV cannot be
/// loaded (so the Update screen is still usable). Mirrors the values the existing
/// app shows. 'Select' is always the first (no-op) option.
const List<String> kDefaultComplaintStatuses = [
  'Select',
  'ASSIGNED',
  'INPROCESS',
  'ONHOLD',
  'RESOLVED',
  'CLOSED',
];

/// Open Complaints list (config key `gocl`).
/// Android: `getopencomplaintslist`, wrapper `openComplaintsInfo`
/// (i:type `OpenComplaintsInfo`), fields `authToken` + `imei` + `dealer_id` (0)
/// + `from_dashboard` ("1"). Response `opencomplaintList` is a JSON-array string
/// (double-encoded, same as `unpaidcustomers`). See server docs/DASHBOARD_FLOW.md §2.3.
class ComplaintsRepository {
  ComplaintsRepository._();
  static final ComplaintsRepository instance = ComplaintsRepository._();

  static String get _imei => AppConfig.deviceImei;

  Future<ComplaintsResult> fetchOpenComplaints() async {
    final ns = ServerUrlResolver.instance.namespace;
    final xml = await SoapClient.instance.call(
      url: ServerUrlResolver.instance.loginServerUrl,
      namespace: ns,
      soapAction: '$ns/getopencomplaintslist',
      methodName: 'getopencomplaintslist',
      wrapper: 'openComplaintsInfo',
      wrapperType: 'OpenComplaintsInfo',
      fields: {
        'authToken': SessionService.instance.authToken,
        'imei': _imei,
        'dealer_id': 0,
        'from_dashboard': '1',
      },
      timeout: const Duration(seconds: 120),
    );

    final status =
        int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
    final message = SoapClient.readField(xml, 'statusMessage') ?? '';
    if (status != 0) {
      return ComplaintsResult(status, message, const []);
    }

    // opencomplaintList is a JSON string holding the array (Android double-encodes).
    final raw = SoapClient.readField(xml, 'opencomplaintList') ?? '[]';
    final complaints = <OpenComplaint>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            complaints
                .add(OpenComplaint.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {
      // Malformed payload → empty list, never throws to the UI.
    }
    return ComplaintsResult(status, message, complaints);
  }

  /// Fetch the status list-of-values (LOV) for the Update Status dropdown.
  /// API key `compty`, method `complaintTypes`, wrapper `getComplaintStatusInfo`.
  /// Returns a list beginning with 'Select'. Falls back to
  /// [kDefaultComplaintStatuses] on any failure — never throws to the UI.
  Future<List<String>> fetchComplaintStatuses() async {
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/complaintTypes',
        methodName: 'complaintTypes',
        wrapper: 'getComplaintStatusInfo',
        wrapperType: 'getComplaintStatusInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final items = SoapClient.readAll(xml, 'complaintStatuses');
      final statuses = <String>['Select'];
      for (final item in items) {
        final name = (SoapClient.readField(item, 'statusName') ?? '').trim();
        if (name.isNotEmpty) statuses.add(name);
      }
      // If the API returned nothing useful, fall back to the safe default list.
      return statuses.length > 1 ? statuses : kDefaultComplaintStatuses;
    } catch (_) {
      return kDefaultComplaintStatuses;
    }
  }

  /// Update / close a complaint via `closeComplaint` (key `clscomp`).
  /// Wrapper element `closeCompInfo`, i:type `closeComplaintInfo`.
  /// Returns [ComplaintActionResult]:
  ///   statusCode 0 = success · 1 = invalid details · 2 = contact support
  ///   statusCode 3 = server busy/unreachable/timeout/network error.
  /// Never throws to the UI.
  Future<ComplaintActionResult> closeComplaint({
    required String altCustomerId,
    required String complaintId,
    required String ticketNumber,
    required String status,
    required String comment,
  }) async {
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/closeComplaint',
        methodName: 'closeComplaint',
        wrapper: 'closeCompInfo',
        wrapperType: 'closeComplaintInfo',
        fields: {
          'altCustomerId': int.tryParse(altCustomerId) ?? 0,
          'authToken': SessionService.instance.authToken,
          'complaintId': int.tryParse(complaintId) ?? 0,
          'comment': comment,
          'status': status,
          'ticketNumber': ticketNumber,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final codeStr = SoapClient.readField(xml, 'statusCode');
      if (codeStr == null) {
        // Null statusCode → server busy / unreachable (mirrors Android behavior).
        return const ComplaintActionResult(3, 'Server busy or unreachable. Please try again.');
      }
      final code = int.tryParse(codeStr) ?? 3;
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';
      return ComplaintActionResult(code, message);
    } on TimeoutException {
      return const ComplaintActionResult(3, 'Request timed out. Please try again.');
    } catch (_) {
      return const ComplaintActionResult(3, 'Could not connect to server. Please try again.');
    }
  }
}
