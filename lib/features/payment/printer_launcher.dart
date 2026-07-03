import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/settings_store.dart';
import '../../core/widgets/premium_dialog.dart';

/// 32-column thermal separator (Android uses a dotted rule on most printers).
const String kReportSeparator = '................................';

/// Printer-dependent receipt layout, mirroring Android's BluetoothChatService
/// branches: printers whose name starts `97BT-` use a 40-column layout with a
/// dashed rule (`line_97bt`); every other printer uses the 32-column dotted rule
/// (`line`). Callers build their lines against the [sep]/[width]/[is97bt] of the
/// connected printer so output matches the corresponding Android branch exactly.
class ReceiptFormat {
  final int width;
  final String sep;
  final bool is97bt;
  const ReceiptFormat._(this.width, this.sep, this.is97bt);

  static const ReceiptFormat dots32 =
      ReceiptFormat._(32, '................................', false);
  static const ReceiptFormat dashes40 =
      ReceiptFormat._(40, '----------------------------------------', true);

  /// Android parity: `mConnectedDeviceName` starting `97BT-` → 40-col dashes,
  /// else 32-col dots. Unknown/empty names fall back to the 32-col default.
  factory ReceiptFormat.forPrinter(String? name) {
    final n = (name ?? '').trim().toUpperCase();
    return n.startsWith('97BT-') ? dashes40 : dots32;
  }
}

/// Left-align in a fixed width (Android `fixedLengthString_leftalign`): pad right,
/// truncate if longer.
String fitLeft(String s, int width) =>
    s.length >= width ? s.substring(0, width) : s.padRight(width);

/// Right-align in a fixed width (Android `fixedLengthString_Rightalign`): pad left,
/// truncate if longer.
String fitRight(String s, int width) =>
    s.length >= width ? s.substring(0, width) : s.padLeft(width);

/// Center within a fixed width (default 32-col paper) by left-padding spaces —
/// matches Android's centered report title/date.
String fitCenter(String s, [int width = 32]) {
  if (s.length >= width) return s;
  final lead = (width - s.length) ~/ 2;
  return (' ' * lead) + s;
}

/// Shared thermal-printer pipeline used by the payment receipt, the offline
/// Mini Day report, and the offline Collections report. Centralises the printer
/// picker (saved printer + scan + connect), ESC/POS write via
/// [RealBluetoothService.printReceipt], the 40s timeout, and the success/error
/// SnackBars — so there is exactly ONE printer flow to maintain.
///
/// [buildLines] returns the 32-col text lines to print (each caller builds its
/// own content; the print/connection behaviour is identical).
Future<void> launchThermalPrint({
  required BuildContext context,
  required RealBluetoothService printerService,
  required List<String> Function(ReceiptFormat fmt) buildLines,
  // Android print strategy by type: false = single write (receipts, Mini Day);
  // true = batched (long Collection/Employee reports). See printReceipt.
  bool batched = false,
}) async {
  // Android parity (DeviceListActivity auto-returns the saved device): if a
  // printer is saved AND still paired, connect + print directly — no picker.
  // Only fall back to the picker when nothing is saved, the saved printer is no
  // longer paired, or the auto-print fails.
  if (await _tryAutoPrint(context, printerService, buildLines, batched)) return;

  // Start from a clean connection (matches the receipt flow).
  try {
    await printerService.disconnectPrinter();
  } catch (_) {}

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AutoScanPrinterSheet(
      printerService: printerService,
      onPrint: (mac, fmt) =>
          _doThermalPrint(context, printerService, buildLines, mac, fmt, batched),
    ),
  );

  debugPrint('[DISCONNECT-MANUAL] disconnecting now (after sheet closed)');
  try {
    await printerService.disconnectPrinter();
  } catch (_) {}
  debugPrint('[DISCONNECT-MANUAL] disconnect complete');
}

/// Android-parity auto-print: prints to the saved printer without showing the
/// picker, but only when it is saved AND still in the paired list. Returns true
/// only if it actually printed; any miss/failure returns false so the caller
/// shows the picker (the user-chosen fallback). Never throws.
Future<bool> _tryAutoPrint(
  BuildContext context,
  RealBluetoothService printerService,
  List<String> Function(ReceiptFormat fmt) buildLines,
  bool batched,
) async {
  await SettingsStore.instance.load();
  final mac = SettingsStore.instance.printerMac;
  final name = SettingsStore.instance.printerName;
  debugPrint('[AUTO] _tryAutoPrint running — savedMac=${mac.isEmpty ? "(none)" : mac}');
  if (mac.isEmpty) return false; // nothing saved → picker

  // Android parity (ConnectThread): connect to the saved MAC directly — no
  // paired-list scan first (it can transiently report empty and wrongly force
  // the picker). `printReceipt` → `ensureConnected` handles the connect. On a
  // genuine connect/print failure we return false so the caller shows the
  // picker (the safety fallback).
  // Android parity (Bluetooth_Fragment: STATE_CONNECTING → non-cancelable
  // ProgressDialog "Connecting to Device..."): the saved-printer path connects
  // silently for 1–3s, so show the same blocking loader instead of a frozen UI.
  if (context.mounted) {
    showPremiumLoading(context, message: 'Connecting to Device...');
  }
  try {
    await printerService
        .printReceipt(
            mac: mac,
            lines: buildLines(ReceiptFormat.forPrinter(name)),
            batched: batched)
        .timeout(const Duration(seconds: 40));
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Printed Successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
    return true;
  } catch (_) {
    // Connection/print/timeout failure → fall back to the picker.
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return false;
  } finally {
    // Android parity (write → sleep(3000) → cancel/close): disconnect after the
    // print. printReceipt already settled ~2s post-write so the bytes finished
    // transmitting before we close (closing mid-transmission = "success" but no
    // paper). We no longer leave the socket open.
    debugPrint('[DISCONNECT-AUTO] disconnecting after auto-print');
    try {
      await printerService.disconnectPrinter();
    } catch (_) {}
  }
}

