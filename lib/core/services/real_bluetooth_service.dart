import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

class RealBluetoothService {

  // 🔹 Permissions — simplified since startup already asked for them.
  // This is a safety net in case the user denied at startup.
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      final results = await [
        Permission.locationWhenInUse,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      final allGranted = results.values.every((s) => s.isGranted);

      if (!allGranted) {
        final anyPermanentlyDenied =
        results.values.any((s) => s.isPermanentlyDenied);
        if (anyPermanentlyDenied) {
          await openAppSettings();
        }
        return false;
      }

      return true;
    } catch (e) {
      print("Permission error: $e");
      return false;
    }
  }

  // 🔹 Get paired devices
  Future<List<BluetoothInfo>> getDevices() async {
    if (!AppConfig.bluetoothPrintingEnabled) return [];
    try {
      if (!await requestPermissions()) return [];
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      print("Device error: $e");
      return [];
    }
  }

  // 🔹 Connect
  Future<bool> connectPrinter(String mac) async {
    if (!AppConfig.bluetoothPrintingEnabled) return false;
    try {
      if (!await requestPermissions()) return false;
      await disconnectPrinter();

      final formatted = _formatMacAddress(mac);
      print("Connecting to $formatted");

      final connectResult = await PrintBluetoothThermal.connect(
        macPrinterAddress: formatted,
      );

      // Android parity (Bluetooth_Fragment MESSAGE_DEVICE_NAME → SystemClock.sleep(2000)):
      // a freshly-opened RFCOMM socket must warm up before the first write, or
      // the first write after a cold connect is silently lost (first-click, no
      // paper). Only on a successful FRESH connect. Warm reconnects reuse the
      // socket via ensureConnected and never call connectPrinter, so the second
      // print stays fast.
      if (connectResult) {
        await Future.delayed(const Duration(milliseconds: 2000));
      }

      // Poll briefly — some devices report "connected" with a slight delay
      for (int i = 0; i < 6; i++) {
        final isConnected = await PrintBluetoothThermal.connectionStatus;
        if (isConnected) return connectResult;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      return connectResult;
    } catch (e) {
      print("Connect error: $e");
      return false;
    }
  }

  Future<void> disconnectPrinter() async {
    // iOS: skip before touching the plugin at all. This method is called from
    // nine screens' dispose(), so without this guard the permission prompt
    // fires when the user merely leaves a screen, no print button tapped.
    //
    // MUST stay here rather than at the call sites: receipt_preview_screen.dart
    // :326 runs the offline NEXT CUSTOMER Navigator.pop() inside this Future's
    // .whenComplete(), and offline_unpaid_list_screen.dart:154 refreshes the
    // unpaid list only after that pop. A bare `return` in an async method still
    // completes the Future normally, so whenComplete fires and the pop happens.
    // Guarding at the call site would delete the pop along with the call.
    if (!AppConfig.bluetoothPrintingEnabled) return;

    try {
      // iOS: the plugin's `disconnect` branch force-unwraps a nil
      // `connectedPeripheral` (SwiftPrintBluetoothThermalPlugin.swift:244,
      // declared `CBPeripheral!`), trapping with EXC_BREAKPOINT whenever
      // disconnect runs before anything was ever connected — which is every
      // screen `dispose()` and the first line of connectPrinter. Android
      // null-guards the same path (`if (outputStream != null)`), so this only
      // ever bit iOS. `connectionStatus` uses optional chaining natively and is
      // safe to call at any time, so gate on it.
      final connected = await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!connected) return;

      // The plugin never answers `disconnect` synchronously — it replies from
      // the didDisconnectPeripheral delegate — so an unbounded await can hang
      // forever if that delegate never fires.
      await PrintBluetoothThermal.disconnect
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {}
  }

  // 🔹 Ensure connection
  Future<bool> ensureConnected(String mac) async {
    if (!AppConfig.bluetoothPrintingEnabled) return false;
    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      print("Connection status: $isConnected");

      if (!isConnected) {
        print("Reconnecting...");
        return await connectPrinter(mac);
      }

      await Future.delayed(const Duration(milliseconds: 600));
      return true;
    } catch (e) {
      print("Ensure error: $e");
      return false;
    }
  }

  // 🔹 Format MAC address
  String _formatMacAddress(String mac) {
    // iOS/CoreBluetooth identifies peripherals by UUID, never by MAC. This
    // Android-style reformatting can only ever corrupt a UUID, and the plugin
    // force-unwraps `UUID(uuidString:)` (SwiftPrintBluetoothThermalPlugin.swift:110)
    // — a corrupted value would trap there. Pass iOS addresses through as-is.
    if (!Platform.isAndroid) return mac;

    if (mac.contains(':') && mac.length == 17) {
      return mac.toUpperCase();
    }

    String cleaned = mac.replaceAll(RegExp(r'[:\s-]'), '').toUpperCase();

    if (cleaned.length == 12) {
      return cleaned
          .replaceAllMapped(RegExp(r'(.{2})'), (m) => '${m.group(1)}:')
          .substring(0, 17);
    }

    return mac;
  }

  // 🔹 Print receipt
  /// Prints the already-formatted receipt [lines] (32-col text, no ₹ — built to
  /// mirror the existing app's thermal layout). The caller owns the layout so
  /// the thermal print and the PDF stay identical.
  /// [batched] selects the Android print strategy by TYPE (not length):
  ///  • false (payment receipt, Mini Day) → ONE write + 3000ms settle
  ///    (Android BluetoothChatService `write` / `write_mini_reports`).
  ///  • true  (Collection / Employee reports) → 15-line batches + 6000ms settle
  ///    (Android `write_reports`), which the slow printer needs for long lists.
  Future<void> printReceipt({
    required String mac,
    required List<String> lines,
    bool batched = false,
  }) async {
    if (!AppConfig.bluetoothPrintingEnabled) return;
    // [PRINTDIAG] TEMPORARY instrumentation — logic unchanged.
    debugPrint('[PRINT 1] printReceipt entered — mac=$mac lines=${lines.length} batched=$batched');
    try {
      final connected = await ensureConnected(mac);
      debugPrint('[PRINT 2] ensureConnected returned = $connected');
      if (!connected) {
        throw Exception("Printer not connected");
      }
      debugPrint('[PRINT 3] receipt lines = ${lines.length} '
          'first="${lines.isEmpty ? '' : lines.first}" '
          'last="${lines.isEmpty ? '' : lines.last}"');

      await Future.delayed(const Duration(milliseconds: 600));

      // Android routes by print TYPE, not length:
      //  • receipts/mini-day (batched=false) → ONE write (the plugin prepends
      //    one "\n" per writeBytes, so a single write is byte-identical to the
      //    original receipt output).
      //  • long reports (batched=true) → 15-line batches with a settle between,
      //    because a long list in one write overflows the printer buffer and
      //    corrupts rows (Android write_reports:2101).
      const batch = 15;
      debugPrint('[PRINT 5] calling writeBytes()... lines=${lines.length} batched=$batched');
      bool writeResult = true;
      try {
        if (!batched) {
          final b = <int>[];
          b.addAll(utf8.encode("\n"));
          for (final l in lines) {
            b.addAll(utf8.encode("$l\n"));
          }
          b.addAll(utf8.encode("\n\n\n"));
          writeResult = await PrintBluetoothThermal.writeBytes(b);
        } else {
          // [BATCHDIAG] TEMPORARY per-batch instrumentation — batching logic,
          // delays, and rethrow behaviour are UNCHANGED.
          final totalBatches = (lines.length + batch - 1) ~/ batch;
          int batchNo = 0;
          for (int i = 0; i < lines.length; i += batch) {
            batchNo++;
            final end = (i + batch < lines.length) ? i + batch : lines.length;
            final b = <int>[];
            for (final l in lines.sublist(i, end)) {
              b.addAll(utf8.encode("$l\n"));
            }
            if (end >= lines.length) b.addAll(utf8.encode("\n\n\n"));

            bool connBefore = false;
            try {
              connBefore = await PrintBluetoothThermal.connectionStatus;
            } catch (_) {}
            final sw = Stopwatch()..start();
            bool r;
            try {
              r = await PrintBluetoothThermal.writeBytes(b);
            } catch (e) {
              sw.stop();
              bool connErr = false;
              try {
                connErr = await PrintBluetoothThermal.connectionStatus;
              } catch (_) {}
              debugPrint('[BATCH $batchNo/$totalBatches] lines=${i + 1}-$end '
                  'bytes=${b.length} connBefore=$connBefore EXCEPTION="$e" '
                  'connAfter=$connErr elapsedMs=${sw.elapsedMilliseconds}');
              rethrow;
            }
            sw.stop();
            bool connAfter = false;
            try {
              connAfter = await PrintBluetoothThermal.connectionStatus;
            } catch (_) {}
            debugPrint('[BATCH $batchNo/$totalBatches] lines=${i + 1}-$end '
                'bytes=${b.length} connBefore=$connBefore writeResult=$r '
                'connAfter=$connAfter elapsedMs=${sw.elapsedMilliseconds}');

            writeResult = writeResult && r;
            if (end < lines.length) {
              // Android write_reports sleeps 3000ms between 15-row batches.
              await Future.delayed(const Duration(milliseconds: 3000));
            }
          }
        }
        debugPrint('[PRINT 6] writeBytes returned = $writeResult');
      } catch (e, st) {
        debugPrint('[PRINT 6-EXCEPTION] writeBytes threw: $e');
        debugPrint('[PRINT 6-STACK] $st');
        rethrow;
      }

      // Android parity: wait after the write so the slow printer finishes
      // rendering BEFORE the caller closes the socket (closing mid-print =
      // "success" but a truncated report with no TOTAL).
      //   • Payment receipt (single write) → Android write() does sleep(3000).
      //   • Report (batched)               → Android write_reports does
      //     sleep(3000) after the last batch PLUS an extra sleep(3000)
      //     (BluetoothChatService:2108-2115) = 6000 ms before cancel/disconnect.
      final settleMs = batched ? 6000 : 3000;
      debugPrint('[SETTLE] last batch transmitted — waiting final settle '
          '${settleMs}ms before disconnect...');
      await Future.delayed(Duration(milliseconds: settleMs));
      debugPrint('[PRINT 8] printReceipt finished — writeResult=$writeResult '
          '(printReceipt does NOT disconnect — caller does)');
    } catch (e) {
      rethrow;
    }
  }
}