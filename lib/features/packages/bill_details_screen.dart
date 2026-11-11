import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/custom_package.dart';
import 'data/custom_packages_repository.dart';

/// Bill Details (checkout) — Android parity (`BillDetails_Act`). Shows the
/// selected custom packages + total, then submits `insertDigiDealerPackages`
/// (act_type=1). On success/"No Data Found" Android pops back to the cart.
class BillDetailsScreen extends StatefulWidget {
  final Customer customer;
  final List<CustomPackage> items; // selected, with chosen quantity
  final double total;
  // Pre-joined payload (built by the activation cart, same selection order).
  final String packages;
  final String startDate;
  final String months;
  final String autorenewal;

  const BillDetailsScreen({
    super.key,
    required this.customer,
    required this.items,
    required this.total,
    required this.packages,
    required this.startDate,
    required this.months,
    required this.autorenewal,
  });

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    // C12 / Android BillDetails_Act :178: non-cancellable "Loading...Please
    // wait..." (Back ignored); activatePackages never throws.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final res = await CustomPackagesRepository.instance.activatePackages(
      customerId: widget.customer.lcoCustomerId,
      packages: widget.packages,
      startDate: widget.startDate,
      months: widget.months,
      autorenewal: widget.autorenewal,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _busy = false);
    if (res.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    // Android: status 0 → success dialog; status 1 → "No Data Found!"; both pop.
    await showPremiumConfirm(
      context: context,
      title: res.statusCode == 0 ? 'Success' : 'No Data Found!',
      body: res.message.trim().isEmpty
          ? (res.statusCode == 0 ? 'Success' : 'No Data Found')
          : res.message,
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('BILL DETAILS'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final p = widget.items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text('Qty: ${p.quantity} · Start: ${p.startDate}'
                        '${p.autoRenewal == 1 ? ' · Auto-renew' : ''}'),
                    trailing: Text('₹${p.price}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                );
              },
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Text('₹${widget.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppColors.primary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _busy ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('CONFIRM',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
