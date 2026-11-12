import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../search/data/search_repository.dart';
import '../search/search_customer_screen.dart' show SearchCustomerCard;
import '../search/search_dealers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCAN CUSTOMER SCREEN — real MobileScanner with camera permission
// Matches the reference photo layout exactly.
// ─────────────────────────────────────────────────────────────────────────────
class ScanCustomerScreen extends StatefulWidget {
  const ScanCustomerScreen({super.key});

  @override
  State<ScanCustomerScreen> createState() => _ScanCustomerScreenState();
}

class _ScanCustomerScreenState extends State<ScanCustomerScreen> {
  String _selectedType = 'Serial Number';
  static const List<String> _types = ['Serial Number', 'VC Number'];

  String _scannedValue = '';
  bool _permissionGranted = false;
  bool _checkingPermission = true;
  MobileScannerController? _scanCtrl;
  // D-B6 / Android ScannerFrag :145-150: Dealer dropdown for common employees
  // only, default "----Select Dealer----" (0).
  final bool _isCommonEmployee = SessionService.instance.commonEmployee != 0;
  List<SearchDealer> _dealers = const [kSelectDealer];
  int _dealerId = 0;
  // D13 / Android ScannerFrag :973-978: every match is listed (even one);
  // tapping a card opens that customer. Cleared by the rescan button.
  List<Customer> _results = const [];
  int _resultsDealerId = 0; // dealer used for the search (detail fetch)

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    if (_isCommonEmployee) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDealers();
      });
    }
  }

  Future<void> _loadDealers() async {
    final list = await loadSearchDealers(context);
    if (list == null || !mounted) return;
    setState(() {
      _dealers = list;
      _dealerId = 0; // Android: items[0] "----Select Dealer----" is selected
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      _scanCtrl = MobileScannerController(
        formats: [BarcodeFormat.all],
        autoStart: true,
      );
      setState(() {
        _permissionGranted = true;
        _checkingPermission = false;
      });
    } else {
      setState(() {
        _permissionGranted = false;
        _checkingPermission = false;
      });
    }
  }

  @override
  void dispose() {
    _scanCtrl?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw != null && raw.isNotEmpty && _scannedValue.isEmpty) {
      _scanCtrl?.stop();
      setState(() => _scannedValue = raw);
    }
  }

  void _resetScan() {
    setState(() {
      _scannedValue = '';
      _results = const [];
    });
    _scanCtrl?.start();
  }

  Future<void> _search() async {
    if (_scannedValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcode scanned yet')),
      );
      return;
    }
    // Android ScannerFrag: Serial Number → searchType 6, VC Number → 7,
    // then searchCustomer(sc) → open the customer.
    final searchType = _selectedType == 'VC Number' ? 7 : 6;
    // D1 / Android ScannerFrag cust_search :632: non-cancellable "Searching...,
    // Please wait..." (Back ignored), so the pops below always close THIS
    // loader and never the Scan screen.
    showPremiumLoading(context,
        message: 'Searching...,   Please wait...', canPop: false);
    // D-B6 / Android ScannerFrag :654-658: dealer_id 0 for a normal employee,
    // the chosen dealer for a common employee.
    final dealerId = _isCommonEmployee ? _dealerId : 0;
    final SearchResult result;
    try {
      result = await SearchRepository.instance.search(
          searchType: searchType, value: _scannedValue, dealerId: dealerId);
    } catch (_) {
      // D1 / Android ScannerFrag :941-955: no server reply → close the loader
      // and show "Server is busy or Un reachable!"; OK only closes the dialog.
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Server is busy or Un reachable!'),
          content: const Text('Please try again after sometime'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading
    // D13 / Android ScannerFrag cust_search onPostExecute :973-1008.
    if (result.statusCode == 0) {
      // Show the result list; the customer opens on tap (the card's View
      // Details does the enriched detail fetch, same as Search Customer).
      setState(() {
        _results = result.customers;
        _resultsDealerId = dealerId;
      });
    } else if (result.statusCode == 1) {
      // "No records Found !" with the server message; OK clears the scan so
      // the next barcode can be read (Android :983-1005).
      setState(() => _results = const []);
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('No records Found !'),
          content: Text(result.statusMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) _resetScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.statusMessage}: Contact Support'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
          ),
        ),
        title: const Text(
          'SEARCH CUSTOMER WITH SCAN',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: _checkingPermission
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Requesting camera permission...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                children: [
                  // ── D-B6: Dealer Dropdown (common employees only, above the
                  //    type dropdown like Android's fragment_scanner.xml) ────
                  if (_isCommonEmployee) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _dealers.any((d) => d.id == _dealerId)
                              ? _dealerId
                              : 0,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: AppColors.primary),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          items: _dealers
                              .map((d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(d.name,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _dealerId = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // ── Type Dropdown ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedType,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.primary),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                        items: _types
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedType = v!),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Camera Preview, or the D13 result list ───────────────
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      // The camera stays in the tree (the scanner controller
                      // is only stopped/started); the result list covers it.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _permissionGranted
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    MobileScanner(
                                      controller: _scanCtrl,
                                      onDetect: _onDetect,
                                    ),
                                    // Corner scan frame overlay
                                    Positioned.fill(
                                      child: CustomPaint(
                                          painter: _ScannerFramePainter()),
                                    ),
                                  ],
                                )
                              : _buildPermissionDenied(),
                          if (_results.isNotEmpty)
                            Container(
                              color: AppColors.primary,
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: _results.length,
                                itemBuilder: (ctx, i) => SearchCustomerCard(
                                  customer: _results[i],
                                  t: AppThemeConst.of(ctx),
                                  dealerId: _resultsDealerId,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Result Box ───────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _scannedValue.isEmpty
                                ? 'No Barcode detected'
                                : _scannedValue,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _scannedValue.isEmpty
                                  ? AppColors.primary.withValues(alpha: 0.45)
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                        if (_scannedValue.isNotEmpty)
                          GestureDetector(
                            onTap: _resetScan,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.refresh_rounded,
                                  color: AppColors.primary, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── SEARCH button ─────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.20),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: Colors.white54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'SEARCH',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionDenied() {
    return Container(
      color: Colors.black54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_rounded, color: Colors.white60, size: 52),
          const SizedBox(height: 16),
          const Text(
            'Camera permission is required\nto scan barcodes',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanner corner frame overlay — draws 4 corner brackets
// ─────────────────────────────────────────────────────────────────────────────
class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 32.0;
    const len = 28.0;
    final x1 = inset;
    final y1 = inset;
    final x2 = size.width - inset;
    final y2 = size.height - inset;

    // Top-left
    canvas.drawLine(Offset(x1, y1), Offset(x1 + len, y1), paint);
    canvas.drawLine(Offset(x1, y1), Offset(x1, y1 + len), paint);
    // Top-right
    canvas.drawLine(Offset(x2, y1), Offset(x2 - len, y1), paint);
    canvas.drawLine(Offset(x2, y1), Offset(x2, y1 + len), paint);
    // Bottom-left
    canvas.drawLine(Offset(x1, y2), Offset(x1 + len, y2), paint);
    canvas.drawLine(Offset(x1, y2), Offset(x1, y2 - len), paint);
    // Bottom-right
    canvas.drawLine(Offset(x2, y2), Offset(x2 - len, y2), paint);
    canvas.drawLine(Offset(x2, y2), Offset(x2, y2 - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}