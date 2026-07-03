import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'broadband_plan.dart';

/// Result of `broadband_expiry_list` (bblist).
class BroadbandExpiryResult {
  final int statusCode; // 0 ok · 1 error(msg) · 3 transport
  final String statusMessage;
  final List<BroadBandPlan> renewedList; // broadband_renewedlist_data (current plan)
  final List<BroadBandPlan> expiryList; // expiry_list
  const BroadbandExpiryResult(
      this.statusCode, this.statusMessage, this.renewedList, this.expiryList);
  bool get isSuccess => statusCode == 0;
}

/// Renew BroadBand — Android parity (`BroadBandList` fragment). Encrypted REST
/// (`/digi_rest_api/...`, same envelope as Pay Later / Calendar): list via
/// `broadband_expiry_list`, renew via `broadband_renew_customers`. Defensive:
/// any failure returns a safe result (never throws to the UI).
class BroadbandRepository {
  BroadbandRepository._();
  static final BroadbandRepository instance = BroadbandRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

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

  static List<BroadBandPlan> _parseList(dynamic raw) {
    final out = <BroadBandPlan>[];
    final list = _decode(raw);
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          out.add(BroadBandPlan.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return out;
  }

  /// Fetch the customer's broadband plan + expiry list (Android
  /// `getHitapibroadbanddata` → `broadband_expiry_list`).
  Future<BroadbandExpiryResult> fetchExpiryList(String broadbandUserId) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('broadband_expiry_list'),
        {
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
          'dealer_id': SessionService.instance.dealerId,
          'employee_id': SessionService.instance.employeeId,
          'broadband_user_id': broadbandUserId,
          'request_from': 'FromDigiApp',
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return BroadbandExpiryResult(
            1, '${data['Error_Message'] ?? 'No records'}', const [], const []);
      }
      return BroadbandExpiryResult(
        0,
        '',
        _parseList(data['broadband_renewedlist_data']),
        _parseList(data['expiry_list']),
      );
    } on TimeoutException {
      return const BroadbandExpiryResult(3, 'Request timed out.', [], []);
    } catch (_) {
      return const BroadbandExpiryResult(
          3, 'Could not connect to server.', [], []);
    }
  }

  /// Renew the broadband plan (Android `gethitrenew` → `broadband_renew_customers`).
  /// Returns statusCode 0 = success (status_message) · 1 = backend error
  /// (Error_Message) · 3 = transport.
  Future<({int statusCode, String message})> renewBroadband({
    required String broadbandUserId,
    required String customerId,
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('broadband_renew_customers'),
        {
          'broadband_user_id': broadbandUserId,
          'customer_id': customerId,
          'dealer_id': SessionService.instance.dealerId,
          'employee_id': SessionService.instance.employeeId,
          'request_from': 'FromDigiApp',
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return (statusCode: 1, message: '${data['Error_Message'] ?? 'Failed'}');
      }
      return (statusCode: 0, message: '${data['status_message'] ?? 'Success'}');
    } on TimeoutException {
      return (statusCode: 3, message: 'Request timed out.');
    } catch (_) {
      return (statusCode: 3, message: 'Could not connect to server.');
    }
  }
}
