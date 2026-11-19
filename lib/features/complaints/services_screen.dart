import 'package:flutter/material.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package.dart';
import '../packages/data/package_operations_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// Reusable Services Screen (Add Services / Schedule Services).
// Add Services — loads the per-box catalogue live via getCustomerPackages (gcp,
// act_type=1) grouped into Base / Add On / Alacarte; SAVE writes via cpo (act_type=1).
class ServicesScreen extends StatefulWidget {
  final Customer customer;
  final CustomerBox box;
  const ServicesScreen({super.key, required this.customer, required this.box});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _search = TextEditingController();

  bool _loading = true;
  bool _error = false;
  String _message = '';
  bool _submitting = false; // double-submit guard for the cpo write
  List<Package> _base = const [];
  List<Package> _addOn = const [];
  List<Package> _alaCarte = const [];

  // Selected package ids (across all tabs).
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: 0);
    _tab.addListener(() {
      if (mounted) setState(() {}); // swap visible list on tab change
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final r = await PackageOperationsRepository.instance.getCustomerPackages(
      customerId: widget.customer.lcoCustomerId,
      boxId: widget.box.boxId,
      casId: widget.box.casServerId,
      actType: 1, // activation list (Add / Schedule)
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _base = r.base;
        _addOn = r.addOn;
        _alaCarte = r.alaCarte;
        _error = false;
      } else if (r.statusCode == 1) {
        _base = const [];
        _addOn = const [];
        _alaCarte = const [];
        _error = false; // empty catalogue, not an error
      } else {
        _base = const [];
        _addOn = const [];
        _alaCarte = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  List<Package> get _currentList {
    switch (_tab.index) {
      case 0:
        return _base;
      case 1:
        return _addOn;
      case 2:
        return _alaCarte;
      default:
        return const [];
    }
  }

  List<Package> get _filtered {
    final q = _search.text.toLowerCase();
    if (q.isEmpty) return _currentList;
    return _currentList.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  String _priceText(Package p) =>
      p.price.isEmpty ? '' : (p.price.contains('₹') ? p.price : '₹${p.price}');

  @override
  Widget build(BuildContext context) =>
      MainFrame(snackBarLift: 68, child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppThemeConst.of(context).backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new,
                size: 16, color: AppThemeConst.of(context).backBtnIcon),
          ),
        ),
        title: Text('ADD SERVICES',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppThemeConst.of(context).appBarFg,
                letterSpacing: 1)),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: Colors.red,
              unselectedLabelColor: Colors.black87,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: Colors.red, width: 2.5),
              ),
              tabs: const [
                Tab(text: 'Base'),
                Tab(text: 'Add On'),
                Tab(text: 'Alacarte'),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '',
                icon: Icon(Icons.search, color: Colors.grey),
              ),
            ),
          ),
          Expanded(child: _listArea()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: GestureDetector(
          onTap: _submitting ? null : _onSave,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Color(0xFF0D47A1)))
                  : const Text('SAVE',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D47A1))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listArea() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF0D47A1)));
    }
    if (_error) {
      // Scrolls instead of overflowing on small phones (MainFrame bars).
      return CenterOrScroll(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.black45, size: 44),
              const SizedBox(height: 12),
              Text(_message.isEmpty ? 'Could not load packages' : _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return const Center(
          child: Text('List is Empty',
              style: TextStyle(fontSize: 18, color: Colors.black54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        final id = _idOf(p);
        final price = _priceText(p);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CheckboxListTile(
            value: _selected.contains(id),
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(id);
                } else {
                  _selected.remove(id);
                }
              });
            },
            activeColor: const Color(0xFF0D47A1),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(p.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D47A1))),
            subtitle: price.isEmpty
                ? null
                : Text(price,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        );
      },
    );
  }

  String _idOf(Package p) => p.packageId.isEmpty ? p.name : p.packageId;

  List<Package> get _allPackages => [..._base, ..._addOn, ..._alaCarte];

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF0D47A1)),
    );
  }

  Future<void> _onSave() async {
    if (_submitting) return; // double-submit guard
    final selected =
        _allPackages.where((p) => _selected.contains(_idOf(p))).toList();
    if (selected.isEmpty) {
      _snack('No packages selected');
      return;
    }
    final packageIds =
        selected.map((p) => p.packageId).where((id) => id.isNotEmpty).toList();
    if (packageIds.isEmpty) {
      _snack('Selected package has no id; cannot proceed.');
      return;
    }

    final confirmed = await _confirmActivation(selected);
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    // C12 / Android Frag_act_Pack :771: non-cancellable "Loading...Please
    // wait..." (Back ignored); activatePackages never throws (70 s → status 3).
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final r = await PackageOperationsRepository.instance.activatePackages(
      customerId: widget.customer.lcoCustomerId,
      boxId: widget.box.boxId,
      packageIds: packageIds,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _submitting = false);

    if (r.isSuccess) {
      await _resultDialog('Package Request!',
          r.statusMessage.isEmpty ? 'Request submitted.' : r.statusMessage);
      if (!mounted) return;
      Navigator.pop(context, true); // signal the hub to re-fetch
    } else {
      await _resultDialog(
          'Failed',
          r.statusMessage.isEmpty
              ? 'Could not complete the request.'
              : r.statusMessage);
    }
  }

  Future<bool?> _confirmActivation(List<Package> selected) {
    double total = 0;
    var allNumeric = true;
    for (final p in selected) {
      final v = double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v == null) {
        allNumeric = false;
      } else {
        total += v;
      }
    }
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Activation',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in selected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child:
                    Text('• ${p.name}', style: const TextStyle(fontSize: 14)),
              ),
            if (allNumeric && total > 0) ...[
              const SizedBox(height: 8),
              Text('Total: ₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ACTIVATE',
                style: TextStyle(
                    color: Color(0xFF0D47A1), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _resultDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFF0D47A1), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
