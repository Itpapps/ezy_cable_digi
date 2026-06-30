import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import 'data/payment_history_repository.dart';

/// Payment History — real `getPaymentHistorylist` (Android `getpayhist()`).
/// Sends the system customer id (`altCustomerId`, = Android `altCustId`).
class PaymentHistoryScreen extends StatefulWidget {
  final Customer customer;
  const PaymentHistoryScreen({super.key, required this.customer});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  bool _loading = true;
  String _message = '';
  List<PaymentRecord> _payments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // System customer id = Android `altCustId` = JSON `customer_id` (Flutter
    // `lcoCustomerId`). `alt_cust_id` is only a display number — don't use it.
    final r = await PaymentHistoryRepository.instance
        .fetch(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _payments = r.payments;
      // statusCode 1 (no records) / 3 (transport) → message for empty state.
      _message = r.statusCode == 0 ? '' : r.statusMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Total count bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              'Total Payments - ${_payments.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),

          // Customer summary
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _row('Customer Name', widget.customer.name),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _row('Address',
                    widget.customer.address.isEmpty ? 'N/A' : widget.customer.address),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _row(
                    'Mobile No.',
                    widget.customer.primaryMobileNumber.isEmpty
                        ? 'N/A'
                        : widget.customer.primaryMobileNumber),
              ],
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_payments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No payments found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _payments.length,
      itemBuilder: (_, i) => _PaymentCard(
        record: _payments[i],
        index: i + 1,
        total: _payments.length,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new,
              size: 16, color: Colors.white),
        ),
      ),
      title: const Text('PAYMENT HISTORY',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1)),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF5B7BAE))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D47A1))),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentRecord record;
  final int index;
  final int total;
  const _PaymentCard({
    required this.record,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    // Fields mirror Android's `paymenthistory_items` row.
    final rows = <MapEntry<String, String>>[
      MapEntry('Payment Date', record.paidDateDisplay),
      MapEntry('Amount Paid', '₹${record.amount}'),
      MapEntry('Payment Type', record.paymentTypeLabel),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text('$index / $total',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B7BAE),
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          ...List.generate(rows.length, (i) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(rows[i].key,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF5B7BAE))),
                      ),
                      Expanded(
                        child: Text(rows[i].value,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D47A1))),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1)
                  const Divider(
                      height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
              ],
            );
          }),
        ],
      ),
    );
  }
}
