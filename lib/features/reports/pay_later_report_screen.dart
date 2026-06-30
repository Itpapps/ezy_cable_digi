import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../collections/data/pay_later.dart';
import '../collections/data/pay_later_repository.dart';

/// Standalone Pay Later (Collection Schedule) report — Android `PayLaterReport`.
/// Filters: date range + name + account + CRF + status + employee. The list row
/// shows ONLY Customer Name / CRF / Status / Schedule Date (Android parity).
/// Reuses [PayLaterRepository.getPayLaterList] — no new APIs.
class PayLaterReportScreen extends StatefulWidget {
  const PayLaterReportScreen({super.key});

  @override
  State<PayLaterReportScreen> createState() => _PayLaterReportScreenState();
}

class _PayLaterReportScreenState extends State<PayLaterReportScreen> {
  final _nameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _crfCtrl = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _status = '';
  String _employeeId = '';

  bool _loading = true;
  String _message = '';
  List<PayLaterSchedule> _items = const [];
  List<String> _statuses = const [];
  List<PayLaterEmployee> _employees = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _accountCtrl.dispose();
    _crfCtrl.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await PayLaterRepository.instance.getPayLaterList(
      customerId: '',
      customerName: _nameCtrl.text.trim(),
      accountNumber: _accountCtrl.text.trim(),
      crfNumber: _crfCtrl.text.trim(),
      scheduledStartDate: _ymd(_startDate),
      scheduledEndDate: _ymd(_endDate),
      status: _status,
      employeeId: _employeeId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = r.schedules;
      _message = r.statusCode == 0 ? '' : r.statusMessage;
      // Spinners populate from the response (keep prior if a refetch returns none).
      if (r.statuses.isNotEmpty) _statuses = r.statuses;
      if (r.employees.isNotEmpty) _employees = r.employees;
    });
  }

  void _clear() {
    setState(() {
      _nameCtrl.clear();
      _accountCtrl.clear();
      _crfCtrl.clear();
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _status = '';
      _employeeId = '';
    });
    _load();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('PAY LATER',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _dateBox('Start Date', _startDate, () => _pickDate(true))),
              const SizedBox(width: 8),
              Expanded(child: _dateBox('End Date', _endDate, () => _pickDate(false))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(_nameCtrl, 'Customer Name')),
              const SizedBox(width: 8),
              Expanded(child: _field(_accountCtrl, 'Account No')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(_crfCtrl, 'CRF No')),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown(
                  hint: 'Status',
                  value: _status.isEmpty ? null : _status,
                  items: _statuses,
                  onChanged: (v) => setState(() => _status = v ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _dropdown(
            hint: 'Employee',
            value: _employeeId.isEmpty ? null : _employeeId,
            items: _employees.map((e) => e.id).toList(),
            labels: {for (final e in _employees) e.id: e.name},
            onChanged: (v) => setState(() => _employeeId = v ?? ''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : _clear,
                  child: const Text('CLEAR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('SEARCH'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No scheduled collections' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (_, i) => _PayLaterRow(item: _items[i]),
    );
  }

  // ── small UI helpers ────────────────────────────────────────────────────────
  Widget _field(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _dateBox(String label, DateTime d, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${d.day.toString().padLeft(2, '0')}-'
                  '${d.month.toString().padLeft(2, '0')}-${d.year}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<String> items,
    Map<String, String>? labels,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      hint: Text(hint, style: const TextStyle(fontSize: 13)),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: items
          .map((v) => DropdownMenuItem(
              value: v,
              child: Text(labels?[v] ?? v,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _PayLaterRow extends StatelessWidget {
  final PayLaterSchedule item;
  const _PayLaterRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _row('Customer Name', item.customerName.isEmpty ? 'NA' : item.customerName),
          if (item.crfno.isNotEmpty) _row('CRF No', item.crfno),
          _row('Status', item.status.isEmpty ? 'NA' : item.status),
          _row('Schedule Date', item.scheduledDate.isEmpty ? 'NA' : item.scheduledDate),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
