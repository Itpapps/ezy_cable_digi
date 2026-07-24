import 'package:flutter/material.dart';
import 'package:ezy_cable_digi/core/services/localization_service.dart';
import '../../core/constants/app_colors.dart';
import 'data/pay_later.dart';
import 'data/pay_later_repository.dart';

/// Collection Schedule (Pay Later report) — server-side, Android parity with
/// `PayLaterReport` (`scheduled_collection_data`). The single list response also
/// carries the employee + status LOVs. The legacy local-DB path
/// (`DatabaseHelper.searchCollectionSchedules` / `CollectionSchedule`) is retained
/// elsewhere but no longer used here. See OPERATIONAL_MODULES_PARITY.md.
class CollectionScheduleScreen extends StatefulWidget {
  const CollectionScheduleScreen({super.key});

  @override
  State<CollectionScheduleScreen> createState() =>
      _CollectionScheduleScreenState();
}

class _CollectionScheduleScreenState extends State<CollectionScheduleScreen> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _employeeId = ''; // '' = Choose (no filter)
  String _status = ''; // '' = Choose (no filter)
  final _customerNameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _crfCtrl = TextEditingController();

  bool _loading = false;
  bool _error = false;
  String _message = '';
  List<PayLaterSchedule> _results = const [];
  List<PayLaterEmployee> _employees = const [];
  List<String> _statuses = const [];

  @override
  void initState() {
    super.initState();
    _search(); // initial load (also fills the employee + status LOVs)
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _accountCtrl.dispose();
    _crfCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final r = await PayLaterRepository.instance.getPayLaterList(
      customerName: _customerNameCtrl.text.trim(),
      accountNumber: _accountCtrl.text.trim(),
      crfNumber: _crfCtrl.text.trim(),
      scheduledStartDate: _fmt(_startDate),
      scheduledEndDate: _fmt(_endDate),
      status: _status,
      employeeId: _employeeId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Keep the LOVs once the server has provided them.
      if (r.employees.isNotEmpty) _employees = r.employees;
      if (r.statuses.isNotEmpty) _statuses = r.statuses;
      if (r.statusCode == 0) {
        _results = r.schedules;
        _error = false;
      } else if (r.statusCode == 1) {
        _results = const []; // no records (Android shows the no-records view)
        _error = false;
        _message = r.statusMessage;
      } else {
        _results = const [];
        _error = true;
        _message = r.statusMessage;
      }
    });
  }

  void _clear() {
    setState(() {
      _startDate = DateTime.now();
      _endDate = DateTime.now();
      _employeeId = '';
      _status = '';
      _customerNameCtrl.clear();
      _accountCtrl.clear();
      _crfCtrl.clear();
    });
    _search();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      // ↓ Shrinks the body when the keyboard appears so nothing overflows.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        centerTitle: true,
        title: Text(
          AppStrings.of(context, 'collection_schedule').toUpperCase(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          // ↓ SingleChildScrollView lets the filter panel scroll up when the
          //   keyboard opens, preventing the "bottom overflowed" error on any
          //   screen size.
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.of(context, 'collection_schedule'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _dateField(AppStrings.of(context, 'start_date'),
                            _fmt(_startDate), _pickStart),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateField(AppStrings.of(context, 'end_date'),
                            _fmt(_endDate), _pickEnd),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _employeeDropdown()),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _textField(
                            AppStrings.of(context, 'customer_name'),
                            _customerNameCtrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _textField(
                            AppStrings.of(context, 'account_number'),
                            _accountCtrl),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _textField('CRF Number', _crfCtrl)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statusDropdown(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : _search,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(AppStrings.of(context, 'search'),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loading ? null : _clear,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(AppStrings.of(context, 'clear'),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              '${AppStrings.of(context, 'total_count')} - ${_results.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Expanded(child: _resultArea()),
        ],
      ),
    );
  }

  Widget _resultArea() {
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
              Text(_message.isEmpty ? 'Could not load schedules' : _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _search,
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
    if (_results.isEmpty) {
      return Center(
        child: Text(AppStrings.of(context, 'no_schedules_found'),
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _results.length,
      itemBuilder: (_, i) => _ScheduleCard(schedule: _results[i]),
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5F5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                const Icon(Icons.calendar_month, color: Colors.black54),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusDropdown() {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
          value: '', child: Text(AppStrings.of(context, 'select_status'))),
      ..._statuses
          .where((s) => s.isNotEmpty)
          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.of(context, 'select_status'),
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5F5)),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status,
              isExpanded: true,
              isDense: true,
              items: items,
              onChanged: (v) => setState(() => _status = v ?? ''),
            ),
          ),
        ),
      ],
    );
  }

  Widget _employeeDropdown() {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
          value: '', child: Text(AppStrings.of(context, 'select_employee'))),
      ..._employees.map(
          (e) => DropdownMenuItem(value: e.id, child: Text(e.name))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.of(context, 'select_employee'),
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5F5)),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _employeeId,
              isExpanded: true,
              isDense: true,
              items: items,
              onChanged: (v) => setState(() => _employeeId = v ?? ''),
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final PayLaterSchedule schedule;
  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
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
                Text(
                  schedule.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                if (schedule.altCustomNumber.isNotEmpty)
                  Text(
                    schedule.altCustomNumber,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  schedule.status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                schedule.scheduledDate,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (schedule.amount.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('₹${schedule.amount}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D47A1))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
