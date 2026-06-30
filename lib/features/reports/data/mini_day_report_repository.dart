import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/network/server_url_resolver.dart';
import '../../../core/services/session_service.dart';

/// Mini Day Report result — `miniDayCollections` (Android `MiniDayReport_Fragment`).
/// `casData[0]` = cash (STB), `casData[1]` = bank (STB). Optional `broadbandData`
/// adds cash/bank rows. `statusCode`: 0 = ok · 1 = no details · 3 = transport.
class MiniDayReportResult {
  final int statusCode;
  final String statusMessage;
  final String cashCount;
  final String cashAmount;
  final String bankCount;
  final String bankAmount;
  final bool hasBroadband;
  final String bbCashCount;
  final String bbCashAmount;
  final String bbBankCount;
  final String bbBankAmount;
  final String totalAmount;

  const MiniDayReportResult({
    required this.statusCode,
    required this.statusMessage,
    this.cashCount = '0',
    this.cashAmount = '0.0',
    this.bankCount = '0',
    this.bankAmount = '0.0',
    this.hasBroadband = false,
    this.bbCashCount = '0',
    this.bbCashAmount = '0.0',
    this.bbBankCount = '0',
    this.bbBankAmount = '0.0',
    this.totalAmount = '0.0',
  });
}

/// Mini Day Report — PLAIN REST `/packagelist/miniDayCollections`.
/// Params `imei, authtoken, request_from="FromDigiApp"` (no date — it's "today").
/// Defensive: any failure returns `statusCode 3`; never throws to the UI.
class MiniDayReportRepository {
  MiniDayReportRepository._();
  static final MiniDayReportRepository instance = MiniDayReportRepository._();

  /// Android adds an amount to the total only when its count > 0.
  static double _amtIfCounted(String count, String amount) {
    final c = double.tryParse(count) ?? 0;
    if (c <= 0) return 0;
    return double.tryParse(amount) ?? 0;
  }

  Future<MiniDayReportResult> fetch() async {
    try {
      final url =
          '${ServerUrlResolver.instance.namespace}/packagelist/miniDayCollections';
      final data = await RestClient.instance.postForm(
        url,
        {
          'imei': AppConfig.deviceImei,
          'authtoken': SessionService.instance.authToken,
          'request_from': 'FromDigiApp',
        },
        timeout: const Duration(seconds: 60),
      );
      final sc = data['status_code'];
      final status = sc is int ? sc : (int.tryParse('$sc') ?? 3);
      final msg = '${data['status_message'] ?? ''}';
      if (status != 0) {
        return MiniDayReportResult(statusCode: status, statusMessage: msg);
      }

      String cashCount = '0', cashAmt = '0.0', bankCount = '0', bankAmt = '0.0';
      final cas = _decodeList(data['casData']);
      if (cas.isNotEmpty) {
        cashAmt = '${cas[0]['amount'] ?? '0.0'}';
        cashCount = '${cas[0]['count'] ?? '0'}';
      }
      if (cas.length > 1) {
        bankAmt = '${cas[1]['amount'] ?? '0.0'}';
        bankCount = '${cas[1]['count'] ?? '0'}';
      }
      double total =
          _amtIfCounted(cashCount, cashAmt) + _amtIfCounted(bankCount, bankAmt);

      bool hasBb = false;
      String bbCashCount = '0', bbCashAmt = '0.0', bbBankCount = '0', bbBankAmt = '0.0';
      final bb = _decodeList(data['broadbandData']);
      if (bb.isNotEmpty) {
        hasBb = true;
        if (bb.isNotEmpty) {
          bbCashAmt = '${bb[0]['amount'] ?? '0.0'}';
          bbCashCount = '${bb[0]['count'] ?? '0'}';
        }
        if (bb.length > 1) {
          bbBankAmt = '${bb[1]['amount'] ?? '0.0'}';
          bbBankCount = '${bb[1]['count'] ?? '0'}';
        }
        total += _amtIfCounted(bbCashCount, bbCashAmt) +
            _amtIfCounted(bbBankCount, bbBankAmt);
      }

      return MiniDayReportResult(
        statusCode: 0,
        statusMessage: msg,
        cashCount: cashCount,
        cashAmount: cashAmt,
        bankCount: bankCount,
        bankAmount: bankAmt,
        hasBroadband: hasBb,
        bbCashCount: bbCashCount,
        bbCashAmount: bbCashAmt,
        bbBankCount: bbBankCount,
        bbBankAmount: bbBankAmt,
        totalAmount: total.toStringAsFixed(2),
      );
    } on TimeoutException {
      return const MiniDayReportResult(
          statusCode: 3, statusMessage: 'Request timed out.');
    } catch (_) {
      return const MiniDayReportResult(
          statusCode: 3, statusMessage: 'Could not connect to server.');
    }
  }

  /// Backend double-encodes `casData`/`broadbandData` as JSON-array strings.
  static List<Map<String, dynamic>> _decodeList(dynamic raw) {
    final v = raw is String ? _tryDecode(raw) : raw;
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  static dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
