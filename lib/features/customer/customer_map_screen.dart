import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/data/customer.dart';
import 'data/directions_repository.dart';

class CustomerMapScreen extends StatefulWidget {
  final Customer customer;
  final LatLng currentLocation;

  const CustomerMapScreen({
    super.key,
    required this.customer,
    required this.currentLocation,
  });

  @override
  State<CustomerMapScreen> createState() => _CustomerMapScreenState();
}

class _CustomerMapScreenState extends State<CustomerMapScreen> {
  StreamSubscription<Position>? _posSub;

  late LatLng _current;
  late LatLng _customerPoint;

  // Straight line polyline between current and customer (always updated).
  Set<Polyline> _polylines = {};

  // Road-route polyline from Directions API (updated occasionally).
  List<LatLng> _routePolyline = [];
  bool _isRouteLoading = false;
  DateTime? _lastRouteFetchAt;
  LatLng? _lastRouteOrigin;

  GoogleMapController? _mapController;
  DateTime? _lastCameraMoveAt;

  @override
  void initState() {
    super.initState();
    _current = widget.currentLocation;

    if (widget.customer.latitude == null || widget.customer.longitude == null) {
      _customerPoint = const LatLng(0, 0);
    } else {
      _customerPoint = LatLng(widget.customer.latitude!, widget.customer.longitude!);
    }

    _refreshPolylines();
    _startLocationStream();
    _tryFetchRoutePolylineOnce();
  }

  void _refreshPolylines() {
    final straightPoints = <LatLng>[_current, _customerPoint];

    if (_routePolyline.isNotEmpty) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('straight'),
          points: straightPoints,
          width: 3,
          color: Colors.blue.withValues(alpha: 0.35),
        ),
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePolyline,
          width: 5,
          color: Colors.blue,
        ),
      };
      return;
    }

    _polylines = {
      Polyline(
        polylineId: const PolylineId('straight'),
        points: straightPoints,
        width: 4,
        color: Colors.blue,
      ),
    };
  }

  Future<void> _startLocationStream() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((pos) {
        if (!mounted) return;

        final next = LatLng(pos.latitude, pos.longitude);
        final movedMeters = Geolocator.distanceBetween(
          _current.latitude,
          _current.longitude,
          next.latitude,
          next.longitude,
        );

        setState(() {
          _current = next;
          _refreshPolylines();
        });

        // Update road route only occasionally to keep it smooth.

        final lastOrigin = _lastRouteOrigin;
        final lastFetchAt = _lastRouteFetchAt;
        final shouldRefresh = lastOrigin == null ||
            lastFetchAt == null ||
            DateTime.now().difference(lastFetchAt).inSeconds >= 180;

        if (shouldRefresh && lastOrigin != null) {
          if (movedMeters >= 250) {
            _fetchRouteIfNeeded(force: false);
          }
        } else if (lastOrigin == null) {
          _fetchRouteIfNeeded(force: false);
        }

        // Follow the agent smoothly (avoid jitter).
        if (_mapController != null) {
          final now = DateTime.now();
          final timeOk = _lastCameraMoveAt == null ||
              now.difference(_lastCameraMoveAt!).inSeconds >= 5;
          if (timeOk && movedMeters >= 50) {
            _lastCameraMoveAt = now;
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(next),
            );
          }
        }
      });
    } catch (error, stackTrace) {
      debugPrint('CustomerMapScreen: location stream failed: $error');
      debugPrint(stackTrace.toString());
    }
  }

  Future<void> _tryFetchRoutePolylineOnce() async {
    await _fetchRouteIfNeeded(force: true);
  }

  Future<void> _fetchRouteIfNeeded({required bool force}) async {
    if (!mounted) return;
    if (_isRouteLoading) return;
    if (_customerPoint.latitude == 0 && _customerPoint.longitude == 0) return;

    try {
      if (!force && _lastRouteFetchAt != null) {
        if (DateTime.now().difference(_lastRouteFetchAt!).inSeconds < 180) {
          return;
        }
      }

      if (!force && _lastRouteOrigin != null) {
        final movedMeters = Geolocator.distanceBetween(
          _lastRouteOrigin!.latitude,
          _lastRouteOrigin!.longitude,
          _current.latitude,
          _current.longitude,
        );
        if (movedMeters < 250) return;
      }

      _isRouteLoading = true;

      final decoded = await DirectionsRepository.instance.fetchRoute(
        origin: _current,
        destination: _customerPoint,
      );
      if (decoded.isEmpty || !mounted) return;

      setState(() {
        _routePolyline = decoded;
        _lastRouteFetchAt = DateTime.now();
        _lastRouteOrigin = _current;
        _refreshPolylines();
      });
    } catch (error, stackTrace) {
      debugPrint('CustomerMapScreen: route fetch failed: $error');
      debugPrint(stackTrace.toString());
    } finally {
      _isRouteLoading = false;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomerLocation =
        widget.customer.latitude != null && widget.customer.longitude != null;
    if (!hasCustomerLocation) {
      return Scaffold(
        appBar: AppBar(title: const Text('CUSTOMER LOCATION')),
        body: const Center(
          child: Text('Location not available for this customer'),
        ),
      );
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('current'),
        position: _current,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId('customer'),
        position: _customerPoint,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    return Scaffold(
      appBar: AppBar(title: Text('${widget.customer.name} Location')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _customerPoint,
              zoom: 16,
            ),
            markers: markers,
            polylines: _polylines,
            myLocationEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _mapController = c,
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 14, color: Colors.blue),
                      SizedBox(width: 6),
                      Text(
                        'Your location',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_current.latitude},${_current.longitude}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_isRouteLoading)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Finding best route...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
