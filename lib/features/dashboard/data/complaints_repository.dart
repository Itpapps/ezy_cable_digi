import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';
import '../../complaints/data/complaint_option.dart';
import '../../complaints/data/customer_complaint.dart';
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

  /// [dealerId] / [fromDashboard] default to the dashboard-card values (0 / "1"),
  /// so the dashboard feed call `fetchOpenComplaints()` stays byte-for-byte the
  /// same. The Complaints tab passes the spinner's dealer_id + "0" — Android
  /// parity (OpenComplaints_Fragment:389-390).
  Future<ComplaintsResult> fetchOpenComplaints({
    int dealerId = 0,
    String fromDashboard = '1',
  }) async {
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
        'dealer_id': dealerId,
        'from_dashboard': fromDashboard,
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

  /// Mapped dealers / businesses for the Complaints-tab dropdown — Android parity
  /// (OpenComplaints_Fragment.Getmappeddealersru → SOAP `gmd` = `getMappeddealers`,
  /// wrapper element + i:type `getMappedDealers`, request `authToken` + `imei`).
  /// Response = repeated `dealerinfo{ dealer_id, business_name }`. Returns a list
  /// led by "Choose" (id 0), exactly like Android's items[0]. Never throws.
  Future<List<ComplaintOption>> fetchMappedDealers() async {
    final list = <ComplaintOption>[const ComplaintOption(0, 'Choose')];
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        // Method name is lowercase-d `getMappeddealers` (config `gmd`), but the
        // wrapper element + i:type are capital-D `getMappedDealers` (Android quirk).
        soapAction: '$ns/getMappeddealers',
        methodName: 'getMappeddealers',
        wrapper: 'getMappedDealers',
        wrapperType: 'getMappedDealers',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      if (status == 0) {
        for (final block in SoapClient.readAll(xml, 'dealerinfo')) {
          final id =
              int.tryParse(SoapClient.readField(block, 'dealer_id') ?? '');
          final name =
              (SoapClient.readField(block, 'business_name') ?? '').trim();
          if (id != null && name.isNotEmpty) {
            list.add(ComplaintOption(id, name));
          }
        }
      }
    } catch (_) {
      // Keep just [Choose] — the tab still loads complaints for dealer_id 0.
    }
    return list;
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

  /// A customer's complaint history (key `gccl`, method `getCustomerComplaintList`).
  /// Wrapper element `compListInfo`, i:type `getCustomerComplaintList`; request
  /// `altCustomerId` + `authToken` + `imei`. Response = repeated
  /// `customerComplaintList` elements. Defensive — never throws to the UI.
  Future<CustomerComplaintsResult> fetchCustomerComplaints({
    required String altCustomerId,
  }) async {
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/getCustomerComplaintList',
        methodName: 'getCustomerComplaintList',
        wrapper: 'compListInfo',
        wrapperType: 'getCustomerComplaintList',
        fields: {
          'altCustomerId': int.tryParse(altCustomerId) ?? 0,
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';
      final items = <CustomerComplaint>[];
      if (status == 0) {
        for (final inner in SoapClient.readAll(xml, 'customerComplaintList')) {
          String f(String k) => (SoapClient.readField(inner, k) ?? '').trim();
          items.add(CustomerComplaint(
            customerId: f('customer_id'),
            altCustomerId: f('alt_cust_id'),
            customNumber: f('customnumber'),
            customerName: f('name'),
            groupName: f('group_name'),
            complaintId: f('complaint_id'),
            ticketNumber: f('tkt_number'),
            description: f('description'),
            complaintTime: f('complaintTime'),
            status: f('status'),
          ));
        }
      }
      return CustomerComplaintsResult(status, message, items);
    } on TimeoutException {
      return const CustomerComplaintsResult(3, 'Request timed out.', []);
    } catch (_) {
      return const CustomerComplaintsResult(3, 'Could not connect to server.', []);
    }
  }

  /// Complaint categories LOV (key `comcat`, method `complaintCategories`).
  /// Wrapper `compCatInfo`/`getComplaintCategoriesInfo`; request `authToken`+`imei`.
  /// Returns a list led by `ComplaintOption.select`. On any failure returns just
  /// `[Select]` — never throws (the Create screen stays usable).
  Future<List<ComplaintOption>> fetchComplaintCategories() async {
    final list = <ComplaintOption>[ComplaintOption.select];
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/complaintCategories',
        methodName: 'complaintCategories',
        wrapper: 'compCatInfo',
        wrapperType: 'getComplaintCategoriesInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 60),
      );
      for (final inner in SoapClient.readAll(xml, 'complaintCategories')) {
        final id = int.tryParse(SoapClient.readField(inner, 'categoryId') ?? '');
        final name = (SoapClient.readField(inner, 'categoryName') ?? '').trim();
        if (id != null && id != 0 && name.isNotEmpty) {
          list.add(ComplaintOption(id, name));
        }
      }
    } catch (_) {
      // keep just [Select]
    }
    return list;
  }

  /// Assigned-employees LOV (key `aed`, method `assignedemployeedetails`).
  /// Wrapper `assignedinfo`/`assignedEmployeeInfo`; request `authToken`+`imei`+
  /// `customerId` (the numeric customer_id). Returns a list led by
  /// `ComplaintOption.select`. Never throws.
  Future<List<ComplaintOption>> fetchAssignedEmployees(String customerId) async {
    final list = <ComplaintOption>[ComplaintOption.select];
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/assignedemployeedetails',
        methodName: 'assignedemployeedetails',
        wrapper: 'assignedinfo',
        wrapperType: 'assignedEmployeeInfo',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
          // The SOAP element name is `customer_id` (getassignedinfo.getPropertyInfo
          // case 2), even though the Java field is `customerId`. Sending the wrong
          // name made the server return an empty employee list.
          'customer_id': int.tryParse(customerId) ?? 0,
        },
        timeout: const Duration(seconds: 60),
      );
      for (final inner in SoapClient.readAll(xml, 'assignedemployee_details')) {
        final id = int.tryParse(SoapClient.readField(inner, 'employee_id') ?? '');
        final name =
            (SoapClient.readField(inner, 'employee_name') ?? '').trim();
        if (id != null && id != 0 && name.isNotEmpty) {
          list.add(ComplaintOption(id, name));
        }
      }
    } catch (_) {
      // keep just [Select]
    }
    return list;
  }

  /// Create a complaint (key `crecomp`, method `createComplaint`).
  /// Wrapper `newCompInfo`/`createComplaintInfo`. [customerId] is the numeric
  /// customer_id. SIMPLE mode sends `error` = 0. Defensive — never throws.
  Future<ComplaintActionResult> createComplaint({
    required String customerId,
    required String complaint,
    required int category,
    required int assignedTo,
    int error = 0,
    String latitude = '0.0',
    String longitude = '0.0',
  }) async {
    try {
      final ns = ServerUrlResolver.instance.namespace;
      final xml = await SoapClient.instance.call(
        url: ServerUrlResolver.instance.loginServerUrl,
        namespace: ns,
        soapAction: '$ns/createComplaint',
        methodName: 'createComplaint',
        wrapper: 'newCompInfo',
        wrapperType: 'createComplaintInfo',
        fields: {
          'customerId': int.tryParse(customerId) ?? 0,
          'authToken': SessionService.instance.authToken,
          'complaint': complaint,
          'category': category,
          'error': error,
          'imei': _imei,
          'latitude': latitude,
          'longitude': longitude,
          'assigned_to': assignedTo,
          'lat': latitude,
          'lang': longitude,
        },
        timeout: const Duration(seconds: 100),
      );
      final codeStr = SoapClient.readField(xml, 'statusCode');
      final code = int.tryParse(codeStr ?? '') ?? 3;
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';
      if (codeStr == null) {
        return const ComplaintActionResult(
            3, 'Server busy or unreachable. Please try again.');
      }
      return ComplaintActionResult(code, message);
    } on TimeoutException {
      return const ComplaintActionResult(3, 'Request timed out. Please try again.');
    } catch (_) {
      return const ComplaintActionResult(
          3, 'Could not connect to server. Please try again.');
    }
  }
}

/// Result of `getCustomerComplaintList`.
class CustomerComplaintsResult {
  final int statusCode; // 0 = ok · 1 = no records · 2 = error · 3 = failed
  final String statusMessage;
  final List<CustomerComplaint> complaints;
  const CustomerComplaintsResult(
      this.statusCode, this.statusMessage, this.complaints);
}
