import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import '../../core/services/session_service.dart';
import '../../core/widgets/premium_dialog.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package_operations_repository.dart';
import 'active_packages_screen.dart';
import 'remove_services_screen.dart';
import 'schedule_services_screen.dart';
import 'services_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PACKAGE OPERATIONS — Dynamic Hub (Phase 2)
// Mirrors Android Box_Selection_new. Loads the customer's boxes live
// (getCustomerBoxes), lets the user pick a box, derives Active/DeActive (frozen
// rule: box_status "1" = Active), and shows permission-gated service actions.
// Defensive: loading / empty ("No Boxes") / error+retry states; never crashes.
// The action screens (Active Packages / Add / Schedule / Reactivate) are wired
// to real data in subsequent steps.
// ─────────────────────────────────────────────────────────────────────────────
class PackageOperationsScreen extends StatefulWidget {
  final Customer customer;
  final CustomerBox? preSelectedBox;
  const PackageOperationsScreen({super.key, required this.customer, this.preSelectedBox});

  @override
  State<PackageOperationsScreen> createState() =>
      _PackageOperationsScreenState();
}

class _PackageOperationsScreenState extends State<PackageOperationsScreen> {
  bool _loading = true;
  bool _error = false;
  String _message = '';
  List<CustomerBox> _boxes = const [];
  CustomerBox? _selectedBox;
  bool _isBoxLocked = false;
  bool _reactivating = false; // double-submit guard for rbox
  bool _extending = false; // double-submit guard for csews (Service Extension)
  String _serviceExtension = '0'; // customer-level service_extension flag (gcb)

  @override
  void initState() {
    super.initState();
    _loadBoxes();
  }

