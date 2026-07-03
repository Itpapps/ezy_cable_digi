import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/widgets/premium_dialog.dart';

/// Sync / Clear Data — Android parity (SyncData_Fragment).
///
/// A screen with two actions and live counts, exactly like Android:
///  • Sync Data  → POST /GetCollectionData per pending payment (flag=1),
///    ACK→flag=2 / NAK / retry. Reuses [OfflineSyncService].
///  • Clear Data → deletes the offline DB, but ONLY after all paid customers
///    are synced (Android guards this). Reuses [OfflineDataService.clearAllData].
///
/// No new engine/logic — this only presents the existing offline services.
/// Toast/dialog strings mirror Android's hardcoded English text.
class SyncClearScreen extends StatefulWidget {
  const SyncClearScreen({super.key});

  @override
  State<SyncClearScreen> createState() => _SyncClearScreenState();
}

class _SyncClearScreenState extends State<SyncClearScreen> {
  final _db = DatabaseHelper();
  int _total = 0; // downloaded records
  int _pending = 0; // flag=1 (paid, not yet synced)
  int _synced = 0; // flag=2 (synced)
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final total = await OfflineModeService.instance.downloadedRecordCount;
    final pending = await _db.getOfflinePaidCount();
    final synced = await _db.getOfflineSyncedCount();
    if (!mounted) return;
    setState(() {
      _total = total;
      _pending = pending;
      _synced = synced;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final n = await OfflineSyncService.instance.syncPendingToServer();
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        n > 0
            ? '$n record(s) synced'
            // Android SyncData_Fragment exact toast when there is nothing to sync.
            : 'No payments has been made (or) Check your internet connection.',
        isSuccess: n > 0,
      );
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        'Error syncing data. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    // Android: block clear until every paid customer is synced.
    if (_pending > 0) {
      showPremiumSnackBar(
        context,
        'Please sync all paid customer before you clear offline data.',
        isError: true,
      );
      return;
    }
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Are you sure?',
      body:
          'You are about to clear all your previous offline data. Please re-login after clearing data to reset machine ID.',
      confirmLabel: 'OK',
      cancelLabel: 'Cancel',
      isDanger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final cleared = _total;
    try {
      await OfflineDataService.instance.clearAllData();
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        '$cleared records has been cleared successfully',
        isSuccess: true,
      );
      await _refresh();
    } on OfflineDataException catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Clear failed. Please try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('SYNC / CLEAR DATA'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statRow('Downloaded records', '$_total'),
                  _statRow('Payments made (pending sync)', '$_pending'),
                  _statRow('Synced', '$_synced'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('SYNC DATA',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('CLEAR DATA',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
