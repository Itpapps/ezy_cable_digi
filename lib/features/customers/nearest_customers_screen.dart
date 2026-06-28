import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../dashboard/data/nearest_repository.dart';

/// Drawer "Nearest Customer" screen — matches Android `LocateNextCustomer.java`.
/// Uses the same `NearestNextCustomer` REST API as the dashboard, with
/// `from_dashboard=0` and user-entered `distance_km`.
class NearestCustomersScreen extends StatefulWidget {
  const NearestCustomersScreen({super.key});

  @override
  State<NearestCustomersScreen> createState() => _NearestCustomersScreenState();
}

class _NearestCustomersScreenState extends State<NearestCustomersScreen> {
  final _distanceController = TextEditingController();
  bool _loading = true;
  bool _mapView = false;
  bool _hasError = false;
  String _errorMessage = '';
  LatLng? _current;
  List<NearestCustomerItem> _customers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  /// Fetches nearest customers from the server API — same endpoint as Android.
  /// GPS coordinates are sent to server; distance is calculated server-side.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showPremiumLoading(context, message: 'Loading...Please wait...');
    });
    try {
      // Get GPS (Android: GPSTracker, sends 0.0 if unavailable)
      double lat = 0.0;
      double lng = 0.0;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 8));
        lat = position.latitude;
        lng = position.longitude;
      } catch (_) {
        // GPS unavailable — send 0.0 as Android does
      }
      _current = LatLng(lat, lng);

      // Distance from user input (default "2" matching Android)
      final distText = _distanceController.text.trim();
      final distanceKm = distText.isEmpty ? '2' : distText;

      final result = await NearestRepository.instance.fetchNearest(
        lat: lat,
        lng: lng,
        distanceKm: distanceKm,
        fromDashboard: false,
      );

      if (mounted) Navigator.of(context).pop(); // dismiss loading

      if (result.statusCode == 0) {
        setState(() {
          _customers = result.customers;
          _loading = false;
        });
      } else if (result.statusCode == 1) {
        // "No Details Found" — Android shows AlertDialog
        setState(() {
          _customers = [];
          _loading = false;
        });
        if (mounted) {
          _showNoDetailsDialog(result.statusMessage);
        }
      } else {
        setState(() {
          _customers = [];
          _loading = false;
          _hasError = true;
          _errorMessage = result.statusMessage.isNotEmpty
              ? result.statusMessage
              : 'Could not load nearest customers';
        });
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // dismiss loading
      setState(() {
        _loading = false;
        _hasError = true;
        _errorMessage = 'Failed.';
      });
    }
  }

  void _showNoDetailsDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Details Found!'),
        content: Text(message.isNotEmpty ? message : 'No customers found in the given range.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Search button — re-fetches with user-entered distance (Android: searchcust_btn_search_distance)
  void _onSearchTap() {
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'NEAREST CUSTOMER',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
              letterSpacing: 1.1, color: t.appBarFg),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ─────────────────────────────────────────
            Padding(
              padding:
              const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _distanceController,
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'Enter distance in km',
                          hintStyle: TextStyle(
                              color: Colors.black.withValues(alpha: 0.35),
                              fontSize: 14),
                          border: InputBorder.none,
                          contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _onSearchTap,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.search,
                            color: AppColors.primary, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Toggle buttons ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ToggleBtn(
                      label: 'View On List',
                      active: !_mapView,
                      onTap: () => setState(() => _mapView = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ToggleBtn(
                      label: 'View On Map',
                      active: _mapView,
                      onTap: () => setState(() => _mapView = true),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ────────────────────────────────────────────
            Expanded(
              child: _mapView ? _buildMapView() : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.warning_2, color: Colors.black38, size: 32),
            const SizedBox(height: 8),
            Text(_errorMessage,
                style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('RETRY')),
          ],
        ),
      );
    }
    if (_customers.isEmpty) {
      return const Center(
        child: Text('No customers found',
            style: TextStyle(color: Colors.black45)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      itemCount: _customers.length,
      itemBuilder: (context, index) {
        final item = _customers[index];
        return _NearestCustomerCard(item: item);
      },
    );
  }

  Widget _buildMapView() {
    if (_current == null || (_current!.latitude == 0.0 && _current!.longitude == 0.0)) {
      return const Center(child: Text('Current location unavailable'));
    }
    if (_customers.isEmpty) {
      return const Center(child: Text('No customers in selected range'));
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('agent'),
        position: _current!,
        icon:
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your location'),
      ),
      ..._customers
          .where((c) => c.latitude != 0 && c.longitude != 0)
          .map(
            (item) => Marker(
          markerId: MarkerId(item.altCustomNumber),
          position: LatLng(item.latitude, item.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: item.name,
            snippet: '${item.distance} km',
          ),
        ),
      ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _current!, zoom: 16),
      markers: markers,
      myLocationEnabled: false,
      compassEnabled: true,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      onTap: (_) {},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer card — matches Android NextCustomerAdapter: name, custId, distance, map tap
// ─────────────────────────────────────────────────────────────────────────────
class _NearestCustomerCard extends StatelessWidget {
  final NearestCustomerItem item;

  const _NearestCustomerCard({required this.item});

  /// Android: tapping the card row opens Google Maps with directions to lat/lng
  void _onNavigate(BuildContext context) {
    final lat = item.latitude;
    final lng = item.longitude;
    if (lat == 0 && lng == 0) return;
    final url = Uri.parse('http://maps.google.com/maps?daddr=$lat,$lng');
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final custId = item.altCustomNumber.isEmpty ? 'NA' : item.altCustomNumber;
    final distanceText = '${item.distance}km';

    return GestureDetector(
      onTap: () => _onNavigate(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: t.cardBorderRadius,
          boxShadow: [
            BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: t.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + Customer ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    custId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Distance + map icon
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Iconsax.location, color: t.accent, size: 20),
                ),
                const SizedBox(height: 5),
                Text(
                  distanceText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle Button
// ─────────────────────────────────────────────────────────────────────────────
class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active ? t.toggleActiveBg : t.toggleInactiveBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: active
                  ? t.toggleActiveBg.withValues(alpha: 0.30)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? t.toggleActiveText : t.toggleInactiveText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
