import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'; // debugPrint + kDebugMode

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'login_notification.dart';

class NotificationRepository {
  NotificationRepository._();
  static final NotificationRepository instance = NotificationRepository._();

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

  /// ALL active login notifications (newest-first), or empty on none/error.
  ///
  /// DIAGNOSTIC (TEMPORARY): currently parses the response `hash`, because the
  /// server's `payload` returns empty for this endpoint. Once the backend fixes
  /// `payload`, return `_parse(data)` from the PAYLOAD block and delete the HASH
  /// block + `RestClient.postEncryptedHash` + `DigiCrypto.hexToString`.
  Future<List<LoginNotification>> fetchLoginNotifications() async {
    final url = _url('login_notifications');
    final params = {
      'dealer_id': SessionService.instance.dealerId,
      'imei': AppConfig.deviceImei,
      'authtoken': SessionService.instance.authToken,
      'employee_id': SessionService.instance.employeeId,
    };

    // ── PAYLOAD (documented/production path) — logged for comparison ──
    try {
      final data = await RestClient.instance
          .postEncrypted(url, params, timeout: const Duration(seconds: 30));
      if (kDebugMode) {
        debugPrint('[LOGIN-NOTIF] PAYLOAD = '
            '${const JsonEncoder.withIndent('  ').convert(data)}');
      }
      // TODO(after backend fixes payload): return _parse(data); remove HASH block.
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN-NOTIF] PAYLOAD failed: $e');
    }

    // ── HASH (DIAGNOSTIC — the server currently puts the data here) ──
    try {
      final data = await RestClient.instance
          .postEncryptedHash(url, params, timeout: const Duration(seconds: 30));
      if (kDebugMode) {
        debugPrint('[LOGIN-NOTIF] HASH = '
            '${const JsonEncoder.withIndent('  ').convert(data)}');
      }
      return _parse(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN-NOTIF] HASH failed: $e');
    }

    return const [];
  }

  /// Parse `login_notifications` (the array) into models. Defensive — a bad
  /// item is skipped, never throws to the UI.
  List<LoginNotification> _parse(Map<String, dynamic> data) {
    if ('${data['status_code']}' != '0') return const [];
    final list = data['login_notifications'];
    if (list is! List) return const [];
    final out = <LoginNotification>[];
    for (final item in list) {
      if (item is Map) {
        out.add(LoginNotification.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }
}
