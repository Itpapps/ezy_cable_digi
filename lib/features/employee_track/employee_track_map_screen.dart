import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data/employee_collection.dart';

/// Employee operation-track map — Android parity (`MapsActivityEmp`): plots the
/// GPS points where an employee performed the selected operation type. Points
/// without usable coordinates are skipped.
class EmployeeTrackMapScreen extends StatelessWidget {
  final String title;
  final List<EmployeeTrackPoint> points;
  const EmployeeTrackMapScreen({
    super.key,
    required this.title,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final located = points.where((p) => p.hasLocation).toList();
    final markers = <Marker>{
      for (var i = 0; i < located.length; i++)
        Marker(
          markerId: MarkerId('pt_$i'),
          position: LatLng(located[i].latitude!, located[i].longitude!),
          infoWindow: InfoWindow(
            title: located[i].displayName.isEmpty
                ? 'Point ${i + 1}'
                : located[i].displayName,
            snippet: located[i].createdDate,
          ),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ),
      body: located.isEmpty
          ? const Center(
              child: Text('No location points to display',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                target:
                    LatLng(located.first.latitude!, located.first.longitude!),
                zoom: 13,
              ),
              markers: markers,
              myLocationEnabled: false,
              compassEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
    );
  }
}
