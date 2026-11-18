import 'dart:convert';

import 'package:intl/intl.dart';

import '../data/offline_customer.dart';
import '../database/database_helper.dart';
import '../network/rest_client.dart';
import '../network/server_url_resolver.dart';
import 'offline_mode_service.dart';
import 'session_service.dart';

/// Core offline engine — handles download, payment commit, sync, and clear.
/// Android parity: mirrors OfflineDataDownload_Fragment, SyncData_Fragment,
/// Offline_unPaidCustomer_Fragment payment logic, and NetworkChangeReceiver.
class OfflineDataService {
  OfflineDataService._();
  static final OfflineDataService instance = OfflineDataService._();

  final DatabaseHelper _db = DatabaseHelper();
  final RestClient _rest = RestClient.instance;
  bool _downloading = false;
  // Single-flight sync lock: while a sync run is in progress, every other
  // caller shares it instead of starting a second run (see [syncAllPending]).
  Future<({int synced, int failed})>? _syncInFlight;

  String get _baseUrl => ServerUrlResolver.instance.namespace;
  String get _downloadUrl => '$_baseUrl/GetRequest';
  String get _syncUrl => '$_baseUrl/GetCollectionData';
  String get _machineId => SessionService.instance.machineNumber;

  /// True only when this session came from an ONLINE login (the server gave a
  /// machine number). An offline-login session has none, so the server would
  /// reject every payment (NAK) — callers must not try to sync then.
  bool get canSync => _machineId.trim().isNotEmpty;

  // ═══════════════════════════════════════════════════════════════════════════
  // DOWNLOAD (Phase C) — Two-step: count then fetch
  // ═══════════════════════════════════════════════════════════════════════════

  /// Guard: check if there's unsyced payment data before allowing new download.
  Future<void> guardBeforeDownload() async {
    final pendingCount = await _db.getOfflinePaidCount();
    if (pendingCount > 0) {
      throw OfflineDataException(
          'You have $pendingCount unsynced payment(s). Sync them before downloading new data.');
    }
  }

  /// Step 1: Get record count from server.
  /// Returns count on success, throws on error.
  Future<int> downloadGetCount() async {
    final scrNo = _padRight(_machineId, 11) +
        _padRight('019', 3) +
        _padRight(':70', 3) +
        _padRight('', 3) + // startcount (3 spaces)
        _padRight('00000', 5); // endcount = 00000 means "get count"

    final response = await _rest.postRaw(_downloadUrl, {'ScrNo': scrNo});

    if (!response.contains('@:71')) {
      throw OfflineDataException('No records found to download.');
    }
    // Response format: first 9 chars contain status, chars [4..9] = count
    final countStr = response.substring(4, 9).trim();
    final count = int.tryParse(countStr);
    if (count == null || count <= 0) {
      throw OfflineDataException('No records found to download.');
    }
    return count;
  }

  /// Step 2: Download all records and insert into DB.
  /// [totalCount] from Step 1. Returns number of records inserted.
  Future<int> downloadRecords(int totalCount) async {
    if (_downloading) {
      throw OfflineDataException('Download already in progress.');
    }
    _downloading = true;
    try {
      final endCount = totalCount.toString().padLeft(5, '0');
      final scrNo = _padRight(_machineId, 11) +
          _padRight('019', 3) +
          _padRight(':70', 3) +
          _padRight('', 4) + // startcount (4 spaces)
          _padRight(endCount, 5);

      final response = await _rest.postRaw(_downloadUrl, {'ScrNo': scrNo});

      if (!response.contains('@:71')) {
        throw OfflineDataException('Error downloading data. Please try again.');
      }

      // Parse: first 9 chars are status code, rest is data
      String data = response.substring(9);
      data = data.replaceAll('#', '');

      if (data.isEmpty) {
        throw OfflineDataException('No data received from server.');
      }

      // B6 / Android OfflineDataDownload_Fragment :255-395: the reply must be
      // a whole number of 332-char records. Android hits the cut last record
      // (substring throws) and shows this message; Flutter used to drop it
      // silently and report success. Checked BEFORE the database is touched,
      // so the previous offline data stays intact (atomic replace below).
      if (data.length % 332 != 0) {
        throw OfflineDataException(
            'Error downloading data. Please contact Customer Care');
      }

      // Split into 332-char records
      final records = <String>[];
      for (var i = 0; i + 332 <= data.length; i += 332) {
        records.add(data.substring(i, i + 332));
      }

      if (records.isEmpty) {
        throw OfflineDataException('No valid records in download.');
      }

      // Parse all records in memory before touching the database
      final customers = records.map(_parseRecord).toList();

      // Atomic replacement: delete + insert all in one transaction.
      // If any insert fails, the entire transaction rolls back and
      // the previous valid dataset is preserved.
      final inserted = await _db.replaceAllOfflineCustomers(customers);

      // Save prefs (only reached after successful commit)
      await OfflineModeService.instance.recordDownload(
        totalRecords: inserted,
        machineId: _machineId,
        userCode: SessionService.instance.offlineUserCode,
      );

      return inserted;
    } finally {
      _downloading = false;
    }
  }

