import 'package:flutter/material.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/employee_collection.dart';
import 'data/employee_track_repository.dart';
import 'employee_track_map_screen.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Employee Track (collection report) — Android parity (EmployeeTrackFragment,
/// SOAP `empCollection`). Date-range filter → per-employee collections. This is a
/// report (NOT GPS tracking — location-sending is handled by LocationSyncService).
class EmployeeTrackScreen extends StatefulWidget {
  const EmployeeTrackScreen({super.key});

  @override
  State<EmployeeTrackScreen> createState() => _EmployeeTrackScreenState();
}

class _EmployeeTrackScreenState extends State<EmployeeTrackScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  bool _loading = false;
  bool _error = false;
  String _message = '';
  List<EmployeeCollection> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await EmployeeTrackRepository.instance.getCollections(
      fromDate: _fmt(_from),
      toDate: _fmt(_to),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.items;
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const [];
        _error = false;
        _message = r.statusMessage;
      } else {
        _items = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  Future<void> _pick(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  double get _total {
    var t = 0.0;
    for (final e in _items) {
      t += double.tryParse(e.amount) ?? 0;
    }
    return t;
  }

  // Android parity (EmployeeTrackAdapter "Select Any Tracking value"): label → op_name.
  static const List<(String, String)> _trackOps = [
    ('Complaint Track', 'create_complaint'),
    ('Deactivate Box Track', 'deactivate_box'),
    ('Live Track', 'live_track'),
    ('Make Payment Track', 'make_payments'),
    ('Payment History Track', 'payment_history'),
    ('Validate Login Track', 'validate_login'),
    ('Update CustomerLocation Track', 'update_customer_location'),
  ];

  Future<void> _openTrackDialog(EmployeeCollection e) async {
    final selected = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Any Tracking value'),
        children: [
          for (final op in _trackOps)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, op),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(op.$1),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _fetchTrack(e, selected.$1, selected.$2);
  }

  /// Android parity (EmployeeTrackAdapter.getEmployeeTrackInfo): fetch the GPS
  /// points for [opName] → map (status 0), "No Tracking Details Found!" (1), or
  /// "Failed." (transport). Uses Android's "Loading...Please wait..." blocker.
  Future<void> _fetchTrack(
    EmployeeCollection e,
    String label,
    String opName,
  ) async {
    // D7 / Android EmployeeTrackAdapter :197: non-cancellable (Back ignored);
    // getEmployeeTrackInfo never throws, so the pop below always closes it.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final r = await EmployeeTrackRepository.instance.getEmployeeTrackInfo(
      employeeId: e.employeeId,
      startDate: _fmt(_from), // Android sends dt_fromDt (the From date)
      opName: opName,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    if (r.statusCode == 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              EmployeeTrackMapScreen(title: label, points: r.points),
        ),
      );
    } else if (r.statusCode == 1) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tracking Details'),
          content: const Text('No Tracking Details Found!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showPremiumSnackBar(context, 'Failed.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 16,
              color: t.backBtnIcon,
            ),
          ),
        ),
        title: Text(
          'EMPLOYEE TRACK',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: t.appBarFg,
            letterSpacing: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter card — a floating rounded card (was a flat edge-to-edge white
          // strip). Only the LOOK changes: the date pickers (_pick) and the Search
          // action (_load) are byte-for-byte the same.
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: t.isLight
                  ? Border.all(color: t.inputBorderColor.withValues(alpha: 0.6))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: t.isLight ? 0.05 : 0.12,
                  ),
                  blurRadius: t.isLight ? 12 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _dateField('From', _from, () => _pick(true)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _dateField('To', _to, () => _pick(false))),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text(
                      'Search',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_loading && !_error && _items.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Total Collected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₹${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final t = AppThemeConst.of(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_error) {
      // Scrolls instead of overflowing on small phones (MainFrame bars).
      return CenterOrScroll(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: t.subtitleText,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _message.isEmpty ? 'Could not load collections' : _message,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.bodyText, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, color: t.subtitleText, size: 46),
            const SizedBox(height: 12),
            Text(
              'No collections found',
              style: TextStyle(color: t.subtitleText, fontSize: 15),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final e = _items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.cardBg,
            borderRadius: BorderRadius.circular(16),
            // Theme-gated depth: hairline border on light bg (defines the card
            // without a harsh line), softer/heavier shadow on the blue theme.
            border: t.isLight
                ? Border.all(color: t.inputBorderColor.withValues(alpha: 0.5))
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: t.isLight ? 0.05 : 0.12),
                blurRadius: t.isLight ? 12 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Employee avatar (initial) — visual only, no data change.
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: t.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name.isEmpty ? '-' : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: t.cardHeadingText,
                      ),
                    ),
                    if (e.dealerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        e.dealerName,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.cardSubtitleText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Collection amount as a semantic (money-green) pill — visual only.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF43A047).withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  '₹${e.amount.isEmpty ? '0' : e.amount}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Android parity (row tv_track): per-employee operation GPS track.
              InkWell(
                onTap: () => _openTrackDialog(e),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 15, color: t.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Track',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: t.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    final t = AppThemeConst.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.06),
          border: Border.all(color: t.inputBorderColor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: t.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: t.cardSubtitleText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _fmt(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: t.cardBodyText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
