import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/response_helpers.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';
import 'calendar_event.dart';

class CalendarListResult {
  final int statusCode; // 0 ok · 1 error(msg) · 3 transport
  final String statusMessage;
  final List<CalendarEvent> events;
  const CalendarListResult(this.statusCode, this.statusMessage, this.events);
  bool get isSuccess => statusCode == 0;
}

class CalendarWriteResult {
  final int statusCode; // 0 ok · 1 error(msg) · 3 transport
  final String statusMessage;
  const CalendarWriteResult(this.statusCode, this.statusMessage);
  bool get isSuccess => statusCode == 0;
}

/// Calendar CRUD — Android parity (CalenderFragment / EventListAdapter).
/// List → `/digi_rest_api/calender_data`; Add/Update/Delete →
/// `/digi_rest_api/calender_event`. Reuses the shared encrypted REST client
/// ([RestClient.postEncrypted]) — the same one Pay Later uses. Defensive.
class CalendarRepository {
  CalendarRepository._();
  static final CalendarRepository instance = CalendarRepository._();

  static String get _imei => AppConfig.deviceImei;

  String _url(String method) =>
      '${ServerUrlResolver.instance.namespace}/digi_rest_api/$method';

  /// List events between two dates (Android gethitapiexpensesList, `calender_data`).
  Future<CalendarListResult> list({
    required String startDate, // yyyy-MM-dd
    required String endDate,
  }) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('calender_data'),
        {
          'start_date': startDate,
          'end_date': endDate,
          'dealer_id': SessionService.instance.dealerId,
          'selected_employee_id': SessionService.instance.employeeId,
          'request_from': 'FromDigiApp',
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
        },
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return CalendarListResult(
            1, '${data['Error_Message'] ?? 'No records'}', const []);
      }
      final events = <CalendarEvent>[];
      final list = decodeDynamic(data['events_list']);
      if (list is List) {
        for (final e in list) {
          if (e is Map) {
            events.add(CalendarEvent.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      return CalendarListResult(0, '', events);
    } on TimeoutException {
      return const CalendarListResult(3, 'Request timed out.', []);
    } catch (_) {
      return const CalendarListResult(3, 'Could not connect to server.', []);
    }
  }

  /// Add (empty [eventId]) or Update (non-empty [eventId]) an event
  /// (Android `calender_event`). Returns the server `status_message`.
  Future<CalendarWriteResult> save({
    required String title,
    required String startDate,
    required String endDate,
    String eventId = '',
  }) async {
    final params = <String, String>{
      'start_date': startDate,
      'end_date': endDate,
      'event_title': title,
      'dealer_id': SessionService.instance.dealerId,
      'employee_id': SessionService.instance.employeeId,
      'request_from': 'FromDigiApp',
      'imei': _imei,
      'authtoken': SessionService.instance.authToken,
    };
    if (eventId.isNotEmpty) {
      params['calendar_event_id'] = eventId; // update
    }
    return _write(params);
  }

  /// Delete an event (Android `calender_event` with is_event_deleted=1).
  Future<CalendarWriteResult> delete({
    required String eventId,
    required String title,
    required String startDate,
    required String endDate,
    String remarks = '',
  }) async {
    return _write({
      'start_date': startDate,
      'end_date': endDate,
      'event_title': title,
      'dealer_id': SessionService.instance.dealerId,
      'employee_id': SessionService.instance.employeeId,
      'request_from': 'FromDigiApp',
      'imei': _imei,
      'authtoken': SessionService.instance.authToken,
      'calendar_event_id': eventId,
      'is_event_deleted': '1',
      'event_delete_remarks': remarks,
    });
  }

  Future<CalendarWriteResult> _write(Map<String, String> params) async {
    try {
      final data = await RestClient.instance.postEncrypted(
        _url('calender_event'),
        params,
        timeout: const Duration(seconds: 70),
      );
      if (data.containsKey('Error_code')) {
        return CalendarWriteResult(1, '${data['Error_Message'] ?? 'Failed'}');
      }
      final msg = (data['status_message'] ?? 'Success').toString();
      return CalendarWriteResult(0, msg);
    } on TimeoutException {
      return const CalendarWriteResult(3, 'Request timed out.');
    } catch (_) {
      return const CalendarWriteResult(3, 'Could not connect to server.');
    }
  }
}