  Future<void> _loadBoxes() async {
    if (mounted) setState(() => _loading = true);
    final r = await PackageOperationsRepository.instance
        .getCustomerBoxes(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _boxes = r.boxes;
        _serviceExtension = r.serviceExtension; // carry customer flag to Remove Services
        // Preserve the user's selected box across refresh (don't snap to first).
        final prevId = _selectedBox?.boxId;
        _selectedBox = r.boxes.isEmpty
            ? null
            : r.boxes.firstWhere(
                (b) => b.boxId == prevId,
                orElse: () => r.boxes.first,
              );
        if (widget.preSelectedBox != null && !_isBoxLocked) {
          final match = r.boxes.where((b) => b.boxId == widget.preSelectedBox!.boxId);
          if (match.isNotEmpty) {
            _selectedBox = match.first;
            _isBoxLocked = true;
          }
        }
        _error = false;
      } else if (r.statusCode == 1) {
        _boxes = const []; // "No Boxes For this Customer" — empty, not an error
        _selectedBox = null;
        _error = false;
      } else {
        _boxes = const [];
        _selectedBox = null;
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error) {
      return _stateMessage(
        Icons.error_outline_rounded,
        _message.isEmpty ? 'Could not load boxes' : _message,
        retry: true,
      );
    }
    if (_boxes.isEmpty || _selectedBox == null) {
      return _stateMessage(Icons.tv_off_rounded, 'No Boxes For this Customer');
    }
    return RefreshIndicator(
      onRefresh: _loadBoxes,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _customerCard(_selectedBox!),
            const SizedBox(height: 12),
            _servicesCard(_selectedBox!),
          ],
        ),
      ),
    );
  }

  Widget _stateMessage(IconData icon, String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 44),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            if (retry) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadBoxes,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D47A1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Customer + box card (dynamic box selector + Active/DeActive state) ──────
  Widget _customerCard(CustomerBox box) {
    return _WhiteCard(
      child: Column(
        children: [
          _row('Customer Name', widget.customer.name),
          const _Sep(),
          _row('LCO Customer Id', widget.customer.lcoCustomerId),
          const _Sep(),
          _boxSelectorRow(box),
          const _Sep(),
          _row('VC Number', box.vcNumber.isEmpty ? 'N/A' : box.vcNumber),
          const _Sep(),
          _stateRow(box),
        ],
      ),
    );
  }

  Widget _boxSelectorRow(CustomerBox box) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 130,
            child: Text('Serial Number',
                style: TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CustomerBox>(
                  value: box,
                  isDense: true,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  items: _boxes
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              b.boxNumber.isEmpty ? b.vcNumber : b.boxNumber,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: _isBoxLocked ? null : (b) => setState(() => _selectedBox = b),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateRow(CustomerBox box) {
    final active = box.isActive;
    final color = active ? Colors.green.shade700 : Colors.red.shade600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 130,
            child: Text('Box Status',
                style: TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              box.stateLabel,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Services card — actions gated by role permissions (Phase 1.5 flags) ─────
  Widget _servicesCard(CustomerBox box) {
    final s = SessionService.instance;
    final tiles = <Widget>[
      _ServiceTile(
          label: 'Active Packages', onTap: () => _showActivePackages(box)),
      if (s.packageActivation)
        _ServiceTile(
          label: 'Add Services',
          onTap: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ServicesScreen(customer: widget.customer, box: box),
              ),
            );
            // cpo succeeded → re-fetch hub (Refresh Behavior Matrix).
            if (changed == true && mounted) _loadBoxes();
          },
        ),
      if (s.packageDeactivation)
        _ServiceTile(
          label: 'Remove Services',
          onTap: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => RemoveServicesScreen(
                    customer: widget.customer,
                    box: box,
                    serviceExtensionFlag: _serviceExtension),
              ),
            );
            if (changed == true && mounted) _loadBoxes();
          },
        ),
      if (s.scheduleService)
        _ServiceTile(
          label: 'Schedule Services',
          onTap: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ScheduleServicesScreen(customer: widget.customer, box: box),
              ),
            );
            if (changed == true && mounted) _loadBoxes();
          },
        ),
      // Service Extension — gated by box_wise_service_extension config flag
      // (Box_Selection_new:239), NOT the service_extension role permission.
      if (s.boxWiseServiceExtension)
        _ServiceTile(
            label: 'Service Extension',
            onTap: () => _confirmServiceExtension(box)),
      // Production parity (Box_Selection_new.java:164-166 + frag_box_selection
      // .xml:331-339 default VISIBLE): Reactivation is hidden ONLY when
      // box_status == "0"; shown otherwise (incl. Active "1"). NOT role-gated.
      if (box.boxStatus.trim() != '0')
        _ServiceTile(
            label: 'Reactivation', onTap: () => _confirmReactivate(box)),
    ];

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services(${box.boxNumber})',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D47A1)),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i < tiles.length - 1)
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ],
        ],
      ),
    );
  }

  void _showActivePackages(CustomerBox box) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivePackagesScreen(customer: widget.customer, box: box),
      ),
    );
  }

  Future<void> _confirmReactivate(CustomerBox box) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reactivate Box',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to Reactivate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _doReactivate(box);
  }

  Future<void> _doReactivate(CustomerBox box) async {
    if (_reactivating) return; // double-submit guard
    _reactivating = true;
    // C4 / Android Box_Selection_new reactivatebox :386: non-cancellable
    // "Loading...Please wait..." (Back ignored), so the pop below always closes
    // THIS loader. reactivateBox never throws (70 s timeout → status 3).
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    // Production sends the box's customer_id (not lcoCustomerId); fall back if empty.
    final customerId = box.customerId.isNotEmpty
        ? box.customerId
        : widget.customer.lcoCustomerId;
    final r = await PackageOperationsRepository.instance
        .reactivateBox(customerId: customerId, boxId: box.boxId);
    _reactivating = false;
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    // Status 0 → "Success!", status 1 → "No Details Found!". After OK the user
    // stays here and the boxes reload, so the new box status shows (like the
    // other operations on this screen). Android restarts MainActivity and lands
    // on the Dashboard — not followed (user decision). Transport error → "Failed", stay.
    if (r.statusCode == 0 || r.statusCode == 1) {
      await _reactResultDialog(
        r.statusCode == 0 ? 'Success!' : 'No Details Found!',
        r.statusMessage,
      );
      if (!mounted) return;
      _loadBoxes();
    } else {
      await _reactResultDialog(
          'Failed', r.statusMessage.isEmpty ? 'Please try again.' : r.statusMessage);
    }
  }

  Future<void> _confirmServiceExtension(CustomerBox box) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Service Extension with Box',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to extend services with box?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _doServiceExtension(box);
  }

  Future<void> _doServiceExtension(CustomerBox box) async {
    if (_extending) return; // double-submit guard
    _extending = true;
    // C4 / Android Box_Selection_new serviceextensionwithbox :279: same
    // non-cancellable loader. serviceExtensionWithBox never throws.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final customerId = box.customerId.isNotEmpty
        ? box.customerId
        : widget.customer.lcoCustomerId;
    final r = await PackageOperationsRepository.instance.serviceExtensionWithBox(
      customerId: customerId,
      boxId: box.boxId,
      stockId: box.stockId,
    );
    _extending = false;
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    // Production parity (Box_Selection_new:335-385): status 0 → "Success!",
    // status 1 → "No Details Found!" — both navigate home. Error → "Failed", stay.
    if (r.statusCode == 0 || r.statusCode == 1) {
      await _reactResultDialog(
        r.statusCode == 0 ? 'Success!' : 'No Details Found!',
        r.statusMessage,
      );
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst); // home (Dashboard)
    } else {
      await _reactResultDialog('Failed',
          r.statusMessage.isEmpty ? 'Please try again.' : r.statusMessage);
    }
  }

  Future<void> _reactResultDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message.isEmpty ? '-' : message),
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

  PreferredSizeWidget _buildAppBar() {
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
      title: const Text('PACKAGE OPERATIONS',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1)),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
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

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E7EB));
}

class _ServiceTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ServiceTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00ACC1))),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF00ACC1)),
          ],
        ),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
