import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/data/offline_customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
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
  bool _onlyCurrentMonth = false;
  List<OfflineCustomer> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getUnpaidOfflineCustomers(
      currentMonthOnly: _onlyCurrentMonth,
    );
    setState(() {
      _filtered = list;
      _loading = false;
    });
  }

  void _applyMonthFilter(bool v) {
    setState(() => _onlyCurrentMonth = v);
    _load();
  }

  Future<void> _onPayCustomer(OfflineCustomer customer) async {
    final initial = customer.totalAmount;
    final result = await showDialog<OfflinePaymentResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfflinePaymentDialog(
        customerName: customer.name,
        initialAmount: initial,
        restrictPartial: false,
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
      await OfflineDataService.instance.commitPayment(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Payment of ₹${result.amount.toStringAsFixed(2)} recorded for ${customer.name}'),
          backgroundColor: Colors.green,
        ),
      );
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
              const Text(
                'Page - 1/1',
                style: TextStyle(color: Colors.white70, fontSize: 12),
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
                value: _onlyCurrentMonth,
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
            itemCount: _filtered.length,
            itemBuilder: (context, i) {
              final c = _filtered[i];
              return _OfflineCustomerPayCard(
                customer: c,
                onProceedPayment: () => _onPayCustomer(c),
              );
            },
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
