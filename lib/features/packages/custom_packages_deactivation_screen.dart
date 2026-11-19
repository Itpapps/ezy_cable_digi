import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import 'data/custom_package.dart';
import 'data/custom_packages_repository.dart';
import 'deactivate_confirm_screen.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

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
    // C5 / Android DigiPackagesDeactAdapter :258: non-cancellable
    // "Loading...Please wait..." while the request runs — it also blocks a
    // second toggle. setPackageAutoRenewal never throws (status 3 on any
    // failure), so the pop below always closes this loader.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final res = await CustomPackagesRepository.instance.setPackageAutoRenewal(
      customerId: widget.customer.lcoCustomerId,
      packageId: p.packageId,
      autorenewal: enable ? '1' : '0',
      enable: enable ? '1' : '0',
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    if (res.statusCode == 0) {
      // Android :285-301: "Success!" + server message; OK reloads the
      // package list from the server (getDigiDealerPackages), so the screen
      // shows the saved state. The reload rebuilds the list → ticks cleared
      // (indices would no longer match the new list).
      await _showResultDialog('Success!', res.message);
      if (!mounted) return;
      setState(_selected.clear);
      _load();
    } else if (res.statusCode == 1) {
      // Android :305-322: "No Details Found!" + server message, OK only.
      await _showResultDialog('No Details Found!', res.message);
    } else if (res.statusCode == 3) {
      // Android :336-343 (Volley error): "Failed."
      showPremiumSnackBar(context, 'Failed.', isError: true);
    } else {
      // Other codes: unchanged Flutter behaviour (server message).
      showPremiumSnackBar(
        context,
        res.message.trim().isEmpty ? 'No Data Found' : res.message,
        isError: true,
      );
    }
  }

  /// Android result popup: not cancellable, single OK.
  Future<void> _showResultDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: message.trim().isEmpty ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceed() async {
    if (_selected.isEmpty) {
      showPremiumSnackBar(context, 'No Packages selected', isError: true);
      return;
    }
    final idx = _selected.toList()..sort();
    final items = [for (final i in idx) _packages[i]];
    String join(String Function(CustomPackage) f) => items.map(f).join(',');
    await Navigator.push(
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
    // C3 / Android DigiPackages_deactivation :198/:221 popBackStack →
    // CustomPackages_Deactivation is re-created (fresh list, no ticks). Same
    // on any return: clear the ticks and reload.
    if (!mounted) return;
    setState(_selected.clear);
    _load();
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('DEACTIVATE PACKAGES'),
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
