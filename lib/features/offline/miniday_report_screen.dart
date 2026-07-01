import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
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
      '${ind}Cash${fitLeft(cashC, 10)}    ${fitLeft(cashA, 10)}',
      '${ind}Bank${fitLeft(bankC, 10)}    ${fitLeft(bankA, 10)}',
      fmt.sep,
      w
          ? 'TOTAL COLLECTION -   ${fitLeft('Rs.$total', 14)}'
          : 'TOTAL COLLECTION -  ${fitLeft(total, 10)}',
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
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('MINI DAY REPORT'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _printReport,
                          icon: const Icon(Icons.print, color: Colors.red),
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
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'MODE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'COUNT',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'AMOUNT',
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
                              const Expanded(
                                child: Text(
                                  'TOTAL COLLECTION',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                (_summary!['totalAmount'] as double)
                                    .toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(mode)),
          Expanded(child: Text(count)),
          Expanded(child: Text(amount)),
        ],
      ),
    );
  }
}