  /// Parse a single 332-char record into OfflineCustomer.
  OfflineCustomer _parseRecord(String rec) {
    return OfflineCustomer(
      lcoCrfNo: rec.substring(0, 13).trim(),
      accountNum: rec.substring(13, 26).trim(),
      name: rec.substring(26, 50).trim(),
      address: rec.substring(50, 74).trim(),
      billAmount: rec.substring(74, 87).trim(),
      taxAmount: rec.substring(87, 100).trim(),
      pendingAmount: rec.substring(100, 113).trim(),
      totalAmount: rec.substring(113, 126).trim(),
      month: rec.substring(126, 134).trim(),
      mobileNum: rec.substring(134, 146).trim(),
      lastPaidAmount: rec.substring(146, 159).trim(),
      lastPaidDate: rec.substring(159, 169).trim(),
      businessName: rec.substring(169, 194).trim(),
      customerId: rec.substring(194, 207).trim(),
      crfNumber: rec.substring(207, 220).trim(),
      lcoCustId: rec.substring(220, 233).trim(),
      paymentFlag: rec.substring(233, 236).trim(),
      discountAmount: rec.substring(236, 249).trim(),
      totalAfterDiscount: rec.substring(249, 262).trim(),
      discountStartDate: rec.substring(262, 272).trim(),
      discountEndDate: rec.substring(272, 282).trim(),
      penaltyAmount: rec.substring(282, 295).trim(),
      totalAfterPenalty: rec.substring(295, 308).trim(),
      penaltyStartDate: rec.substring(308, 318).trim(),
      penaltyEndDate: rec.substring(318, 328).trim(),
      discountPenaltyFlag: rec.substring(328, 332).trim(),
      amount: '0.00',
      flag: 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT (Phase D) — Commit offline payment
  // ═══════════════════════════════════════════════════════════════════════════

  /// Commit an offline payment. Updates offline_customers and inserts into
  /// offline_payments queue. Returns the updated model.
  Future<OfflineCustomer> commitPayment({
    required OfflineCustomer customer,
    required double amount,
    required String payMode, // "R" or "B"
    required bool sendSms,
    String chequeNumber = '',
    String bankName = '',
    String branchName = '',
    String insDate = '',
    String discountPenaltyFlag = '0000',
  }) async {
    // Duplicate guard: if already paid, reject
    if (customer.flag != 0) {
      throw OfflineDataException('Payment already made for this customer.');
    }

    final now = DateTime.now();
    final timeStamp = DateFormat('dd-MM-yyyy HH:mm:ss').format(now);
    final timestamp2 = DateFormat('dd-MM-yyyy').format(now);
    final tstamp = DateFormat('ddMMyyyyHHmmss').format(now);
    final receiptNum = '$tstamp${customer.customerId}';

    final updated = customer.copyWith(
      flag: 1,
      amount: amount.toStringAsFixed(2),
      paymentDate: timeStamp,
      lastPaidDate: timestamp2,
      lastPaidAmount: amount.toStringAsFixed(2),
      payMode: payMode,
      sendSms: sendSms ? '015' : '005',
      chequeNumber: chequeNumber,
      bankName: bankName,
      branchName: branchName,
      insDate: insDate,
      discountPenaltyFlag: discountPenaltyFlag,
      syncPaymentDate: receiptNum, // store receipt number here for sync
    );

    // DB operations: insert into payment queue + update customer table
    await _db.insertOfflinePayment(updated);
    await _db.updateOfflineCustomerAfterPayment(updated);

    // Update outstanding amount
    final outstanding = _calculateOutstanding(updated, amount);
    if (outstanding >= 0) {
      await _db.updateOfflineCustomerOutstanding(
          customer.customerId, outstanding.toStringAsFixed(2));
    }

    return updated;
  }

  double _calculateOutstanding(OfflineCustomer c, double paidAmount) {
    double totalDue;
    if (c.discountPenaltyFlag.contains('D')) {
      totalDue = double.tryParse(c.totalAfterDiscount) ?? 0;
    } else if (c.discountPenaltyFlag.contains('P')) {
      totalDue = double.tryParse(c.totalAfterPenalty) ?? 0;
    } else {
      totalDue = double.tryParse(c.totalAmount) ?? 0;
    }
    return totalDue - paidAmount;
  }

  /// Generate receipt number for a customer payment.
  String generateReceiptNum(String customerId) {
    final tstamp = DateFormat('ddMMyyyyHHmmss').format(DateTime.now());
    return '$tstamp$customerId';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC (Phase E) — POST to /GetCollectionData
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync a single payment to server. Returns true if ACK, false if NAK.
  /// Throws on network/server error (row stays at flag=1 for retry).
  /// Private on purpose: payments reach the server only through the locked
  /// [syncAllPending], so no caller can bypass the single-flight lock.
  Future<bool> _syncPayment(OfflineCustomer payment) async {
    final tstamp = DateFormat('ddMMyyyyHHmmss').format(DateTime.now());
    final receiptNum = '$tstamp${payment.customerId}';

    // Build fixed-length request string
    final machineId = _padRight(_machineId, 11);
    final version = _padRight('019', 3);
    final command = _padRight(':50', 3);
    final customerNumber = _padRight(payment.customerId, 13);
    final paidAmount = _padRight(payment.amount, 13);
    final payMode = _padRight(payment.payMode, 1);
    final altReceipt = _padRight(receiptNum, 25);
    final hhtPaidDate = _padRight(payment.paymentDate, 19);
    final dpFlag = _padRight(payment.discountPenaltyFlag, 4);

    String req;
    if (payment.payMode == 'R') {
      req = machineId +
          version +
          command +
          customerNumber +
          paidAmount +
          payMode +
          altReceipt +
          hhtPaidDate +
          dpFlag;
    } else {
      final cheque = _padRight(payment.chequeNumber, 6);
      final bank = _padRight(payment.bankName, 19);
      final branch = _padRight(payment.branchName, 19);
      final insdate = _padRight(payment.insDate, 8);
      req = machineId +
          version +
          command +
          customerNumber +
          paidAmount +
          payMode +
          altReceipt +
          cheque +
          bank +
          branch +
          insdate +
          hhtPaidDate +
          dpFlag;
    }

    final encodedBuffer = base64Encode(utf8.encode(req));
    final params = {
      'type': '3',
      'payment_flag': payment.sendSms,
      'buffer': encodedBuffer,
    };

    final response = await _rest.postRaw(_syncUrl, params);
    final trimmed = response.trim();

    if (trimmed.toUpperCase() == 'ACK') {
      // Success: mark synced (flag=2)
      final synced = payment.copyWith(
        flag: 2,
        syncPaymentDate: tstamp.substring(0, 8),
      );
      await _db.updateOfflineCustomerAfterPayment(synced);
      await _db.updateOfflinePaymentAfterSync(synced);
      return true;
    } else if (trimmed.toUpperCase() == 'NAK') {
      // Server rejected (B2). Android bulk sync / auto-sync (SyncData_Fragment
      // :208-209, MainActivity :950-951) leave the row at flag=1: the payment
      // stays pending, is retried next sync, and Clear Data stays blocked.
      // Resetting to 0 made a collected payment look unpaid and deletable.
      return false;
    } else {
      // Unknown response — keep at flag=1, will retry
      throw OfflineDataException('Sync error: $trimmed');
    }
  }

  /// Sync ALL pending payments (flag=1). Returns (synced, failed) counts.
  ///
  /// Single-flight: if a sync is already running, the caller gets that same
  /// run instead of starting another, so a pending payment is never sent twice
  /// in parallel. All five sync triggers (auto-sync, offline-dashboard exit,
  /// Miniday, Sync/Clear, Download screen) reach the server only through here.
  Future<({int synced, int failed})> syncAllPending() {
    return _syncInFlight ??=
        _runSyncAllPending().whenComplete(() => _syncInFlight = null);
  }

  Future<({int synced, int failed})> _runSyncAllPending() async {
    // No machine ID (offline-login session, or before any online login): do
    // not contact the server. Pending payments stay at flag=1 untouched and are
    // reported as not synced (synced: 0), so no caller shows a success message.
    if (!canSync) {
      final skipped = await _db.getOfflinePaidCount();
      return (synced: 0, failed: skipped);
    }
    final pending = await _db.getOfflinePaymentsByFlag(1);
    int synced = 0;
    int failed = 0;
    for (final p in pending) {
      try {
        final ok = await _syncPayment(p);
        if (ok) {
          synced++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    return (synced: synced, failed: failed);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEAR DATA (Phase F) — Only after all synced
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear all offline data. Only allowed when no pending (flag=1) payments.
  Future<void> clearAllData() async {
    final pendingCount = await _db.getOfflinePaidCount();
    if (pendingCount > 0) {
      throw OfflineDataException(
          'Please sync all paid customers first ($pendingCount pending).');
    }
    await _db.deleteAllOfflineData();
    await OfflineModeService.instance.clearOfflineData();
    await OfflineModeService.instance.setOfflineMode(false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Right-pad string with spaces to [length] (Android fixedLengthString).
  String _padRight(String s, int length) {
    if (s.length >= length) return s.substring(0, length);
    return s.padRight(length);
  }
}

class OfflineDataException implements Exception {
  final String message;
  OfflineDataException(this.message);
  @override
  String toString() => message;
}
