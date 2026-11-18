import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationPreviewScreen extends StatelessWidget {
  final String customerName;
  final String areaName;
  final LatLng location;

  /// Android MapsFragmentlocupdate SEND: the save confirm + server call run
  /// while this map is still open, so a failure leaves the user here.
  final Future<void> Function(BuildContext context) onSend;

  const LocationPreviewScreen({
    super.key,
    required this.customerName,
    required this.areaName,
    required this.location,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LOCATION PREVIEW')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: location,
                zoom: 17,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('preview'),
                  position: location,
                  infoWindow: InfoWindow(
                    title: customerName,
                    snippet: areaName,
                  ),
                ),
              },
              polylines: const {},
              // Android MapsFragmentlocupdate :305/:312 setMyLocationEnabled(true):
              // blue dot + "my location" button (works on iOS and Android).
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lat: ${location.latitude}, Lng: ${location.longitude}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('CANCEL'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => onSend(context),
                        child: const Text('SEND'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
