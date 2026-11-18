import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import '../dashboard/data/complaints_repository.dart';
import 'complaint_details_screen.dart';
import 'data/customer_complaint.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COMPLAINT HISTORY (Customer Details → Complaint History)
// Real `getCustomerComplaintList` data for this customer. Defensive: loading /
// error / empty states; never crashes on null / missing fields / malformed data.
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintHistoryScreen extends StatefulWidget {
  final Customer customer;
  const ComplaintHistoryScreen({super.key, required this.customer});

  @override
  State<ComplaintHistoryScreen> createState() => _ComplaintHistoryScreenState();
}

class _ComplaintHistoryScreenState extends State<ComplaintHistoryScreen> {
  bool _loading = true;
  bool _error = false;
  String _message = '';
  List<CustomerComplaint> _items = const [];

  Customer get customer => widget.customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    // The complaint APIs key on the numeric customer_id, which the app stores in
    // lcoCustomerId (same id the payment/GPA flow uses). altCustomerId here can be
    // the alphanumeric account number, so it is only a fallback.
    final id = customer.lcoCustomerId.isNotEmpty
        ? customer.lcoCustomerId
        : customer.altCustomerId;
    final r = await ComplaintsRepository.instance
        .fetchCustomerComplaints(altCustomerId: id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.complaints; // may be empty → empty-state
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const []; // no records → empty-state
        _error = false;
      } else {
        _items = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  // Tapping a complaint opens the update-status flow (closeComplaint). On a
  // successful update we refetch so the new status shows. closeComplaint keys on
  // the complaint's alt_cust_id (not the customer_id), which the history row carries.
  void _openUpdate(CustomerComplaint c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComplaintDetailsScreen(
          complaintId: c.ticketNumber.isEmpty ? c.complaintId : c.ticketNumber,
          customerName: customer.name,
          complaint: c.description.isEmpty ? 'N/A' : c.description,
          currentStatus: c.status,
          altCustomerId: c.altCustomerId,
          realComplaintId: c.complaintId,
        ),
      ),
    ).then((ok) {
      if (ok == true) _load();
    });
  }

  // Android's complaint list shows complaint / status only (it parses
  // `complaintTime` but never displays it — ComplaintSearchResult_Fragment :74-85),
  // so we don't render a "Time" row either. The field stays in the model.
  Map<String, String> _toMap(CustomerComplaint c) => {
        'Ticket No.': c.ticketNumber.isEmpty ? c.complaintId : c.ticketNumber,
        'Complaint': c.description.isEmpty ? 'N/A' : c.description,
        'Status': c.status.isEmpty ? 'N/A' : c.status,
      };

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
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
              'Total Count - ${_items.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),

          // Customer Info
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _cRow('Customer Name', customer.name),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _cRow('Address',
                    customer.address.isEmpty ? 'N/A' : customer.address),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _cRow(
                    'Mobile No.',
                    customer.primaryMobileNumber.isEmpty
                        ? 'N/A'
                        : customer.primaryMobileNumber,
                    isLast: true),
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error) {
      // Scrolls instead of overflowing on small phones (MainFrame bars).
      return CenterOrScroll(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'Could not load complaint history' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No complaints found',
            style: TextStyle(color: Colors.white70, fontSize: 15)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _items.length,
        itemBuilder: (_, i) => _ComplaintCard(
          data: _toMap(_items[i]),
          onTap: () => _openUpdate(_items[i]),
        ),
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
      title: const Text('COMPLAINT HISTORY',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1)),
    );
  }

  Widget _cRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
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

class _ComplaintCard extends StatelessWidget {
  final Map<String, String> data;
  final VoidCallback? onTap;
  const _ComplaintCard({required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                ...List.generate(entries.length, (i) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(entries[i].key,
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF5B7BAE))),
                            ),
                            Expanded(
                              child: Text(entries[i].value,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0D47A1))),
                            ),
                          ],
                        ),
                      ),
                      const Divider(
                          height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                    ],
                  );
                }),
                if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: const [
                        Icon(Icons.edit_note_rounded,
                            size: 16, color: Color(0xFF0D47A1)),
                        SizedBox(width: 4),
                        Text('Tap to update status',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D47A1))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
