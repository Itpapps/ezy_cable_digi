import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'data/paid_customer.dart';
import 'data/paid_customers_repository.dart';

/// Paid Customers list — Android parity (Customer Payment → Paid tab,
/// `PaidlistFragment` / `getPaidCustomer_Detail`). Month filter → the customers
/// who paid that month, with total count. status 0 → list · 1 → "No Details
/// Found!" · 3 → "Failed.".
class PaidCustomersScreen extends StatefulWidget {
  const PaidCustomersScreen({super.key});

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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
    final r = await PaidCustomersRepository.instance
        .getPaidCustomers(paidMonth: _paidMonth);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.customers;
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const [];
        _error = false;
        _message =
            r.statusMessage.isEmpty ? 'No Details Found!' : r.statusMessage;
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
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('PAID CUSTOMERS'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCBD5F5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(_monthLabel,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                  ),
                  child: const Text('Search',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          if (!_loading && !_error && _items.isNotEmpty)
            Container(
              width: double.infinity,
              color: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('Total Count ${_items.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error) {
      return _message_(Icons.error_outline_rounded, _message);
    }
    if (_items.isEmpty) {
      return _message_(Icons.info_outline_rounded,
          _message.isEmpty ? 'No Details Found!' : _message);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => _PaidCard(customer: _items[i]),
    );
  }

  Widget _message_(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 44),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary),
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
    final c = customer;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.name.isEmpty ? '-' : c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
                ),
                child: Text('₹${c.lastPaidAmount.isEmpty ? '0' : c.lastPaidAmount}',
                    style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row('LCO Customer id', c.altCustomNumber),
          _row('Last Paid Date', c.lastPaidDate),
          if (c.mobileNo.trim().isNotEmpty) _row('Mobile', c.mobileNo),
          _row('This Month Pending',
              '₹${c.thisMonthPending.isEmpty ? '0' : c.thisMonthPending}'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text('$label : ${value.trim().isEmpty ? 'NA' : value}',
          style: const TextStyle(
              fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
    );
  }
}
