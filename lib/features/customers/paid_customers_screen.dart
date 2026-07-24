import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import 'data/paid_customer.dart';
import 'data/paid_customers_repository.dart';

/// Paid Customers list — Android parity (Customer Payment → Paid tab,
/// `PaidlistFragment` / `getPaidCustomer_Detail`). Month filter → the customers
/// who paid that month, with total count. status 0 → list · 1 → "No Details
/// Found!" · 3 → "Failed.".
class PaidCustomersScreen extends StatefulWidget {
  // When true, renders WITHOUT its own Scaffold/app bar so it can be embedded as
  // the Customer List "Paid List" tab (Android CustomerPay_Tab_Fragment).
  final bool embedded;
  const PaidCustomersScreen({super.key, this.embedded = false});

  @override
  State<PaidCustomersScreen> createState() => _PaidCustomersScreenState();
}

class _PaidCustomersScreenState extends State<PaidCustomersScreen> {
  DateTime _month = DateTime.now();
  bool _loading = true;
  bool _error = false;
  String _message = '';
  List<PaidCustomer> _items = const [];

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // Android `paid_month` = "(month)-(year)", month NOT zero-padded (e.g. "7-2026").
  String get _paidMonth => '${_month.month}-${_month.year}';
  String get _monthLabel => '${_monthNames[_month.month - 1]} ${_month.year}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await PaidCustomersRepository.instance.getPaidCustomers(
      paidMonth: _paidMonth,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.customers;
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const [];
        _error = false;
        _message = r.statusMessage.isEmpty
            ? 'No Details Found!'
            : r.statusMessage;
      } else {
        _items = const [];
        _error = true;
        _message = r.statusMessage.isEmpty ? 'Failed.' : r.statusMessage;
      }
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Select month',
    );
    if (picked != null && mounted) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final content = Column(
      children: [
        // Filter card — a floating rounded card (was a flat edge-to-edge white
        // strip). Only the LOOK changes: the month picker (_pickMonth) and the
        // Search action (_load) are byte-for-byte the same.
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
                color: Colors.black.withValues(alpha: t.isLight ? 0.05 : 0.12),
                blurRadius: t.isLight ? 12 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickMonth,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.06),
                    border: Border.all(
                      color: t.inputBorderColor.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: t.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _monthLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: t.cardBodyText,
                        ),
                      ),
                    ],
                  ),
                ),
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
                  Icons.people_alt_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Total Count',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_items.length}',
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
    );
    // Embedded (Customer List "Paid List" tab) → no Scaffold/app bar; the tab
    // sits under the Customer List's app bar. Standalone (drawer) → full screen.
    if (widget.embedded) {
      return Container(color: t.scaffoldBg, child: content);
    }
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        title: const Text('PAID CUSTOMERS'),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
      ),
      body: content,
    );
  }

  Widget _body() {
    final t = AppThemeConst.of(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_error) {
      return _message_(Icons.error_outline_rounded, _message);
    }
    if (_items.isEmpty) {
      return _message_(
        Icons.info_outline_rounded,
        _message.isEmpty ? 'No Details Found!' : _message,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => _PaidCard(customer: _items[i]),
    );
  }

  Widget _message_(IconData icon, String text) {
    final t = AppThemeConst.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: t.subtitleText, size: 44),
            const SizedBox(height: 12),
            Text(
              text,
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
}

class _PaidCard extends StatelessWidget {
  final PaidCustomer customer;
  const _PaidCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final c = customer;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.name.isEmpty ? '-' : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: t.cardHeadingText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '₹${c.lastPaidAmount.isEmpty ? '0' : c.lastPaidAmount}',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row('LCO Customer id', c.altCustomNumber, t),
          _row('Last Paid Date', c.lastPaidDate, t),
          if (c.mobileNo.trim().isNotEmpty) _row('Mobile', c.mobileNo, t),
          _row(
            'This Month Pending',
            '₹${c.thisMonthPending.isEmpty ? '0' : c.thisMonthPending}',
            t,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, AppThemeConst t) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        '$label : ${value.trim().isEmpty ? 'NA' : value}',
        style: TextStyle(
          fontSize: 12,
          color: t.cardSubtitleText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
