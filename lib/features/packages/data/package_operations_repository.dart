import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
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
  const CustomerBoxesResult(
      this.statusCode, this.statusMessage, this.boxes, this.serviceExtension);
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

  /// Backend double-encodes nested arrays/objects as JSON strings; decode safely.
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

  static int _statusOf(Map<String, dynamic> data) {
    final v = data['status_code'];
    return v is int ? v : (int.tryParse('$v') ?? 3);
  }

  // ── getCustomerBoxes (gcb) ──────────────────────────────────────────────────
  Future<CustomerBoxesResult> getCustomerBoxes(String customerId) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getCustomerBoxes'),
        {..._auth, 'customer_id': customerId},
        timeout: const Duration(seconds: 70),
      );
      final status = _statusOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final ext = '${data['service_extension'] ?? ''}';
      final boxes = <CustomerBox>[];
      if (status == 0) {
        final list = _decode(data['customer_boxes']);
        if (list is List) {
          for (final b in list) {
            if (b is Map) {
              boxes.add(CustomerBox.fromJson(Map<String, dynamic>.from(b)));
            }
          }
        }
      }
      return CustomerBoxesResult(status, msg, boxes, ext);
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
      final status = _statusOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final base = <Package>[];
      final addOn = <Package>[];
      final ala = <Package>[];
      if (status == 0) {
        final obj = _decode(data['customer_packages']);
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
    final list = _decode(raw);
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
      final code = _statusOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final packages = <ActivePackage>[];
      if (code == 0) {
        final list = _decode(data['total_packages_list']);
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
      return PackageWriteResult(_statusOf(data), '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return const PackageWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const PackageWriteResult(3, 'Could not connect to server.');
    }
  }
}
