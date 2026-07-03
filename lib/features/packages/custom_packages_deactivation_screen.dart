import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/custom_package.dart';
import 'data/custom_packages_repository.dart';
import 'deactivate_confirm_screen.dart';

/// Custom Packages — Deactivation list (Android `CustomPackages_Deactivation`).
/// Lists the customer's custom packages (`gddp` act_type=2); each row can be
/// selected, and its auto-renewal toggled (confirm → `insertDigiDealerPackages`
/// with `enable_custome_package`, Android `DigiPackagesDeactAdapter`).
/// "Proceed" (≥1 selected) → deactivate confirm screen.
class CustomPackagesDeactivationScreen extends StatefulWidget {
  final Customer customer;
  const CustomPackagesDeactivationScreen({super.key, required this.customer});

  @override
  State<CustomPackagesDeactivationScreen> createState() =>
      _CustomPackagesDeactivationScreenState();
}

class _CustomPackagesDeactivationScreenState
    extends State<CustomPackagesDeactivationScreen> {
  bool _loading = true;
  String? _error;
  List<CustomPackage> _packages = [];
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await CustomPackagesRepository.instance
        .getDigiDealerPackages(customerId: widget.customer.lcoCustomerId, actType: '2');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.isSuccess) {
        _packages = r.packages;
      } else {
        _error = r.statusMessage.isEmpty ? 'No packages found.' : r.statusMessage;
      }
    });
  }

  /// Auto-renewal toggle → confirm → per-package write (enable_custome_package).
  Future<void> _toggleAutoRenewal(int i, bool enable) async {
    final p = _packages[i];
    final ok = await showPremiumConfirm(
      context: context,
      title: 'AutoRenewal!',
      body:
          'Are you sure you want to ${enable ? 'enable' : 'disable'} the auto extension for package ${p.name} ?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
    );
    if (ok != true || !mounted) return;
    setState(() =>
        _packages[i] = _packages[i].copyWith(autoRenewal: enable ? 1 : 0));
    final res = await CustomPackagesRepository.instance.setPackageAutoRenewal(
      customerId: widget.customer.lcoCustomerId,
      packageId: p.packageId,
      autorenewal: enable ? '1' : '0',
      enable: enable ? '1' : '0',
    );
    if (!mounted) return;
    if (res.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
    } else {
      showPremiumSnackBar(
        context,
        res.message.trim().isEmpty
            ? (res.statusCode == 0 ? 'Success' : 'No Data Found')
            : res.message,
        isSuccess: res.statusCode == 0,
        isError: res.statusCode != 0,
      );
    }
  }

  void _proceed() {
    if (_selected.isEmpty) {
      showPremiumSnackBar(context, 'No Packages selected', isError: true);
      return;
    }
    final idx = _selected.toList()..sort();
    final items = [for (final i in idx) _packages[i]];
    String join(String Function(CustomPackage) f) => items.map(f).join(',');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeactivateConfirmScreen(
          customer: widget.customer,
          items: items,
          packages: join((p) => p.packageId),
          autorenewal: join((p) => p.autoRenewal.toString()),
        ),
      ),
    );
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _errorView()
              : _content(),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _packages.isEmpty
              ? const Center(
                  child: Text('No packages found.',
                      style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _packages.length,
                  itemBuilder: (context, i) {
                    final p = _packages[i];
                    final selected = _selected.contains(i);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(i);
                                  } else {
                                    _selected.remove(i);
                                  }
                                }),
                              ),
                              Expanded(
                                child: Text(p.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              const Text('Auto-renew',
                                  style: TextStyle(fontSize: 12)),
                              Checkbox(
                                value: p.autoRenewal == 1,
                                onChanged: (v) =>
                                    _toggleAutoRenewal(i, v == true),
                              ),
                            ],
                          ),
                        ],
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
              onPressed: _proceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              child: const Text('PROCEED',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ],
    );
  }
}
