import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/network/soap_client.dart';
import '../../../core/services/session_service.dart';
import 'customer_box.dart';
import 'package.dart';

/// Result of `getCustomerBoxes` (gcb). `statusCode == 1` = "NO Boxes" (empty,
/// not an error — handle as empty state).
class CustomerBoxesResult {
  final int statusCode; // 0 ok · 1 no boxes · 3 failed
  final String statusMessage;
  final List<CustomerBox> boxes;
  final String serviceExtension;
  final List<CustomerBox> ottBoxes; // ott_boxes_list → OTT operation
  const CustomerBoxesResult(
      this.statusCode, this.statusMessage, this.boxes, this.serviceExtension,
      [this.ottBoxes = const []]);
}

/// Result of `getCustomerPackages` (gcp) — base / add-on / ala-carte.
class CustomerPackagesResult {
  final int statusCode;
  final String statusMessage;
  final List<Package> base;
  final List<Package> addOn;
  final List<Package> alaCarte;
  const CustomerPackagesResult(this.statusCode, this.statusMessage, this.base,
      this.addOn, this.alaCarte);
  List<Package> get all => [...base, ...addOn, ...alaCarte];
}

/// Result of `getcustomerpackageslist` (gcpl) — active packages with expiry.
class ActivePackagesResult {
  final int statusCode;
  final String statusMessage;
  final List<ActivePackage> packages;
  const ActivePackagesResult(this.statusCode, this.statusMessage, this.packages);
}

/// Result of `Customerdeactivereasons` (cdr) — deactivation reasons LOV.
class DeactivateReasonsResult {
  final int statusCode;
  final String statusMessage;
  final List<DeactivateReason> reasons;
  const DeactivateReasonsResult(
      this.statusCode, this.statusMessage, this.reasons);
}

/// Result of a `Customerpackageoperations` (cpo) WRITE — activate/deactivate.
/// `statusCode`: 0 = success · 1 = backend-rejected (show `statusMessage`) ·
/// 3 = transport failure (timeout/network).
class PackageWriteResult {
  final int statusCode;
  final String statusMessage;
  const PackageWriteResult(this.statusCode, this.statusMessage);
  bool get isSuccess => statusCode == 0;
}

/// Package Operations — REST (`/packagelist/...`) read APIs (Phase 1 foundation).
/// Defensive by design: any failure (network/timeout/malformed) returns a
/// `statusCode 3` result with an empty list — it NEVER throws to the UI, and all
/// nested JSON (which the backend double-encodes as strings) is decoded safely.
/// See server docs/PACKAGE_OPERATIONS_COMPLETE.md (frozen spec).
class PackageOperationsRepository {
  PackageOperationsRepository._();
  static final PackageOperationsRepository instance =
      PackageOperationsRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/packagelist/$method';

  Map<String, String> get _auth => {
        'dealer_id': SessionService.instance.dealerId,
        'imei': _imei,
        'authtoken': SessionService.instance.authToken,
      };

