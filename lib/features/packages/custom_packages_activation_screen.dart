import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import 'bill_details_screen.dart';
import 'data/custom_package.dart';
import 'data/custom_packages_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Custom Packages — Activation cart (Android `CustomPackages_Activation`).
/// Lists the dealer's custom packages (`gddp` act_type=1); each row can be
/// selected, with a quantity stepper and an auto-renewal checkbox (Android
/// `GetCustomPackages_ActAdapter`). "Proceed" (≥1 selected) → BillDetails.
/// Start date is NOT editable — it uses the package's default (Android has no
/// date picker here).
class CustomPackagesActivationScreen extends StatefulWidget {
  final Customer customer;
  const CustomPackagesActivationScreen({super.key, required this.customer});

  @override
  State<CustomPackagesActivationScreen> createState() =>
      _CustomPackagesActivationScreenState();
}

class _CustomPackagesActivationScreenState
    extends State<CustomPackagesActivationScreen> {
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
        .getDigiDealerPackages(customerId: widget.customer.lcoCustomerId, actType: '1');
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

  double get _total {
    var sum = 0.0;
    for (final i in _selected) {
      sum += double.tryParse(_packages[i].price) ?? 0;
    }
    return sum;
  }

  void _setQty(int i, int delta) {
    final cur = int.tryParse(_packages[i].quantity) ?? 1;
    final next = (cur + delta).clamp(1, 999); // Android stepper min 1
    setState(() =>
        _packages[i] = _packages[i].copyWith(quantity: next.toString()));
  }

  Future<void> _proceed() async {
    if (_selected.isEmpty) {
      // Android: Toast "No Packages selected".
      showPremiumSnackBar(context, 'No Packages selected', isError: true);
      return;
    }
    final idx = _selected.toList()..sort();
    final items = [for (final i in idx) _packages[i]];
    // Comma-joined in selection order (Android convertStringArrayToString1).
    String join(String Function(CustomPackage) f) => items.map(f).join(',');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillDetailsScreen(
          customer: widget.customer,
          items: items,
          total: _total,
          packages: join((p) => p.packageId),
          startDate: join((p) => p.startDate),
          months: join((p) => p.quantity),
          autorenewal: join((p) => p.autoRenewal.toString()),
        ),
      ),
    );
    _reloadAfterReturn();
  }

  /// C3 / Android BillDetails_Act :207 popBackStack → CustomPackages_Activation
  /// is re-created (onCreateView :105 fetches again, adapter :45 starts with no
  /// ticks). Same on ANY return (Success, No Data Found or Back): clear the
  /// ticks and reload, so activated packages don't stay listed/ticked.
  void _reloadAfterReturn() {
    if (!mounted) return;
    setState(_selected.clear);
    _load();
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    // Theme-aware page: Theme 1 keeps the same blue page + white spinner.
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 40, // compact, same as Customer / Payment Details
        title: const Text('CUSTOM PACKAGES',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.loadingColor))
          : _error != null
              ? _errorView(t)
              : _content(t),
    );
  }

  // Drawn straight on the page, so its colours follow the theme (Theme 1:
  // white text + white70 outline, as before).
  Widget _errorView(AppThemeConst t) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: t.headingText)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.headingText,
                side: BorderSide(
                    color: t.isLight
                        ? t.headingText.withValues(alpha: 0.45)
                        : Colors.white70),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _content(AppThemeConst t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _packages.isEmpty
              ? Center(
                  child: Text('No packages found.',
                      style: TextStyle(
                          color: t.isLight
                              ? t.subtitleText
                              : Colors.white70)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _packages.length,
                  itemBuilder: (context, i) => _packageCard(i),
                ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Text('Selected: ${_selected.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Total ₹${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, color: AppColors.primary)),
            ],
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

  Widget _packageCard(int i) {
    final p = _packages[i];
    final selected = _selected.contains(i);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('₹${p.price} · ${p.startDate}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Row(
                  children: [
                    const Text('Qty', style: TextStyle(fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _setQty(i, -1),
                    ),
                    Text(p.quantity,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _setQty(i, 1),
                    ),
                    const Spacer(),
                    const Text('Auto-renew', style: TextStyle(fontSize: 13)),
                    Checkbox(
                      value: p.autoRenewal == 1,
                      onChanged: (v) => setState(() => _packages[i] =
                          _packages[i].copyWith(autoRenewal: v == true ? 1 : 0)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
