import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package.dart';
import '../packages/data/package_operations_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

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

  // C10: id of the latest request — a reply for an older selection is dropped,
  // so the list always matches the status shown.
  int _req = 0;

  Future<void> _load() async {
    final req = ++_req;
    if (_status == 'Select') {
      setState(() {
        _loading = false;
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
    if (!mounted || req != _req) return; // C10: stale reply
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
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
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
                  // C10 / Android ActivePackagesFragment :150: the modal
                  // "Loading...Please wait..." blocks the dropdown while the
                  // list loads — same here (disabled until the load ends).
                  onChanged: _loading
                      ? null
                      : (v) {
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
