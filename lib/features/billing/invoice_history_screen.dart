import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import 'data/invoice_history_repository.dart';

/// Invoice History — real `InvoiceService` SOAP (Android `InvoiceHistory`).
/// Sends the system customer id (`altCustomerId`, = Android `custId`/`altCustId`).
class InvoiceHistoryScreen extends StatefulWidget {
  final Customer customer;
  const InvoiceHistoryScreen({super.key, required this.customer});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  bool _loading = true;
  String _message = '';
  List<InvoiceRecord> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // System customer id = Android `custId`/`altCustId` = JSON `customer_id`
    // (Flutter `lcoCustomerId`). `alt_cust_id` is only a display number.
    final r = await InvoiceHistoryRepository.instance
        .fetch(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _invoices = r.invoices;
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              'Total Invoices : ${_invoices.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
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
    if (_invoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No invoices found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _invoices.length,
      itemBuilder: (_, i) => _InvoiceCard(invoice: _invoices[i]),
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
          child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
        ),
      ),
      title: const Text('INVOICE HISTORY',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final InvoiceRecord invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Invoice number header row (grey background)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFE0E0E0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Text('Invoice Number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
                const Spacer(),
                Text(invoice.billingId,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1B3A7A))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('Invoice Date', invoice.billDate),
                _row('Due Date', invoice.dueDate),
                _row('Bill Number', invoice.billNo),
                _row('Bill Amount', '₹${invoice.billAmount}'),
                _row('Tax Amount', '₹${invoice.taxAmount}'),
                _row('Pending Amount', '₹${invoice.pendingAmount}'),
                _row('Package Name', invoice.packageName),
                _row('Total Amount', '₹${invoice.totalAmount}', isTotal: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool isTotal = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: isTotal ? const Color(0xFF0D47A1) : const Color(0xFF5B7BAE),
                        fontWeight: isTotal ? FontWeight.w800 : FontWeight.w400)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}
