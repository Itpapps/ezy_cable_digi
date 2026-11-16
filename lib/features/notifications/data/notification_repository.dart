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
  /// Issue 2 / Android MainActivity.fetchLoginNotifications (:1034-1090): ONE
  /// request via ApiCallRestClient.callPostApiSilent, which reads the decrypted
  /// `payload` first and falls back to `hash` only when it is a real response.
  /// Flutter used to read `hash` alone (two requests) — when the server echoes
  /// the request there, nothing showed even though Android showed the popup.
  /// Any failure → empty list (silent, like Android).
  Future<List<LoginNotification>> fetchLoginNotifications() async {
    final url = _url('login_notifications');
    final params = {
      'dealer_id': SessionService.instance.dealerId,
      'imei': AppConfig.deviceImei,
      'authtoken': SessionService.instance.authToken,
      'employee_id': SessionService.instance.employeeId,
    };

    try {
      final data = await RestClient.instance.postEncryptedSilent(url, params,
          timeout: const Duration(seconds: 30)); // Android retry policy 30 s
      if (kDebugMode) {
        debugPrint('[LOGIN-NOTIF] response = '
            '${const JsonEncoder.withIndent('  ').convert(data)}');
      }
      return _parse(data);
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN-NOTIF] failed: $e');
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
