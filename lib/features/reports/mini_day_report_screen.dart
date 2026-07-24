import 'package:ezy_cable_digi/core/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/real_bluetooth_service.dart';
import '../../core/theme/theme_constants.dart';
import '../payment/printer_launcher.dart';
import 'data/mini_day_report_repository.dart';

class MiniDayReportScreen extends StatefulWidget {
  const MiniDayReportScreen({super.key});

  @override
  State<MiniDayReportScreen> createState() => _MiniDayReportScreenState();
}

class _MiniDayReportScreenState extends State<MiniDayReportScreen> {
  bool _loading = true;
  final _printerService = RealBluetoothService();
  MiniDayReportResult _data =
      const MiniDayReportResult(statusCode: 3, statusMessage: '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await MiniDayReportRepository.instance.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = r;
    });
  }

  /// Thermal lines — Android parity (BluetoothChatService.write_mini_reports):
  /// MINI REPORT with Cash(STB)/Bank(STB) and, when broadband data exists,
  /// Cash(BB)/Bank(BB), then TOTAL COLLECTION. No dealer/employee/footer
  /// (Android's mini-day printout does not include them).
  List<String> _buildMinidayLines(ReceiptFormat fmt) {
    final date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final w = fmt.is97bt; // 97BT (40-col) branch — Android write_mini_reports:2452
    // Android widens the amount column (8→10), indents rows 2 spaces, widens the
    // MODE header and prefixes the total with "Rs." on 97BT; 32-col is unchanged.
    final amtW = w ? 10 : 8;
    final modeHdr =
        w ? '    MODE          COUNT       AMOUNT' : 'MODE      COUNT        AMOUNT';
    final ind = w ? '  ' : '';
    final lines = <String>[
      fmt.sep,
      fitCenter('MINI REPORT', fmt.width),
      fmt.sep,
      fitCenter(date, fmt.width), // Android centers the date
      fmt.sep,
      modeHdr,
      fmt.sep,
      // Android right-aligns COUNT/AMOUNT via fixedLengthString (%1$Ns), so the
      // values line up under the headers — use fitRight, not fitLeft.
      '${ind}Cash(STB)${fitRight(_data.cashCount, 10)}   ${fitRight(_data.cashAmount, amtW)}',
      '${ind}Bank(STB)${fitRight(_data.bankCount, 10)}   ${fitRight(_data.bankAmount, amtW)}',
    ];
    if (_data.hasBroadband) {
      lines.add(
          '${ind}Cash(BB)${w ? ' ' : ''}${fitRight(_data.bbCashCount, 10)}   ${fitRight(_data.bbCashAmount, amtW)}');
      lines.add(
          '${ind}Bank(BB)${w ? ' ' : ''}${fitRight(_data.bbBankCount, 10)}   ${fitRight(_data.bbBankAmount, amtW)}');
    }
    lines.add(fmt.sep);
    lines.add(w
        ? 'TOTAL COLLECTION -   ${fitRight('Rs.${_data.totalAmount}', 14)}'
        : 'TOTAL COLLECTION -  ${fitRight(_data.totalAmount, 10)}');
    lines.add(fmt.sep);
    return lines;
  }

  /// Print via the shared thermal-printer pipeline (same as receipts/offline).
  /// Guards empty / failed report so there is no silent failure.
  Future<void> _printReport() async {
    if (_loading) return;
    if (_data.statusCode != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_data.statusMessage.isEmpty
                ? 'No records to print.'
                : _data.statusMessage)),
      );
      return;
    }
    await launchThermalPrint(
      context: context,
      printerService: _printerService,
      buildLines: _buildMinidayLines,
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
              color: t.backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppStrings.of(context, 'mini_day_report').toUpperCase(),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.1, color: t.appBarFg),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Print button row ──────────────────────────────────────────
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _printReport,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.sectionBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.print, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.of(context, 'print'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: t.bodyText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Data card ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: t.cardBorderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header row — fixed 3-column grid so values line up (Android parity)
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(AppStrings.of(context, 'mode'),
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 13, color: t.cardHeadingText)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(AppStrings.of(context, 'count'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 13, color: t.cardHeadingText)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(AppStrings.of(context, 'amount'),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 13, color: t.cardHeadingText)),
                      ),
                    ],
                  ),

                  Divider(
                      height: 20,
                      thickness: 1,
                      color: t.accent.withValues(alpha: 0.25)),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    // Cash row (STB)
                    _ReportRow(
                      label: AppStrings.of(context, 'cash_stb'),
                      count: _data.cashCount, amount: _data.cashAmount, t: t,
                    ),

                    const SizedBox(height: 10),

                    // Bank row (STB)
                    _ReportRow(
                      label: AppStrings.of(context, 'bank_stb'),
                      count: _data.bankCount, amount: _data.bankAmount, t: t,
                    ),

                    if (_data.hasBroadband) ...[
                      const SizedBox(height: 10),
                      _ReportRow(
                        label: 'Cash (BB)',
                        count: _data.bbCashCount, amount: _data.bbCashAmount, t: t,
                      ),
                      const SizedBox(height: 10),
                      _ReportRow(
                        label: 'Bank (BB)',
                        count: _data.bbBankCount, amount: _data.bbBankAmount, t: t,
                      ),
                    ],

                    Divider(
                      height: 20,
                      thickness: 1,
                      color: t.accent.withValues(alpha: 0.25)),

                    // Total row — amount aligned under the AMOUNT column
                    Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Text(
                            AppStrings.of(context, 'total_collection'),
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 14, color: t.accent),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '₹${_data.totalAmount}',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 14, color: t.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String count;
  final String amount;
  final AppThemeConst t;

  const _ReportRow({
    required this.label,
    required this.count,
    required this.amount,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: t.cardBodyText, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 2,
          child: Text(count,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.cardBodyText, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Text(amount,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: t.cardBodyText, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}