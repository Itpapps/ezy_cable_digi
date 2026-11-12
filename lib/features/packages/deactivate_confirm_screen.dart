import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/custom_package.dart';
import 'data/custom_packages_repository.dart';

/// Deactivate confirm — Android parity (`DigiPackages_deactivation`). Shows the
/// selected packages, then submits `insertDigiDealerPackages` (act_type=2). On
/// success/"No Data Found" Android pops back.
class DeactivateConfirmScreen extends StatefulWidget {
  final Customer customer;
  final List<CustomPackage> items; // selected
  final String packages; // comma-joined ids (selection order)
  final String autorenewal; // comma-joined "0"/"1"

  const DeactivateConfirmScreen({
    super.key,
    required this.customer,
    required this.items,
    required this.packages,
    required this.autorenewal,
  });

  @override
  State<DeactivateConfirmScreen> createState() =>
      _DeactivateConfirmScreenState();
}

class _DeactivateConfirmScreenState extends State<DeactivateConfirmScreen> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    // C-B3 / Android DigiPackages_deactivation :100-125: ask before sending.
    _busy = true; // block a second tap while the question is open
    final yes = await showPremiumConfirm(
      context: context,
      title: 'Deactivate Packages',
      body: 'Are you sure you want to Deactivate packages?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
    );
    _busy = false;
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    // C12 / Android DigiPackages_deactivation :169: non-cancellable
    // "Loading...Please wait..." (Back ignored); deactivatePackages never throws.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final res = await CustomPackagesRepository.instance.deactivatePackages(
      customerId: widget.customer.lcoCustomerId,
      packages: widget.packages,
      autorenewal: widget.autorenewal,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _busy = false);
    if (res.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
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
        title: const Text('DEACTIVATE PACKAGES'),
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
                    subtitle: Text('₹${p.price} · ${p.startDate}'),
                  ),
                );
              },
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
                    : const Text('CONFIRM DEACTIVATION',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
