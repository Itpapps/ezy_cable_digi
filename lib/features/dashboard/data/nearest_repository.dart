import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// One nearest-customer row from `NearestNextCustomer` (Android `nnc`).
/// The server returns parallel arrays — we zip them into these objects.
class NearestCustomerItem {
  final String name;
  final String altCustomNumber;
  final String distance;
  final double latitude;
  final double longitude;

  const NearestCustomerItem({
    this.name = '',
    this.altCustomNumber = '',
    this.distance = '',
    this.latitude = 0,
    this.longitude = 0,
  });
}

/// Result of the Nearest customers REST call.
class NearestListResult {
  final int statusCode; // 0 ok · 1 no records · 3 transport/parse error
  final String statusMessage;
  final List<NearestCustomerItem> customers;
  const NearestListResult(this.statusCode, this.statusMessage, this.customers);
}

/// Nearest customers — REST POST (`/digi_rest_api/NearestNextCustomer`),
/// Android source of truth: `DashboardHomeFragment` → `NearestNextCustomer` (config key `nnc`).
/// Response carries parallel arrays (`distance[]`, `name[]`, `alt_custom_number[]`,
/// `latitude[]`, `longitude[]`). Defensive: any failure returns a safe result.
class NearestRepository {
  NearestRepository._();
  static final NearestRepository instance = NearestRepository._();

  static String get _imei => AppConfig.deviceImei;

  String get _url =>
      '${ServerUrlResolver.instance.namespace}/packagelist/NearestNextCustomer';

  Future<NearestListResult> fetchNearest({
    required double lat,
    required double lng,
    String distanceKm = '2',
    bool fromDashboard = true,
  }) async {
    try {
      final data = await RestClient.instance.postForm(
        _url,
        {
          'dealer_id': SessionService.instance.dealerId,
          'lat': lat.toString(),
          'lang': lng.toString(),
          'imei': _imei,
          'authtoken': SessionService.instance.authToken,
          'distance_km': distanceKm,
          'from_dashboard': fromDashboard ? '1' : '0',
        },
        timeout: const Duration(seconds: 10),
      );

      final code = int.tryParse('${data['status_code'] ?? ''}') ?? 3;
      final msg = '${data['status_msg'] ?? ''}';

      if (code != 0) {
        return NearestListResult(code, msg, const []);
      }

      // Parallel arrays → zip into objects
      final names = _toList(data['name']);
      final altNums = _toList(data['alt_custom_number']);
      final distances = _toList(data['distance']);
      final lats = _toList(data['latitude']);
      final lngs = _toList(data['longitude']);

      final count = names.length;
      final items = <NearestCustomerItem>[];
      for (int i = 0; i < count; i++) {
        items.add(NearestCustomerItem(
          name: i < names.length ? names[i] : '',
          altCustomNumber: i < altNums.length ? altNums[i] : '',
          distance: i < distances.length ? distances[i] : '',
          latitude: i < lats.length ? (double.tryParse(lats[i]) ?? 0) : 0,
          longitude: i < lngs.length ? (double.tryParse(lngs[i]) ?? 0) : 0,
        ));
      }

      return NearestListResult(0, msg, items);
    } on TimeoutException {
      return const NearestListResult(3, 'Request timed out.', []);
    } catch (_) {
      return const NearestListResult(3, 'Could not connect to server.', []);
    }
  }

  static List<String> _toList(dynamic v) {
    if (v is List) return v.map((e) => '$e').toList();
    return const [];
  }
}
