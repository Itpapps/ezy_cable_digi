import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/data/offline_customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
import 'offline_payment_flow.dart';
import 'widgets/offline_payment_dialog.dart';

class OfflineUnpaidListScreen extends StatefulWidget {
  const OfflineUnpaidListScreen({super.key});

  @override
  State<OfflineUnpaidListScreen> createState() =>
      _OfflineUnpaidListScreenState();
}

class _OfflineUnpaidListScreenState extends State<OfflineUnpaidListScreen> {
  final _db = DatabaseHelper();
  bool _loading = true;
  // true = current month, false = non-current month
  // (Offline_unPaidCustomer_Fragment :120 / :300-306). Starts TRUE: Android's
  // "Only Current Month" checkbox is checked by default
  // (offline_tabfragment1.xml:56), so the screen opens on the current-month list.
  bool? _monthFilter = true;
  // Full unpaid set (flag=0), loaded ONCE — Android keeps `custList` in memory
  // and filters it synchronously on the checkbox toggle (:294-344). [_filtered]
  // is the in-memory month-filtered view shown in the list.
  List<OfflineCustomer> _all = [];
  List<OfflineCustomer> _filtered = [];

  // Client-side pagination — Android parity (Offline_unPaidCustomer_Fragment
  // :312-343): 25 per page with Prev/Next; the page bar shows only when the
  // filtered list exceeds one page. All rows are already in memory (offline).
  static const int _pageSize = 25;
  int _page = 0; // Android `page_position`

  int get _totalPages =>
      _filtered.isEmpty ? 1 : ((_filtered.length + _pageSize - 1) ~/ _pageSize);

  List<OfflineCustomer> get _pageItems {
    final start = _page * _pageSize;
    if (start >= _filtered.length) return const [];
    final end = (start + _pageSize) < _filtered.length
        ? start + _pageSize
        : _filtered.length;
    return _filtered.sublist(start, end);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Load the FULL unpaid list once; the month filter is applied in memory.
    final all = await _db.getUnpaidOfflineCustomers();
    if (!mounted) return;
    setState(() {
      _all = all;
      _filtered = _computeFiltered();
      _page = 0;
      _loading = false;
    });
  }

  /// Android parity (onCheckedChanged :298-307): filter the in-memory list.
  /// true → current month (payment_flag "000") · false → non-current.
  List<OfflineCustomer> _computeFiltered() {
    if (_monthFilter == true) {
      return _all.where((c) => c.paymentFlag.trim() == '000').toList();
    }
    if (_monthFilter == false) {
      return _all.where((c) => c.paymentFlag.trim() != '000').toList();
    }
    return List<OfflineCustomer>.from(_all);
  }

  /// Synchronous filter + count update from the SAME list, in one setState —
  /// mirrors Android's onCheckedChanged. No DB round-trip, so count and list
  /// can never desync and there is no async race.
  void _applyMonthFilter(bool v) {
    setState(() {
      _monthFilter = v;
      _filtered = _computeFiltered();
      _page = 0;
    });
  }

