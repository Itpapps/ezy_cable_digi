import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'custom_package.dart';

/// Result of `getDigiDealerPackages` (gddp). `statusCode == 1` = none (msg).
class CustomPackagesListResult {
  final int statusCode; // 0 ok · 1 none · 3 transport
  final String statusMessage;
  final List<CustomPackage> packages;
  const CustomPackagesListResult(
      this.statusCode, this.statusMessage, this.packages);
  bool get isSuccess => statusCode == 0;
}

/// Custom Packages — Android parity (`DigiPackage_Home` module). Phase C, step 1:
/// the list read (`getDigiDealerPackages`, plain `/packagelist/` REST) shared by
/// the Activation (`act_type=1`) and Deactivation (`act_type=2`) flows. The write
/// (`insertDigiDealerPackages`/`iddp`) is added with the cart screens (steps 2/3).
class CustomPackagesRepository {
  CustomPackagesRepository._();
  static final CustomPackagesRepository instance = CustomPackagesRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/packagelist/$method';

  Map<String, String> get _auth => {
        'dealer_id': SessionService.instance.dealerId,
        'imei': _imei,
        'authtoken': SessionService.instance.authToken,
      };

  /// [actType] "1" = activation list, "2" = deactivation list (Android
  /// CustomPackages_Activation/Deactivation).
  Future<CustomPackagesListResult> getDigiDealerPackages({
    required String customerId,
    required String actType,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('getDigiDealerPackages'),
        {..._auth, 'customer_id': customerId, 'act_type': actType},
        timeout: const Duration(seconds: 70),
      );
      final status = statusCodeOf(data);
      final msg = '${data['status_msg'] ?? ''}';
      final packages = <CustomPackage>[];
      if (status == 0) {
        final list = decodeDynamic(data['digi_dealer_packages']);
        if (list is List) {
          for (final p in list) {
            if (p is Map) {
              packages.add(CustomPackage.fromJson(Map<String, dynamic>.from(p)));
            }
          }
        }
      }
      return CustomPackagesListResult(status, msg, packages);
    } on TimeoutException {
      return const CustomPackagesListResult(3, 'Request timed out.', []);
    } catch (_) {
      return const CustomPackagesListResult(
          3, 'Could not connect to server.', []);
    }
  }

  /// Activate selected custom packages — Android parity (`BillDetails_Act` →
  /// `insertDigiDealerPackages`/`iddp`). All list args are COMMA-joined in the
  /// SAME selection order (Android `convertStringArrayToString1(...,",")`):
  /// [packages]=package_ids, [startDate]=start_dates, [months]=quantities,
  /// [autorenewal]="0"/"1" per package. status 0 = success (status_msg) · 1 =
  /// "No Data Found" · 3 = transport.
  Future<({int statusCode, String message})> activatePackages({
    required String customerId,
    required String packages,
    required String startDate,
    required String months,
    required String autorenewal,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('insertDigiDealerPackages'),
        {
          ..._auth,
          'customer_id': customerId,
          'packages': packages,
          'start_date': startDate,
          'months': months,
          'autorenewal': autorenewal,
          'act_type': '1',
        },
        timeout: const Duration(seconds: 70),
      );
      return (statusCode: statusCodeOf(data), message: '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return (statusCode: 3, message: 'Request timed out.');
    } catch (_) {
      return (statusCode: 3, message: 'Could not connect to server.');
    }
  }

  /// Deactivate selected custom packages — Android parity (`DigiPackages_deactivation`
  /// → `iddp`). Comma-joined [packages]=ids, [autorenewal]="0"/"1"; act_type="2".
  Future<({int statusCode, String message})> deactivatePackages({
    required String customerId,
    required String packages,
    required String autorenewal,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('insertDigiDealerPackages'),
        {
          ..._auth,
          'customer_id': customerId,
          'packages': packages,
          'autorenewal': autorenewal,
          'act_type': '2',
        },
        timeout: const Duration(seconds: 70),
      );
      return (statusCode: statusCodeOf(data), message: '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return (statusCode: 3, message: 'Request timed out.');
    } catch (_) {
      return (statusCode: 3, message: 'Could not connect to server.');
    }
  }

  /// Enable/disable auto-extension for a single package — Android parity
  /// (`DigiPackagesDeactAdapter.getdigiselectedpackact` → `iddp` act_type=2 with
  /// `enable_custome_package`). [enable] "1" = enable · "0" = disable.
  Future<({int statusCode, String message})> setPackageAutoRenewal({
    required String customerId,
    required String packageId,
    required String autorenewal,
    required String enable,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url('insertDigiDealerPackages'),
        {
          ..._auth,
          'customer_id': customerId,
          'packages': packageId,
          'autorenewal': autorenewal,
          'act_type': '2',
          'enable_custome_package': enable,
        },
        timeout: const Duration(seconds: 70),
      );
      return (statusCode: statusCodeOf(data), message: '${data['status_msg'] ?? ''}');
    } on TimeoutException {
      return (statusCode: 3, message: 'Request timed out.');
    } catch (_) {
      return (statusCode: 3, message: 'Could not connect to server.');
    }
  }
}
