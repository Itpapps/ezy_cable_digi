import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';

class DirectionsRepository {
  DirectionsRepository._();
  static final DirectionsRepository instance = DirectionsRepository._();

  Future<List<LatLng>> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final apiKey = AppConfig.instance.googleMapsApiKey;
    if (apiKey.isEmpty) return const [];
    try {
      final url = Uri.https(
        'maps.googleapis.com',
        '/maps/api/directions/json',
        <String, String>{
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'key': apiKey,
        },
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return const [];

      final routes = (data['routes'] as List<dynamic>?) ?? [];
      if (routes.isEmpty) return const [];

      final route = routes.first as Map<String, dynamic>;
      final overview =
          (route['overview_polyline'] as Map<String, dynamic>?) ?? {};
      final encoded = overview['points'] as String?;
      if (encoded == null || encoded.isEmpty) return const [];

      return _decodePolyline(encoded);
    } catch (_) {
      return const [];
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }
}