  /// Prev page — Android prevBtn (:348-368): at page 1 it just notifies.
  void _prevPage() {
    if (_page == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Page-1, Press 'Next' ")),
      );
      return;
    }
    setState(() => _page--);
  }

  /// Next page — Android nextBtn (:370-393): at the last page it just notifies.
  void _nextPage() {
    if (_page >= _totalPages - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available.')),
      );
      return;
    }
    setState(() => _page++);
  }

  Future<void> _onPayCustomer(OfflineCustomer customer) async {
    // B-B4: Android blocks a due of 0.00 or less before the popup.
    if (!offlineDueAllowsPayment(context, customer)) return;
    final initial = customer.totalAmount;
    final result = await showDialog<OfflinePaymentResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfflinePaymentDialog(
        customerName: customer.name,
        initialAmount: initial,
        discountPenaltyFlag: customer.discountPenaltyFlag,
        discountAmount: customer.discountAmount,
        penaltyAmount: customer.penaltyAmount,
        totalAfterDiscount: customer.totalAfterDiscount,
        totalAfterPenalty: customer.totalAfterPenalty,
        discountStartDate: customer.discountStartDate,
        discountEndDate: customer.discountEndDate,
        penaltyStartDate: customer.penaltyStartDate,
        penaltyEndDate: customer.penaltyEndDate,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final updated = await OfflineDataService.instance.commitPayment(
        customer: customer,
        amount: result.amount,
        payMode: result.method == 'cash' ? 'R' : 'B',
        sendSms: result.sendSms,
        chequeNumber: result.chequeNo,
        bankName: result.bankName,
        branchName: result.branch,
        insDate: result.instrumentDate,
        discountPenaltyFlag: result.discountPenaltyFlag,
      );
      if (!mounted) return;
      // Android parity: after the offline payment, show the printable receipt
      // (offline receipt number + bill/due/out), then refresh the list.
      await showOfflineReceipt(context, updated,
          paid: result.amount, sendSms: result.sendSms);
      if (!mounted) return;
      await _load();
    } on OfflineDataException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Payment failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        appBar: AppBar(
          title: const Text('CUSTOMER LIST'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: Colors.redAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Un-Paid Customer-List'),
              Tab(text: 'Paid Customer-List(Day Report)'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUnpaidTab(),
            const _PaidTodayTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildUnpaidTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.primary,
          child: Row(
            children: [
              Text(
                'Total Customer Count - ${_filtered.length}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const Spacer(),
              Text(
                'Page - ${_page + 1}/$_totalPages',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Checkbox(
                value: _monthFilter ?? false,
                onChanged: (v) => _applyMonthFilter(v ?? false),
                activeColor: Colors.white,
                checkColor: AppColors.primary,
              ),
              const Text(
                'Only Current Month',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSizes.paddingM),
            itemCount: _pageItems.length,
            itemBuilder: (context, i) {
              final c = _pageItems[i];
              return _OfflineCustomerPayCard(
                customer: c,
                onProceedPayment: () => _onPayCustomer(c),
              );
            },
          ),
        ),
        // Android parity (:312-343): Prev/Next page bar, shown only when the
        // filtered list spans more than one page (25 rows).
        if (_filtered.length > _pageSize)
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _prevPage,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                Text(
                  'Page - ${_page + 1} / $_totalPages',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                TextButton(
                  onPressed: _nextPage,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Next'), Icon(Icons.chevron_right)],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OfflineCustomerPayCard extends StatelessWidget {
  final OfflineCustomer customer;
  final VoidCallback onProceedPayment;

  const _OfflineCustomerPayCard({
    required this.customer,
    required this.onProceedPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onProceedPayment,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('LCO Customer ID', customer.lcoCustId),
              _row('CRF Number', customer.crfNumber),
              _row('Name', customer.name),
              _row('Address', customer.address),
              _row('Mobile Number', customer.mobileNum),
              _row('Bill Amount', '₹${customer.billAmount}'),
              _row('Tax Amount', '₹${customer.taxAmount}'),
              _row('Pending Amount', '₹${customer.pendingAmount}'),
              _row('Total Amount', '₹${customer.totalAmount}'),
              _row('Last Paid Amount', '₹${customer.lastPaidAmount}'),
              _row('Last Paid Date', customer.lastPaidDate),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onProceedPayment,
                  child: const Text(
                    'Click to proceed for payment.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$k:',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaidTodayTab extends StatefulWidget {
  const _PaidTodayTab();

  @override
  State<_PaidTodayTab> createState() => _PaidTodayTabState();
}

class _PaidTodayTabState extends State<_PaidTodayTab> {
  final _db = DatabaseHelper();
  bool _loading = true;
  var _items = <OfflineCustomer>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final p = await _db.getTodayOfflinePayments(today);
    setState(() {
      _items = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No payments today',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final pay = _items[i];
        final synced = pay.flag == 2;
        final syncedText = synced ? 'Synced' : 'Pending';
        final method = pay.payMode == 'R' ? 'CASH' : 'BANK';
        return Card(
          child: ListTile(
            title: Text(pay.name),
            subtitle: Text(
              '$method · ₹${pay.amount} · ${pay.paymentDate}',
            ),
            trailing: Text(
              syncedText,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: synced ? Colors.green : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}
