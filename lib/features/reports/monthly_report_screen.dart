import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../employee_track/data/employee_collection.dart';
import '../employee_track/data/employee_track_repository.dart';
import '../payment/printer_launcher.dart';

/// Parse an amount that may carry grouping separators / currency symbols
/// (e.g. "1,234.50") — strip everything but digits and the decimal point so
/// totals never silently become 0.
double _parseAmount(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

/// Monthly Report — Android parity (ReportsHome → Report_EmpCollect →
/// Reports_Emp_Collection_List → Employee_Collection_Details):
/// employee list (empCollection) + Total → tap → per-customer breakdown
/// (empCustomerCollectionDetails / `eccd`) → thermal print (shared helper).
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final _fmt = DateFormat('yyyy-MM-dd');
  final _printerService = RealBluetoothService();

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();

  List<EmployeeCollection>? _employees; // null = not searched yet
  bool _loading = false;
  String _message = '';

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  double get _total {
    if (_employees == null) return 0;
    var sum = 0.0;
    for (final e in _employees!) {
      sum += _parseAmount(e.amount);
    }
    return sum;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
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
    if (_start.isAfter(_end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Start date must not be greater than end date')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _message = '';
    });
    final r = await EmployeeTrackRepository.instance.getCollections(
      fromDate: _fmt.format(_start),
      toDate: _fmt.format(_end),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _employees = r.items;
      _message = r.statusCode == 0
          ? ''
          : (r.statusMessage.isEmpty ? 'Could not load report' : r.statusMessage);
    });
  }

  /// Print-all (employee list) — Android parity (write_reportscollection):
  /// COLLECTION REPORT with S.NO / NAME / AMOUNT columns + TOTAL AMOUNT.
  List<String> _buildListLines(ReceiptFormat fmt) {
    final emps = _employees ?? const [];
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
    for (var i = 0; i < emps.length; i++) {
      final e = emps[i];
      lines.add(fitLeft('${i + 1}', 8) +
          fitLeft(e.name, nameW) +
          fitRight(e.amount.isEmpty ? '0' : e.amount, amtW));
    }
    lines.add(fmt.sep);
    lines.add(
        fitLeft('TOTAL AMOUNT', 8 + nameW) + fitRight(_total.toStringAsFixed(2), amtW));
    lines.add(fmt.sep);
    return lines;
  }

  Future<void> _printList() async {
    if (_employees == null || _employees!.isEmpty) return;
    await launchThermalPrint(
      context: context,
      printerService: _printerService,
      buildLines: _buildListLines,
      batched: true, // long Collection Report → Android write_reports batching
    );
  }

  void _openDetail(EmployeeCollection e) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MonthlyReportDetailScreen(
          employeeId: e.employeeId,
          employeeName: e.name,
          employeeAmount: e.amount,
          fromDate: _fmt.format(_start),
          toDate: _fmt.format(_end),
          printerService: _printerService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: t.backBtnBg, borderRadius: BorderRadius.circular(10)),
            child:
                Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('MONTHLY REPORT',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: t.appBarFg)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter card — date range + Search, in a themed white card.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: t.cardShadowColor,
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _dateButton('From', _start, true, t)),
                      const SizedBox(width: 10),
                      Expanded(child: _dateButton('To', _end, false, t)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _search,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.search, size: 20),
                      label: const Text('SEARCH',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _resultArea(t)),
        ],
      ),
    );
  }

  // Date field — matches the Employee Track filter design: tappable soft card
  // with a leading calendar icon + label/value. Presentation only; the tap still
  // calls the same _pickDate and shows the same _fmt-formatted date.
  Widget _dateButton(
      String label, DateTime date, bool isStart, AppThemeConst t) {
    return GestureDetector(
      onTap: () => _pickDate(isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.06),
          border: Border.all(color: t.inputBorderColor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: t.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: t.cardSubtitleText,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(_fmt.format(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: t.cardBodyText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultArea(AppThemeConst t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_employees == null) {
      return Center(
        child: Text('Select a date range and tap Search.',
            style: TextStyle(color: t.subtitleText)),
      );
    }
    if (_message.isNotEmpty && _employees!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_message, style: TextStyle(color: t.bodyText)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _search,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.accent,
                side: BorderSide(color: t.inputBorderColor),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_employees!.isEmpty) {
      return Center(
        child: Text('No collections found',
            style: TextStyle(color: t.subtitleText)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: t.headerGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Total — ₹${_total.toStringAsFixed(2)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _printList,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.print, color: Colors.white, size: 18),
                label: const Text('Print',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: _employees!.length,
            itemBuilder: (context, i) {
              final e = _employees![i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_outline, color: t.accent, size: 20),
                  ),
                  title: Text(e.name.isEmpty ? '-' : e.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: t.cardHeadingText)),
                  subtitle: e.dealerName.isEmpty
                      ? null
                      : Text(e.dealerName,
                          style: TextStyle(color: t.cardSubtitleText)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${e.amount.isEmpty ? '0' : e.amount}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: t.accent)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 18, color: t.cardSubtitleText),
                    ],
                  ),
                  onTap: () => _openDetail(e),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Per-employee customer-wise collection detail (empCustomerCollectionDetails).
class _MonthlyReportDetailScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String employeeAmount; // employee's total (Android reclf_amt / amt111)
  final String fromDate;
  final String toDate;
  final RealBluetoothService printerService;

  const _MonthlyReportDetailScreen({
    required this.employeeId,
    required this.employeeName,
    required this.employeeAmount,
    required this.fromDate,
    required this.toDate,
    required this.printerService,
  });

  @override
  State<_MonthlyReportDetailScreen> createState() =>
      _MonthlyReportDetailScreenState();
}

class _MonthlyReportDetailScreenState
    extends State<_MonthlyReportDetailScreen> {
  List<EmployeeCustomerCollection>? _items; // null = loading
  String _message = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  double get _total {
    if (_items == null) return 0;
    var sum = 0.0;
    for (final c in _items!) {
      sum += _parseAmount(c.paidAmount);
    }
    return sum;
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _message = '';
    });
    final r = await EmployeeTrackRepository.instance.getCustomerCollections(
      fromDate: widget.fromDate,
      toDate: widget.toDate,
      employeeId: widget.employeeId,
    );
    if (!mounted) return;
    setState(() {
      _items = r.items;
      _message = r.statusCode == 0 || r.items.isNotEmpty
          ? ''
          : (r.statusMessage.isEmpty ? 'No records found' : r.statusMessage);
    });
  }

  /// Android parity (Employee_Collection_Details print): COLLECTION REPORT with
  /// employee name + S.NO / NAME / AMOUNT columns + TOTAL AMOUNT.
  List<String> _buildDetailLines(ReceiptFormat fmt) {
    final items = _items ?? const [];
    final w = fmt.is97bt; // 97BT widens NAME/AMOUNT to fill the 40-col paper.
    final nameW = w ? 18 : 12;
    final amtW = w ? 14 : 12;
    final lines = <String>[
      fmt.sep,
      w ? fitCenter('COLLECTION  REPORT', fmt.width) : '      COLLECTION  REPORT',
      fmt.sep,
      widget.employeeName,
      '${widget.fromDate} to ${widget.toDate}',
      fmt.sep,
      w
          ? fitLeft('S.NO', 8) + fitLeft('NAME', nameW) + fitRight('AMOUNT', amtW)
          : 'S.NO    NAME                AMOUNT',
      fmt.sep,
    ];
    for (var i = 0; i < items.length; i++) {
      final c = items[i];
      lines.add(fitLeft('${i + 1}', 8) +
          fitLeft(c.customerName, nameW) +
          fitRight(c.paidAmount.isEmpty ? '0' : c.paidAmount, amtW));
    }
    lines.add(fmt.sep);
    lines.add(
        fitLeft('TOTAL AMOUNT', 8 + nameW) + fitRight(_total.toStringAsFixed(2), amtW));
    lines.add(fmt.sep);
    return lines;
  }

  Future<void> _print() async {
    if (_items == null || _items!.isEmpty) return;
    await launchThermalPrint(
      context: context,
      printerService: widget.printerService,
      buildLines: _buildDetailLines,
      batched: true, // long Employee Collection detail → Android write_reports batching
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: t.backBtnBg, borderRadius: BorderRadius.circular(10)),
            child:
                Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('COLLECTION DETAILS',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: t.appBarFg)),
        actions: [
          if (_items != null && _items!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: _print,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Employee summary — themed white card.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: t.cardShadowColor,
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, size: 18, color: t.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(widget.employeeName,
                            style: TextStyle(
                                color: t.cardHeadingText,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Android parity (Employee_Collection_Details): the employee's
                  // total amount (reclf_amt) + the record count ("Total - N").
                  Text(
                      'Total Amount — ₹${widget.employeeAmount.isEmpty ? '0' : widget.employeeAmount}',
                      style: TextStyle(
                          color: t.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  if (_items != null) ...[
                    const SizedBox(height: 2),
                    Text('Total - ${_items!.length}',
                        style: TextStyle(
                            color: t.cardSubtitleText, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _body(AppThemeConst t) {
    if (_items == null) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_items!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_message.isEmpty ? 'No records found' : _message,
                style: TextStyle(color: t.subtitleText)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.accent,
                side: BorderSide(color: t.inputBorderColor),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items!.length,
      itemBuilder: (context, i) => _detailCard(_items![i]),
    );
  }

  /// Labeled card — Android parity (Employee_Collection_Details_Adapter /
  /// employee_collection_report_items.xml): Name, Acc. No., LCO Customer ID,
  /// CRF No (only when use_caf == 1), NickName, Address, Payment Date, Amount.
  Widget _detailCard(EmployeeCustomerCollection c) {
    final accNo = c.customNumber.isEmpty
        ? c.altCustId
        : '${c.altCustId} (${c.customNumber})';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Name', c.customerName.isEmpty ? '-' : c.customerName),
            _kv('Acc. No.', accNo.trim().isEmpty ? '-' : accNo),
            _kv('LCO Customer ID',
                c.altCustomNumber.isEmpty ? '-' : c.altCustomNumber),
            if (SessionService.instance.useCaf == 1)
              _kv('CRF No', c.crfNo.isEmpty ? 'NA' : c.crfNo),
            _kv('NickName', c.nickname.isEmpty ? 'NA' : c.nickname),
            _kv('Address', c.address.isEmpty ? '-' : c.address),
            _kv('Payment Date', c.paidOn.isEmpty ? '-' : c.paidOn),
            _kv('Amount', '₹${c.paidAmount.isEmpty ? '0' : c.paidAmount}',
                bold: true),
          ],
        ),
      ),
    );
  }

  // Decorative leading icon chosen by the row LABEL only — presentation
  // metadata; does NOT touch the label, value, or any logic.
  IconData _kvIcon(String label) {
    switch (label) {
      case 'Name':
        return Icons.person_outline;
      case 'Acc. No.':
        return Icons.tag;
      case 'LCO Customer ID':
        return Icons.badge_outlined;
      case 'CRF No':
        return Icons.description_outlined;
      case 'NickName':
        return Icons.sentiment_satisfied_outlined;
      case 'Address':
        return Icons.location_on_outlined;
      case 'Payment Date':
        return Icons.event_outlined;
      case 'Amount':
        return Icons.payments_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Widget _kv(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 138,
            child: Row(
              children: [
                Icon(_kvIcon(label), size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('$label:',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 12.5)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                    color: const Color(0xFF0D1B4B))),
          ),
        ],
      ),
    );
  }
}
