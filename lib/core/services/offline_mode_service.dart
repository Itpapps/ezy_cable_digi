import 'package:shared_preferences/shared_preferences.dart';

/// Manages offline-mode state in SharedPreferences.
/// Android parity: mirrors OFFLINEFLAG, MACHINE_ID, USERCODE, total_length.
class OfflineModeService {
  OfflineModeService._();
  static final OfflineModeService instance = OfflineModeService._();

  static const _keyOffline = 'is_offline_mode';
  static const _keyDownloadedRecords = 'offline_downloaded_record_count';
  static const _keyLastDownload = 'offline_last_download_iso';
  // Android parity keys
  static const _keyOfflineFlag = 'offlinedataflag'; // 0=data present, 1=cleared/synced
  static const _keyMachineId = 'machineNumber';
  static const _keyUserCode = 'usercode';
  static const _keyTotalLength = 'total_length';

  Future<bool> get isOfflineMode async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyOffline) ?? false;
  }

  Future<void> setOfflineMode(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyOffline, value);
  }

  Future<void> recordDownload({
    required int totalRecords,
    required String machineId,
    required String userCode,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyDownloadedRecords, totalRecords);
    await p.setString(_keyLastDownload, DateTime.now().toIso8601String());
    await p.setInt(_keyOfflineFlag, 0); // 0 = data inserted
    await p.setString(_keyTotalLength, totalRecords.toString());
    await p.setString(_keyMachineId, machineId);
    await p.setString(_keyUserCode, userCode);
  }

  Future<int> get downloadedRecordCount async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyDownloadedRecords) ?? 0;
  }

  /// Android offlineFlag: 0 = data present, 1 = cleared/ready for download.
  Future<int> get offlineFlag async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyOfflineFlag) ?? 1; // default 1 = cleared
  }

  Future<String> get machineId async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyMachineId) ?? '';
  }

  Future<String> get userCode async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyUserCode) ?? '';
  }

  /// Clear all offline data prefs (after sync + clear data).
  Future<void> clearOfflineData() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyOfflineFlag, 1); // 1 = cleared
    await p.setString(_keyTotalLength, '0');
    await p.setString(_keyMachineId, '0');
    await p.setInt(_keyDownloadedRecords, 0);
    await p.remove(_keyLastDownload);
  }
}
