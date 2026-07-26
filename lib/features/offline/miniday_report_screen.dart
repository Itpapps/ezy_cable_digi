import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../payment/printer_launcher.dart';

class MinidayReportScreen extends StatefulWidget {
  const MinidayReportScreen({super.key});

  @override
  State<MinidayReportScreen> createState() => _MinidayReportScreenState();
}

class _MinidayReportScreenState extends State<MinidayReportScreen> {
  final _db = DatabaseHelper();
  final _printerService = RealBluetoothService();
  Map<String, dynamic>? _summary;
  bool _loading = true;
  int _pendingToSync = 0;

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
    final now = DateTime.now();
    final todayStr =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final s = await _db.getOfflineTodaySummary(todayStr);
    final pendingPayments = await _db.getOfflinePaidCount();
    _pendingToSync = pendingPayments;
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  /// Thermal lines for the Mini Day report — Android parity
  /// (BluetoothChatService.write_mini_reports_off): MINI REPORT layout with
  /// Cash/Bank count+amount and TOTAL COLLECTION.
  List<String> _buildMinidayLines(ReceiptFormat fmt) {
    final s = _summary!;
    final cashC = '${s['cashCount']}';
    final bankC = '${s['bankCount']}';
    final cashA = (s['cashAmount'] as double).toStringAsFixed(2);
    final bankA = (s['bankAmount'] as double).toStringAsFixed(2);
    final total = (s['totalAmount'] as double).toStringAsFixed(2);
    final date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final w = fmt.is97bt; // 97BT (40-col) branch — Android write_mini_reports.
    final ind = w ? '  ' : '';

    return [
      fmt.sep,
      fitCenter('MINI REPORT', fmt.width),
      fmt.sep,
      fitCenter(date, fmt.width),
      fmt.sep,
      w ? '    MODE          COUNT       AMOUNT' : 'MODE      COUNT        AMOUNT',
      fmt.sep,
      // Android right-aligns COUNT/AMOUNT (fixedLengthString) → use fitRight.
      '${ind}Cash${fitRight(cashC, 10)}    ${fitRight(cashA, 10)}',
      '${ind}Bank${fitRight(bankC, 10)}    ${fitRight(bankA, 10)}',
      fmt.sep,
      w
          ? 'TOTAL COLLECTION -   ${fitRight('Rs.$total', 14)}'
          : 'TOTAL COLLECTION -  ${fitRight(total, 10)}',
      fmt.sep,
    ];
  }

  // Shared thermal-printer pipeline (same as the payment receipt).
  Future<void> _printReport() async {
    if (_summary == null) return;
    await launchThermalPrint(
      context: context,
      printerService: _printerService,
      buildLines: _buildMinidayLines,
    );
  }

  Future<void> _sync() async {
    await OfflineSyncService.instance.syncPendingToServer();
    await _load();
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
          'MINI DAY REPORT',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.1, color: t.appBarFg),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _printReport,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.print,
                              color: Colors.red, size: 20),
                          label: const Text(
                            'PRINT',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'MODE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'COUNT',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                'AMOUNT',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _row(
                          'CASH(STB)',
                          '${_summary!['cashCount']}',
                          '₹${(_summary!['cashAmount'] as double).toStringAsFixed(1)}',
                        ),
                        _row(
                          'BANK(STB)',
                          '${_summary!['bankCount']}',
                          '₹${(_summary!['bankAmount'] as double).toStringAsFixed(1)}',
                        ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 6,
                                child: Row(
                                  children: const [
                                    Icon(Icons.account_balance_wallet_outlined,
                                        size: 16, color: AppColors.primary),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'TOTAL COLLECTION',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '₹${(_summary!['totalAmount'] as double).toStringAsFixed(1)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pendingToSync > 0
                      ? SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _sync,
                            icon: const Icon(Icons.sync),
                            label: const Text(
                              'Click to Sync',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        )
                      : SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: Center(
                            child: Text(
                              'Synced.',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.redAccent.shade700,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  Widget _row(String mode, String count, String amount) {
    // Icon picked from the mode label only — presentation, no data/logic.
    final icon = mode.toUpperCase().startsWith('CASH')
        ? Icons.payments_outlined
        : Icons.account_balance_outlined;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(mode)),
              ],
            ),
          ),
          Expanded(
              flex: 2, child: Text(count, textAlign: TextAlign.center)),
          Expanded(
              flex: 3, child: Text(amount, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
