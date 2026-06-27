import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import '../../core/services/session_service.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package.dart';
import '../packages/data/package_operations_repository.dart';

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
  const PackageOperationsScreen({super.key, required this.customer});

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
        // Preserve the user's selected box across refresh (don't snap to first).
        final prevId = _selectedBox?.boxId;
        _selectedBox = r.boxes.isEmpty
            ? null
            : r.boxes.firstWhere(
                (b) => b.boxId == prevId,
                orElse: () => r.boxes.first,
              );
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
                  onChanged: (b) => setState(() => _selectedBox = b),
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
                builder: (_) => _ServicesScreen(
                    title: 'ADD SERVICES', customer: widget.customer, box: box),
              ),
            );
            // cpo succeeded → re-fetch hub (Refresh Behavior Matrix).
            if (changed == true && mounted) _loadBoxes();
          },
        ),
      if (s.scheduleService)
        _ServiceTile(
          label: 'Schedule Services',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ServicesScreen(
                  title: 'SCHEDULE SERVICES',
                  customer: widget.customer,
                  box: box),
            ),
          ),
        ),
      // Production parity (Box_Selection_new.java:164-166 + frag_box_selection
      // .xml:331-339 default VISIBLE): Reactivation is hidden ONLY when
      // box_status == "0"; shown otherwise (incl. Active "1"). NOT role-gated.
      if (box.boxStatus.trim() != '0')
        _ServiceTile(label: 'Reactivation', onTap: _confirmReactivate),
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

  void _confirmReactivate() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reactivate Box',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to Reactivate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('NO',
                style:
                    TextStyle(color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Box Reactivated Successfully'),
                    backgroundColor: Colors.green),
              );
            },
            child: const Text('YES',
                style:
                    TextStyle(color: Colors.orange, fontWeight: FontWeight.w700)),
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

// ActivePackagesScreen — live active/deactive packages via
// getcustomerpackageslist (gcpl). Status filter maps Active→"1", Deactive→"0"
// (verified). Read-only view; _ServicesScreen write (cpo) is wired in Phase 3.
class ActivePackagesScreen extends StatefulWidget {
  final Customer customer;
  final CustomerBox box;
  const ActivePackagesScreen(
      {super.key, required this.customer, required this.box});

  @override
  State<ActivePackagesScreen> createState() => _ActivePackagesScreenState();
}

class _ActivePackagesScreenState extends State<ActivePackagesScreen> {
  String _status = 'Select';
  final _statuses = ['Select', 'Active', 'Deactive'];

  bool _loading = false;
  bool _error = false;
  String _message = '';
  bool _fetched = false;
  List<ActivePackage> _packages = const [];

  Future<void> _load() async {
    if (_status == 'Select') {
      setState(() {
        _fetched = false;
        _packages = const [];
        _error = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await PackageOperationsRepository.instance.getCustomerPackageList(
      customerId: widget.customer.lcoCustomerId,
      boxId: widget.box.boxId,
      status: _status == 'Active' ? '1' : '0',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fetched = true;
      if (r.statusCode == 0) {
        _packages = r.packages;
        _error = false;
      } else if (r.statusCode == 1) {
        _packages = const [];
        _error = false; // none found for this filter
      } else {
        _packages = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
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
        title: const Text('ACTIVE PACKAGES',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0277BD), Color(0xFF26C6DA)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('ACTIVE PACKAGES',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Serial Number',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF5B7BAE))),
                      Text(
                          widget.box.boxNumber.isEmpty
                              ? '-'
                              : widget.box.boxNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D47A1))),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vc Number',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF5B7BAE))),
                      Text(
                          widget.box.vcNumber.isEmpty
                              ? '-'
                              : widget.box.vcNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D47A1))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Choose Status',
                style: TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _status,
                  isExpanded: true,
                  items: _statuses
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _status = v ?? 'Select');
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            _resultArea(),
          ],
        ),
      ),
    );
  }

  Widget _resultArea() {
    if (_status == 'Select') {
      return _hint('Choose a status to view packages.');
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child:
            Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))),
      );
    }
    if (_error) {
      return Column(
        children: [
          _hint(_message.isEmpty ? 'Could not load packages.' : _message),
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
      );
    }
    if (!_fetched) return const SizedBox.shrink();
    if (_packages.isEmpty) {
      return _hint('No $_status packages found.');
    }
    return Column(children: _packages.map(_packageCard).toList());
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ),
      );

  Widget _packageCard(ActivePackage p) {
    final price = p.price.isEmpty
        ? ''
        : (p.price.contains('₹') ? p.price : '₹${p.price}');
    final dates =
        [p.startDate, p.endDate].where((e) => e.isNotEmpty).join('  →  ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name.isEmpty ? '-' : p.name,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D47A1))),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(dates,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B7BAE))),
          ],
          if (price.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(price,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black87)),
            ),
          ],
        ],
      ),
    );
  }
}

// Reusable Services Screen (Add Services / Schedule Services).
// Loads the per-box package catalogue live via getCustomerPackages (gcp,
// act_type=1 → activatable list) and groups it into Base / Add On / Alacarte.
// SAVE still only previews the selection — the write (cpo) is the next step.
class _ServicesScreen extends StatefulWidget {
  final String title;
  final Customer customer;
  final CustomerBox box;
  const _ServicesScreen(
      {required this.title, required this.customer, required this.box});

  @override
  State<_ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<_ServicesScreen>
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
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
        title: Text(widget.title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
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
      return Center(
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
    // Only Add Services performs the cpo write (act_type=1). Schedule Services
    // is a separate, not-yet-investigated feature.
    if (widget.title != 'ADD SERVICES') {
      _snack('Scheduling is not enabled yet.');
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
    final r = await PackageOperationsRepository.instance.activatePackages(
      customerId: widget.customer.lcoCustomerId,
      boxId: widget.box.boxId,
      packageIds: packageIds,
    );
    if (!mounted) return;
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
