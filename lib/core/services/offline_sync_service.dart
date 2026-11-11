import '../database/database_helper.dart';
import 'offline_data_service.dart';

/// Offline sync service — wraps OfflineDataService for backward compat
/// and adds the old payments table sync as well.
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final DatabaseHelper _db = DatabaseHelper();
  final OfflineDataService _offlineEngine = OfflineDataService.instance;

  /// Count of old payments (synced=0) + offline queue (flag=1).
  Future<int> pendingSyncCount() async {
    final oldPending = await _db.countUnsyncedPayments();
    final offlinePending = await _db.getOfflinePaidCount();
    return oldPending + offlinePending;
  }

  /// Sync all pending offline payments to server (real /GetCollectionData).
  /// For old payments table, marks as synced locally.
  /// `failed` = rejected (NAK) or not reached; those stay pending (flag=1).
  Future<({int synced, int failed})> syncPendingToServer() async {
    // Sync real offline payments
    final result = await _offlineEngine.syncAllPending();
    // Also mark old payments table as synced
    final oldMarked = await _db.markAllPaymentsSynced();
    return (synced: result.synced + oldMarked, failed: result.failed);
  }

  /// Clear offline data after all synced.
  Future<void> clearLocalAfterSyncConfirm() async {
    await _offlineEngine.clearAllData();
    await _db.markAllPaymentsSynced();
  }
}