Future<void> _doThermalPrint(
  BuildContext context,
  RealBluetoothService printerService,
  List<String> Function(ReceiptFormat fmt) buildLines,
  String mac,
  ReceiptFormat fmt,
  bool batched,
) async {
  try {
    // Timeout so a printer that dies mid-write can't hang the loading forever.
    await printerService
        .printReceipt(mac: mac, lines: buildLines(fmt), batched: batched)
        .timeout(const Duration(seconds: 40));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Printed Successfully'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context); // close sheet
  } on TimeoutException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Print timed out — check the printer and try again.'),
          backgroundColor: Colors.red),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
    );
  }
}

/// Printer picker bottom sheet: scans paired devices, floats/pre-selects the
/// saved default printer, connects on tap, and prints on confirm. Shared by all
/// thermal-print callers (was private to the receipt screen).
class AutoScanPrinterSheet extends StatefulWidget {
  final RealBluetoothService printerService;
  final Future<void> Function(String mac, ReceiptFormat fmt) onPrint;

  const AutoScanPrinterSheet({
    super.key,
    required this.printerService,
    required this.onPrint,
  });

  @override
  State<AutoScanPrinterSheet> createState() => _AutoScanPrinterSheetState();
}

class _AutoScanPrinterSheetState extends State<AutoScanPrinterSheet> {
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selected;
  bool _isScanning = true;
  bool _isConnecting = false;
  bool _connected = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });
    try {
      // Permission + Bluetooth-on checks first, so failures aren't silent.
      final granted = await widget.printerService.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth permission denied. Enable it in Settings.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btOn) {
        if (!mounted) return;
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bluetooth is off. Turn it on and tap Rescan.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      final devices =
          List<BluetoothInfo>.from(await widget.printerService.getDevices());
      // Saved default printer (Android-style): float it to the top and
      // pre-select it so it is already highlighted. No auto-connect — the
      // user still taps it (or any other device) to connect and print.
      await SettingsStore.instance.load();
      final savedMac = SettingsStore.instance.printerMac;
      BluetoothInfo? preselect;
      if (savedMac.isNotEmpty) {
        final idx = devices.indexWhere((d) => d.macAdress == savedMac);
        if (idx != -1) {
          preselect = devices.removeAt(idx);
          devices.insert(0, preselect);
        }
      }
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selected = preselect; // pre-highlight saved printer (if present)
        _isScanning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connect(BluetoothInfo device) async {
    if (_isConnecting || _isPrinting) return; // no concurrent connect attempts
    setState(() {
      _isConnecting = true;
      _selected = device;
      _connected = false;
    });
    // Android parity (Bluetooth_Fragment STATE_CONNECTING): blocking,
    // non-cancelable "Connecting to Device..." dialog for the socket connect.
    if (mounted) showPremiumLoading(context, message: 'Connecting to Device...');
    // Single connect only — no second `ensureConnected` attempt (that reconnect
    // closed the socket we just opened and caused the reconnect loop).
    final ok = await widget.printerService.connectPrinter(device.macAdress);
    debugPrint('[PICKER 1] connectPrinter() returned = $ok (mac=${device.macAdress})');
    bool statusAfter = false;
    try {
      statusAfter = await PrintBluetoothThermal.connectionStatus;
    } catch (_) {}
    debugPrint('[PICKER 2] connectionStatus after connect = $statusAfter');
    debugPrint('[PICKER 3] selected="${device.name}" _connected=$ok');
    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    setState(() {
      _connected = ok;
      _isConnecting = false;
    });
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✗ Connection Failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _print() async {
    if (_selected == null || _isPrinting) return; // guard against double-print
    setState(() => _isPrinting = true);
    try {
      // Pick the Android-matching layout from the connected printer's name.
      await widget.onPrint(
          _selected!.macAdress, ReceiptFormat.forPrinter(_selected!.name));
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0277BD), Color(0xFF26C6DA)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Iconsax.printer,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              // Expanded (not fixed + Spacer) so the title yields space to the
              // trailing Rescan/Connected chips instead of overflowing the row.
              const Expanded(
                child: Text(
                  'Select Printer',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Rescan button
              GestureDetector(
                onTap: _isScanning ? null : _scan,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Rescan',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
              if (_connected) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth_connected,
                          size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Connected',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.green)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Device list or scanning indicator
          if (_isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Scanning for devices...',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else if (_devices.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No paired devices found.\nPair your printer in Bluetooth settings first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: _devices.map((d) {
                  final isSel = _selected?.macAdress == d.macAdress;
                  return GestureDetector(
                    onTap: _isConnecting ? null : () => _connect(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : const Color(0xFFF4F7FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel
                              ? AppColors.primary.withValues(alpha: 0.35)
                              : const Color(0xFFCBD5F5),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth,
                              size: 18,
                              color: isSel
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name.isEmpty ? 'Unknown Device' : d.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isSel
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  d.macAdress,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isConnecting && isSel)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            )
                          else if (isSel && _connected)
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 18)
                          else if (isSel)
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.primary, size: 18),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 14),

          // Print button — visible only after connected
          if (_connected)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isPrinting ? null : _print,
                icon: _isPrinting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Iconsax.printer, size: 18),
                label: Text(_isPrinting ? 'Printing...' : 'Print'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
