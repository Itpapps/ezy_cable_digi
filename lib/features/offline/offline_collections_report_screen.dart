import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/offline_customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../payment/printer_launcher.dart';

/// Offline Collections report — Android parity (Offline_Reports_Fragment +
/// Offline_ReportsResult_Fragment): pick a start/end date, query the offline
/// pay-queue by `last_paid_date`, show the record list with Total Count + total
/// amount, and Print All via the shared thermal-printer pipeline.
class OfflineCollectionsReportScreen extends StatefulWidget {
  const OfflineCollectionsReportScreen({super.key});

  @override
  State<OfflineCollectionsReportScreen> createState() =>
      _OfflineCollectionsReportScreenState();
}

class _OfflineCollectionsReportScreenState
    extends State<OfflineCollectionsReportScreen> {
  final _db = DatabaseHelper();
  final _printerService = RealBluetoothService();
  final _fmt = DateFormat('dd-MM-yyyy');

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();

  List<OfflineCustomer>? _results; // null = not searched yet
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  double get _total {
    if (_results == null) return 0;
    var sum = 0.0;
    for (final r in _results!) {
      sum += double.tryParse(r.lastPaidAmount) ?? 0;
    }
    return sum;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: now, // Android: not greater than current date
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _search() async {
    // Android validates start <= end; clamp defensively.
    if (_start.isAfter(_end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Start date must not be greater than end date')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _db.getOfflinePaymentsBetweenDates(
        _fmt.format(_start),
        _fmt.format(_end),
      );
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
      if (list.isEmpty && mounted) {
        // Android: Toast "No Records Found."
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Records Found.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load report. Please try again.';
      });
    }
  }

  /// Thermal lines — Android parity (write_reportscollection): COLLECTION REPORT
  /// with S.NO / NAME / AMOUNT columns + TOTAL AMOUNT.
  List<String> _buildCollectionsLines(ReceiptFormat fmt) {
    final records = _results ?? const [];
    final w = fmt.is97bt; // 97BT widens NAME/AMOUNT to fill the 40-col paper.
    final nameW = w ? 18 : 12;
    final amtW = w ? 14 : 12;
    final lines = <String>[
      fmt.sep,
      w ? fitCenter('COLLECTION  REPORT', fmt.width) : '      COLLECTION  REPORT',
      fmt.sep,
      '${_fmt.format(_start)} to ${_fmt.format(_end)}',
      fmt.sep,
      w
          ? fitLeft('S.NO', 8) + fitLeft('NAME', nameW) + fitRight('AMOUNT', amtW)
          : 'S.NO    NAME                AMOUNT',
      fmt.sep,
    ];
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      lines.add(fitLeft('${i + 1}', 8) +
          fitLeft(r.name, nameW) +
          fitRight(r.lastPaidAmount.isEmpty ? '0' : r.lastPaidAmount, amtW));
    }
    lines.add(fmt.sep);
    lines.add(
        fitLeft('TOTAL AMOUNT', 8 + nameW) + fitRight(_total.toStringAsFixed(2), amtW));
    lines.add(fmt.sep);
    return lines;
  }

  Future<void> _printAll() async {
    if (_results == null || _results!.isEmpty) return;
    await launchThermalPrint(
      context: context,
      printerService: _printerService,
      buildLines: _buildCollectionsLines,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('COLLECTIONS'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date range pickers + search
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _dateButton('From', _start, true)),
                    const SizedBox(width: 10),
                    Expanded(child: _dateButton('To', _end, false)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.search),
                    label: const Text('SEARCH',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _resultArea()),
        ],
      ),
    );
  }

  Widget _dateButton(String label, DateTime date, bool isStart) {
    return OutlinedButton(
      onPressed: () => _pickDate(isStart: isStart),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(_fmt.format(date),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _resultArea() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _search,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_results == null) {
      return const Center(
        child: Text('Select a date range and tap Search.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    if (_results!.isEmpty) {
      return const Center(
        child: Text('No Records Found.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text('Total Count - ${_results!.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              const Spacer(),
              Text('₹${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _printAll,
              icon: const Icon(Icons.print, color: Colors.red),
              label: const Text('PRINT ALL',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: _results!.length,
            itemBuilder: (context, i) {
              final r = _results![i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text(
                    '${r.lcoCustId.isEmpty ? r.customerId : r.lcoCustId} · ${r.payMode == 'R' ? 'CASH' : 'BANK'} · ${r.lastPaidDate}',
                  ),
                  trailing: Text(
                    '₹${r.lastPaidAmount}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
