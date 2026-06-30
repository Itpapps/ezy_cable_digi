import 'package:flutter/material.dart';
import 'data/employee_collection.dart';
import 'data/employee_track_repository.dart';

/// Employee Track (collection report) — Android parity (EmployeeTrackFragment,
/// SOAP `empCollection`). Date-range filter → per-employee collections. This is a
/// report (NOT GPS tracking — location-sending is handled by LocationSyncService).
class EmployeeTrackScreen extends StatefulWidget {
  const EmployeeTrackScreen({super.key});

  @override
  State<EmployeeTrackScreen> createState() => _EmployeeTrackScreenState();
}

class _EmployeeTrackScreenState extends State<EmployeeTrackScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  bool _loading = false;
  bool _error = false;
  String _message = '';
  List<EmployeeCollection> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await EmployeeTrackRepository.instance.getCollections(
      fromDate: _fmt(_from),
      toDate: _fmt(_to),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _items = r.items;
        _error = false;
      } else if (r.statusCode == 1) {
        _items = const [];
        _error = false;
        _message = r.statusMessage;
      } else {
        _items = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  Future<void> _pick(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  double get _total {
    var t = 0.0;
    for (final e in _items) {
      t += double.tryParse(e.amount) ?? 0;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
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
        title: const Text('EMPLOYEE TRACK',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1)),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _dateField('From', _from, () => _pick(true))),
                const SizedBox(width: 10),
                Expanded(child: _dateField('To', _to, () => _pick(false))),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('Search',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          if (!_loading && !_error && _items.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFF0D47A1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('Total — ₹${_total.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 44),
              const SizedBox(height: 12),
              Text(_message.isEmpty ? 'Could not load collections' : _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D47A1),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No collections found',
            style: TextStyle(color: Colors.white70, fontSize: 15)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final e = _items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name.isEmpty ? '-' : e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0D47A1))),
                    if (e.dealerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(e.dealerName,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('₹${e.amount.isEmpty ? '0' : e.amount}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D47A1))),
            ],
          ),
        );
      },
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5F5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
            const SizedBox(height: 2),
            Text(_fmt(value),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