  // ── getCustomerBoxes (gcb) ──────────────────────────────────────────────────
  Future<CustomerBoxesResult> getCustomerBoxes(String customerId) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getCustomerBoxes'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final ext = '${data['service_extension'] ?? ''}';
      final boxes = <CustomerBox>[];
      final ottBoxes = <CustomerBox>[];
      if (status == 0) {
        final list = decodeDynamic(data['customer_boxes']);
        if (list is List) {
          for (final b in list) {
            if (b is Map) {
              boxes.add(CustomerBox.fromJson(Map<String, dynamic>.from(b)));
            }
          }
        }
        // ott_boxes_list drives the OTT operation (Android CustomerOperations:2733).
        final ott = decodeDynamic(data['ott_boxes_list']);
        if (ott is List) {
          for (final b in ott) {
            if (b is Map) {
              ottBoxes.add(CustomerBox.fromJson(Map<String, dynamic>.from(b)));
            }
          }
        }
      }
      return CustomerBoxesResult(status, msg, boxes, ext, ottBoxes);
    } on TimeoutException {
      return const CustomerBoxesResult(3, 'Request timed out.', [], '');
    } catch (_) {
      return const CustomerBoxesResult(3, 'Could not connect to server.', [], '');
    }
  }

  // ── getCustomerPackages (gcp) — actType: 1=activation list, 2=deactivation ──
  Future<CustomerPackagesResult> getCustomerPackages({
    required String customerId,
    required String boxId,
    required String casId,
    required int actType,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getCustomerpackages'),
        {
          ..._auth,
          'customer_id': customerId,
          'box_id': boxId,
          'cas_id': casId,
          'act_type': '$actType',
        },
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final base = <Package>[];
      final addOn = <Package>[];
      final ala = <Package>[];
      if (status == 0) {
        final obj = decodeDynamic(data['customer_packages']);
        if (obj is Map) {
          _fill(obj['is_base'], PackageCategory.base, base);
          _fill(obj['is_add_on'], PackageCategory.addOn, addOn);
          _fill(obj['is_al_a_carte'], PackageCategory.alaCarte, ala);
        }
      }
      return CustomerPackagesResult(status, msg, base, addOn, ala);
    } on TimeoutException {
      return const CustomerPackagesResult(3, 'Request timed out.', [], [], []);
    } catch (_) {
      return const CustomerPackagesResult(
          3, 'Could not connect to server.', [], [], []);
    }
  }

  static void _fill(dynamic raw, PackageCategory cat, List<Package> out) {
    final list = decodeDynamic(raw);
    if (list is List) {
      for (final p in list) {
        if (p is Map) {
          out.add(Package.fromJson(Map<String, dynamic>.from(p), cat));
        }
      }
    }
  }

  // ── getCustomerPackageList / getcustomerpackageslist (gcpl) ─────────────────
  // Android sends `customerId` (camelCase) + `box_id` + `status` here.
  Future<ActivePackagesResult> getCustomerPackageList({
    required String customerId,
    required String boxId,
    required String status,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getcustomerpackageslist'),
        {
          'dealer_id': SessionService.instance.dealerId,
          'box_id': boxId,
          'customerId': customerId,
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
          'status': status,
        },
        timeout: const Duration(seconds: 70),
      );
      final code = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final packages = <ActivePackage>[];
      if (code == 0) {
        final list = decodeDynamic(data['total_packages_list']);
        if (list is List) {
          for (final p in list) {
            if (p is Map) {
              packages.add(ActivePackage.fromJson(Map<String, dynamic>.from(p)));
            }
          }
        }
      }
      return ActivePackagesResult(code, msg, packages);
    } on TimeoutException {
      return const ActivePackagesResult(3, 'Request timed out.', []);
    } catch (_) {
      return const ActivePackagesResult(3, 'Could not connect to server.', []);
    }
  }

  // ── Customerpackageoperations (cpo) — ACTIVATE (act_type=1) ─────────────────
  // Verified default path for qty_seletion_view=0 dealers: each selected package
  // is sent with ptype "1" and month "1" (no quantity selector). The three CSVs
  // mirror Android FilterTool (packages=id; service_type_val=id##ptype;
  // month_val=id##month). See PACKAGE_OPERATIONS_COMPLETE.md §cpo ACTIVATE.
  Future<PackageWriteResult> activatePackages({
    required String customerId,
    required String boxId,
    required List<String> packageIds,
  }) async {
    if (packageIds.isEmpty) {
      return const PackageWriteResult(3, 'No packages selected.');
    }
    final packages = packageIds.join(',');
    final serviceTypeVal = packageIds.map((id) => '$id##1').join(',');
    final monthVal = packageIds.map((id) => '$id##1').join(',');
    try {
      final data = await RestClient.instance.postForm(
        _url('Customerpackageoperations'),
        {
          ..._auth,
          'customer_id': customerId,
          'box_id': boxId,
          'packages': packages,
          'service_type_val': serviceTypeVal,
          'month_val': monthVal,
          'act_type': '1',
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── Customerdeactivereasons (cdr) — per-box deactivation reasons LOV ─────────
  // VERIFIED per-box request: ONLY imei + authtoken (Frag_Deactpack:940-949).
  Future<DeactivateReasonsResult> getDeactivateReasons() async {
    try {
      final data = await RestClient.instance.postForm(
        _url('Customerdeactivereasons'),
        {
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      final code = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final reasons = <DeactivateReason>[];
      if (code == 0) {
        final list = decodeDynamic(data['deactive_reasons']);
        if (list is List) {
          for (final r in list) {
            if (r is Map) {
              reasons
                  .add(DeactivateReason.fromJson(Map<String, dynamic>.from(r)));
            }
          }
        }
      }
      return DeactivateReasonsResult(code, msg, reasons);
    } on TimeoutException {
      return const DeactivateReasonsResult(3, 'Request timed out.', []);
    } catch (_) {
      return const DeactivateReasonsResult(
          3, 'Could not connect to server.', []);
    }
  }

  // ── Customerpackageoperations (cpo) — DEACTIVATE (act_type=2) ───────────────
  // VERIFIED (Frag_Deactpack:1223-1234): packages CSV + deact_reason only — NO
  // service_type_val/month_val. Caller must enforce reasonId > 0 (cdr "Select").
  Future<PackageWriteResult> deactivatePackages({
    required String customerId,
    required String boxId,
    required List<String> packageIds,
    required int reasonId,
  }) async {
    if (packageIds.isEmpty) {
      return const PackageWriteResult(3, 'No packages selected.');
    }
    try {
      final data = await RestClient.instance.postForm(
        _url('Customerpackageoperations'),
        {
          ..._auth,
          'customer_id': customerId,
          'box_id': boxId,
          'packages': packageIds.join(','),
          'act_type': '2',
          'deact_reason': '$reasonId',
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── Customerpackageoperations (cpo) — SCHEDULE (act_type=7) ─────────────────
  // VERIFIED (SchedulePackage_frag:846-853): packages CSV + schedule_start_date
  // (dd-MM-yyyy, strictly future) — NO service_type_val/month_val/deact_reason.
  Future<PackageWriteResult> schedulePackages({
    required String customerId,
    required String boxId,
    required List<String> packageIds,
    required String scheduleStartDate, // dd-MM-yyyy
  }) async {
    if (packageIds.isEmpty) {
      return const PackageWriteResult(3, 'No packages selected.');
    }
    try {
      final data = await RestClient.instance.postForm(
        _url('Customerpackageoperations'),
        {
          ..._auth,
          'customer_id': customerId,
          'box_id': boxId,
          'packages': packageIds.join(','),
          'schedule_start_date': scheduleStartDate,
          'act_type': '7',
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── reactivateBox (rbox) — VERIFIED (Box_Selection_new:513-523) ─────────────
  // customer_id = the box's customer_id (NOT lcoCustomerId). Response status 0 and
  // 1 both navigate home in production; transport error → "Failed" (caller handles).
  Future<PackageWriteResult> reactivateBox({
    required String customerId,
    required String boxId,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('reactivateBox'),
        {..._auth, 'customer_id': customerId, 'box_id': boxId},
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── stbTemporaryActivation (sta) — VERIFIED (CustomerOperations_Fragment:3333-3416)
  // customer_id = the customer's customer_id (Flutter lcoCustomerId). Android reads
  // ONLY status_code + status_msg from the response (no other business fields).
  // status 0 = success · 1 = backend-rejected · 3 = transport.
  Future<PackageWriteResult> stbTemporaryActivation({
    required String customerId,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('stbTemporaryActivation'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── unpaidCustomerActivation (uca) — VERIFIED (CustomerOperations_Fragment:3225-3320)
  // customer_id = the customer's customer_id (== Flutter lcoCustomerId). Reads ONLY
  // status_code + status_msg. 0 = success · 1 = "No Details Found" · 3 = transport.
  Future<PackageWriteResult> unpaidCustomerActivation({
    required String customerId,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('unpaidCustomerActivation'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── packageRenew (pr) — VERIFIED (CustomerOperations_Fragment:2870-2968) ─────
  // STB "Renew Services". customer_id = the customer's customer_id (Android
  // `customersidd`, populated on load via packageoperations(0); == Flutter
  // lcoCustomerId). Reads ONLY status_code + status_msg. 0 = success · 1 =
  // rejected · 3 = transport. (The "Renew BroadBand" variant is a separate
  // feature — editcustomer → BroadBandList — and is NOT this call.)
  Future<PackageWriteResult> packageRenew({
    required String customerId,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('packageRenew'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── customerServicesExtendWithStock (csews) — box-wise Service Extension ─────
  // VERIFIED (Box_Selection_new:317-414): req dealer_id, customer_id, imei,
  // authtoken, box_id, stock_id. customer_id = the box's customer_id.
  Future<PackageWriteResult> serviceExtensionWithBox({
    required String customerId,
    required String boxId,
    required String stockId,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('customerServicesExtendWithStock'),
        {
          ..._auth,
          'customer_id': customerId,
          'box_id': boxId,
          'stock_id': stockId,
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }
  // ── serviceExtension (serext) — per-package Extend Service (the [+] inside
  // Remove Services). VERIFIED (DeactiveAdapter_listview.java:200-289;
  // configg serext=/packagelist/serviceExtension). POST params: dealer_id, imei,
  // authtoken, customer_id, product_id (= package_id), quantity=1, box_id,
  // act_type=1, pricing_structure_type.
  Future<PackageWriteResult> serviceExtension({
    required String customerId,
    required String boxId,
    required String productId,
    required String pricingStructureType,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('serviceExtension'),
        {
          ..._auth,
          'customer_id': customerId,
          'product_id': productId,
          'quantity': '1',
          'box_id': boxId,
          'act_type': '1',
          'pricing_structure_type': pricingStructureType,
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── updateMobileAndLCOCustID (upmoblcoid) — edit the customer's LCO id ───────
  // VERIFIED (CustomerOperations_Fragment:2976-3103; configg.properties
  // upmoblcoid=/packagelist/updateMobileAndLCOCustID). POST params: dealer_id,
  // customerId (= customersidd == Flutter lcoCustomerId — the STABLE key that
  // identifies the customer; it is NOT the value being changed), imei, authtoken,
  // employeeId, updateType="LCO_customer_id", updateValue=<new LCO id>.
  // status_code: 0 = success · 1 = backend-rejected (show status_msg) · 3 =
  // transport. Android validates the new id is >= 5 chars before calling
  // (row_updatelcoidview). The mobile edit is the same call with
  // updateType="mobile" / updateValue="91"+number.
  Future<PackageWriteResult> updateLcoCustomerId({
    required String customerId,
    required String newLcoId,
  }) =>
      _updateMobileOrLcoId(customerId, 'LCO_customer_id', newLcoId);

  /// Same API as [updateLcoCustomerId] — Android igv_editmob →
  /// update_Lco_or_mobile("", mobile): updateType="mobile",
  /// updateValue="91"+<10-digit number>.
  Future<PackageWriteResult> updateMobileNumber({
    required String customerId,
    required String newMobile,
  }) =>
      _updateMobileOrLcoId(customerId, 'mobile', '91$newMobile');

  Future<PackageWriteResult> _updateMobileOrLcoId(
    String customerId,
    String updateType,
    String updateValue,
  ) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('updateMobileAndLCOCustID'),
        {
          ..._auth,
          'customerId': customerId,
          'employeeId': SessionService.instance.employeeId,
          'updateType': updateType,
          'updateValue': updateValue,
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── STB Deactivation reasons — gdr (getDeactiveReasons, SOAP) ───────────────
  // VERIFIED (Deactivatestb_Frag_New:388-468): wrapper reasonsInfo/DeactivateReasonsInfo,
  // fields showforlco=0, authToken, imei; response = repeated <reasonList>{reasonId,
  // reasonName}. (This is gdr/SOAP — distinct from the per-box cdr/REST.)
  Future<DeactivateReasonsResult> getStbDeactivateReasons() async {
    final ns = ServerUrlResolver.instance.namespace;
    final url = ServerUrlResolver.instance.loginServerUrl;
    if (ns.isEmpty || url.isEmpty) {
      return const DeactivateReasonsResult(3, 'Server not ready.', []);
    }
    try {
      final xml = await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/getDeactiveReasons',
        methodName: 'getDeactiveReasons',
        wrapper: 'reasonsInfo',
        wrapperType: 'DeactivateReasonsInfo',
        fields: {
          'showforlco': 0,
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
        },
        timeout: const Duration(seconds: 70),
      );
      // C8 / Android Deactivatestb_Frag_New Deactivation_Reasons (:491-525):
      // the reasons are used only when statusCode is 0; 1 and 2 come with
      // statusMessage. A reply without a statusCode counts as a failed call (3).
      final status =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      final message = SoapClient.readField(xml, 'statusMessage') ?? '';
      final reasons = <DeactivateReason>[];
      if (status == 0) {
        for (final item in SoapClient.readAll(xml, 'reasonList')) {
          final id =
              int.tryParse(SoapClient.readField(item, 'reasonId') ?? '') ?? -1;
          final name = (SoapClient.readField(item, 'reasonName') ?? '').trim();
          if (id >= 0) reasons.add(DeactivateReason(id, name));
        }
      }
      return DeactivateReasonsResult(status, message, reasons);
    } on SoapException {
      return const DeactivateReasonsResult(3, 'Server error.', []);
    } on TimeoutException {
      return const DeactivateReasonsResult(3, 'Request timed out.', []);
    } catch (_) {
      return const DeactivateReasonsResult(3, 'Could not connect to server.', []);
    }
  }

  // ── deactivateSTB (ds, REST) — non-17 reasons ──────────────────────────────
  // VERIFIED (Deactivatestb_Frag_New:787-796).
  Future<PackageWriteResult> deactivateStbRest({
    required int reasonId,
    required String serialNumber,
    required String boxId,
    required String customerId,
    required String lat,
    required String lang,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('deactivateSTB'),
        {
          'dealer_id': SessionService.instance.dealerId,
          'reasonId': '$reasonId',
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
          'serialNumber': serialNumber,
          'lat': lat,
          'lang': lang,
          'box_id': boxId,
          'customer_id': customerId,
        },
        timeout: const Duration(seconds: 70),
      );
      return PackageWriteResult(statusCodeOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }

  // ── deactivateBox (db, SOAP) — reasonId 17 ("Unpaid Customer") ──────────────
  // VERIFIED (Deactivatestb_Frag_New:575-600): wrapper deactivateSTB_info/
  // DeactivateSTB_Info; SOAP response uses camelCase statusCode/statusMessage.
  Future<PackageWriteResult> deactivateBoxSoap({
    required int reasonId,
    required String serialNumber,
    required String boxId,
    required String customerId,
    required String lat,
    required String lang,
  }) async {
    final ns = ServerUrlResolver.instance.namespace;
    final url = ServerUrlResolver.instance.loginServerUrl;
    if (ns.isEmpty || url.isEmpty) {
      return const PackageWriteResult(3, 'Server not ready.');
    }
    try {
      final xml = await SoapClient.instance.call(
        url: url,
        namespace: ns,
        soapAction: '$ns/deactivateBox',
        methodName: 'deactivateBox',
        wrapper: 'deactivateSTB_info',
        wrapperType: 'DeactivateSTB_Info',
        fields: {
          'authToken': SessionService.instance.authToken,
          'imei': _imei,
          'reasonId': reasonId,
          'serialNumber': serialNumber,
          'lat': lat,
          'lang': lang,
          'box_id': int.tryParse(boxId) ?? boxId,
          'customer_id': int.tryParse(customerId) ?? customerId,
        },
        timeout: const Duration(seconds: 70),
      );
      final code =
          int.tryParse(SoapClient.readField(xml, 'statusCode') ?? '') ?? 3;
      final msg = SoapClient.readField(xml, 'statusMessage') ?? '';
      return PackageWriteResult(code, msg);
    } on SoapException {
      return const PackageWriteResult(3, 'Server error.');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }
}
