import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'offline_data_service.dart';
import 'offline_mode_service.dart';

/// Listens for network reconnection and auto-syncs pending offline payments.
/// Android parity: mirrors NetworkChangeReceiver auto-sync behavior.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isSyncing = false;

  /// Start listening. Call once from app initialization.
  void startListening() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onChanged(List<ConnectivityResult> results) async {
    // If we have network and there's pending sync data, auto-sync
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

    if (!hasNetwork) return;
    if (_isSyncing) return;

    final isOffline = await OfflineModeService.instance.isOfflineMode;
    if (!isOffline) return;

    _isSyncing = true;
    try {
      final result = await OfflineDataService.instance.syncAllPending();
      if (result.synced > 0) {
        print('ConnectivityService: Auto-synced ${result.synced} payment(s)');
      }
    } catch (_) {
      // Silently fail — will retry on next connectivity change
    } finally {
      _isSyncing = false;
    }
  }

  /// Check current connectivity (utility).
  Future<bool> get hasNetwork async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }
}
