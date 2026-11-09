import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/widgets/premium_dialog.dart';

class DownloadRecordsScreen extends StatefulWidget {
  const DownloadRecordsScreen({super.key});

  @override
  State<DownloadRecordsScreen> createState() => _DownloadRecordsScreenState();
}

class _DownloadRecordsScreenState extends State<DownloadRecordsScreen> {
  final _db = DatabaseHelper();
  int _totalRecords = 0;
  int _paymentsToday = 0;
  int _pendingToSync = 0;
  int _totalSynced = 0;
  bool _loading = true;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final count = await _db.getOfflineCustomerCount();
    final paid = await _db.getOfflinePaidCount();
    final synced = await _db.getOfflineSyncedCount();
    if (mounted) {
      setState(() {
        _totalRecords = count;
        _paymentsToday = paid + synced;
        _pendingToSync = paid;
        _totalSynced = synced;
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      await OfflineDataService.instance.guardBeforeDownload();
      final flag = await OfflineModeService.instance.offlineFlag;
      if (flag == 0) {
        if (!mounted) return;
        showPremiumSnackBar(
          context,
          'Data already downloaded. Clear data first to download again.',
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      showPremiumSnackBar(context, 'Getting count...');
      final count = await OfflineDataService.instance.downloadGetCount();
      if (!mounted) return;
      showPremiumSnackBar(context, 'Downloading $count records...');
      final inserted =
          await OfflineDataService.instance.downloadRecords(count);
      if (!mounted) return;
      showPremiumSnackBar(
        context, 'Downloaded $inserted records successfully',
        isSuccess: true,
      );
      await _refresh();
    } on OfflineDataException catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Download failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _sync() async {
    try {
      final n = await OfflineSyncService.instance.syncPendingToServer();
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        n > 0
            ? 'Synced $n record(s)'
            // Android SyncData_Fragment text (also used by Sync/Clear).
            : 'No payments has been made (or) Check your internet connection.',
        isSuccess: n > 0,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Sync failed: $e', isError: true);
    }
  }

  Future<void> _clearData() async {
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Clear All Data',
      body:
          'This will remove all offline customers and payments from this device.\n\nDownload again to continue working offline.',
      confirmLabel: 'Clear',
      cancelLabel: 'Cancel',
      isDanger: true,
    );
    if (ok != true) return;

    try {
      await OfflineDataService.instance.clearAllData();
      if (!mounted) return;
      showPremiumSnackBar(
        context, 'All offline data cleared', isSuccess: true,
      );
      await _refresh();
    } on OfflineDataException catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Clear failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final statValueColor = t.isLight
        ? AppColors.primary
        : const Color(0xFF26C6DA);
    final statCardBg = t.isLight
        ? Colors.white
        : Colors.white.withValues(alpha: 0.08);
    final statCardBorder = t.isLight
        ? AppColors.border
        : Colors.white.withValues(alpha: 0.12);
    final statIconBg = t.isLight
        ? const Color(0xFFE3EDFF)
        : const Color(0xFF1565C0).withValues(alpha: 0.35);
    final statIconColor = t.isLight
        ? AppColors.primary
        : const Color(0xFF26C6DA);

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
          'DOWNLOAD RECORDS',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.1, color: t.appBarFg),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.loadingColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Download Card ──
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: t.headerGradient,
                      ),
                      borderRadius: BorderRadius.circular(AppSizes.radiusL),
                      boxShadow: [
                        BoxShadow(
                          color: t.headerGradient.first.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isDownloading ? null : _download,
                        borderRadius: BorderRadius.circular(AppSizes.radiusL),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                          child: Column(
                            children: [
                              _isDownloading
                                  ? const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.20),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(Icons.download_rounded,
                                          color: Colors.white, size: 32),
                                    ),
                              const SizedBox(height: 14),
                              const Text(
                                'Download New Records',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sync latest data with the server.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.80),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppSizes.radiusXL),
                                ),
                                child: Text(
                                  _isDownloading ? 'Downloading...' : 'Start Download',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: t.headerGradient.first,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Data Summary Header ──
                  Row(
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 20, color: t.headingText),
                      const SizedBox(width: 8),
                      Text(
                        'Data Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.headingText,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Stat Cards Row 1 ──
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.description_outlined,
                          label: 'Total Records',
                          value: '$_totalRecords',
                          valueFontSize: 24,
                          cardBg: statCardBg,
                          borderColor: statCardBorder,
                          iconBg: statIconBg,
                          iconColor: statIconColor,
                          valueColor: statValueColor,
                          labelColor: t.isLight
                              ? AppColors.textSecondary
                              : Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.currency_rupee_rounded,
                          label: "Today's Payments",
                          value: '$_paymentsToday',
                          valueFontSize: 24,
                          cardBg: statCardBg,
                          borderColor: statCardBorder,
                          iconBg: statIconBg,
                          iconColor: statIconColor,
                          valueColor: statValueColor,
                          labelColor: t.isLight
                              ? AppColors.textSecondary
                              : Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Stat Cards Row 2 ──
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.sync_rounded,
                          label: 'Pending Sync\n(Payments)',
                          value: '$_pendingToSync',
                          valueFontSize: 24,
                          cardBg: statCardBg,
                          borderColor: statCardBorder,
                          iconBg: statIconBg,
                          iconColor: statIconColor,
                          valueColor: statValueColor,
                          labelColor: t.isLight
                              ? AppColors.textSecondary
                              : Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.playlist_add_check_rounded,
                          label: 'Total Payments /\nSynced',
                          value: '$_paymentsToday/$_totalSynced',
                          valueFontSize: 22,
                          cardBg: statCardBg,
                          borderColor: statCardBorder,
                          iconBg: statIconBg,
                          iconColor: statIconColor,
                          valueColor: statValueColor,
                          labelColor: t.isLight
                              ? AppColors.textSecondary
                              : Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Divider(color: t.dividerColor, height: 1),

                  const SizedBox(height: 16),

                  // ── Sync + Clear Row ──
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _sync,
                            icon: Icon(Icons.sync_rounded, color: statIconColor),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: statIconColor,
                              side: BorderSide(color: statIconColor.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                              ),
                            ),
                            label: Text(
                              'Sync Data',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: t.headingText,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _clearData,
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: Color(0xFFEF4444)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: BorderSide(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                              ),
                            ),
                            label: Text(
                              'Clear Data',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: t.isLight
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFFF6B6B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double valueFontSize;
  final Color cardBg;
  final Color borderColor;
  final Color iconBg;
  final Color iconColor;
  final Color valueColor;
  final Color labelColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueFontSize,
    required this.cardBg,
    required this.borderColor,
    required this.iconBg,
    required this.iconColor,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusS),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
