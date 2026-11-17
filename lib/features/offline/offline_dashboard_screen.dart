import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import '../auth/login_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../search/search_customer_screen.dart';
import 'offline_reports_screen.dart';
import 'offline_unpaid_list_screen.dart';

/// Offline Dashboard — theme-aware restyle (AppThemeConst), kept lightweight
/// (static gradient + cards, no animations / network / Lottie) so it stays
/// crash-free and smooth in offline mode on both Android and iOS. All control
/// flow (back-to-online session logic, logout, navigation, refresh) is
/// unchanged from the original — only the presentation is themed.
class OfflineDashboardScreen extends StatefulWidget {
  const OfflineDashboardScreen({super.key});

  /// True while at least one Offline Dashboard is open (used by the
  /// background-timeout logout to know an offline user is "logged in").
  static bool get isOpen => _OfflineDashboardScreenState._openCount > 0;

  @override
  State<OfflineDashboardScreen> createState() => _OfflineDashboardScreenState();
}

class _OfflineDashboardScreenState extends State<OfflineDashboardScreen> {
  // Number of Offline Dashboards currently open. The offline-mode flag is on
  // while at least one is open and is cleared only when the last one closes,
  // so a late dispose of an old instance can't switch off a newer one.
  static int _openCount = 0;

  final _db = DatabaseHelper();
  int _totalCustomers = 0;
  int _paidCount = 0;
  int _syncedCount = 0;
  // True while [_exitOffline] is running — ignores repeated back presses.
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    // Every entry path (dashboard tile, drawer, offline login) is offline mode.
    _openCount++;
    OfflineModeService.instance.setOfflineMode(true);
    _refresh();
  }

  @override
  void dispose() {
    // Clear the offline flag when the LAST open Offline Dashboard closes
    // (back button, system back, logout or any other route removal).
    if (_openCount > 0) _openCount--;
    if (_openCount == 0) OfflineModeService.instance.setOfflineMode(false);
    super.dispose();
  }

  Future<void> _refresh() async {
    final total = await _db.getOfflineCustomerCount();
    final paid = await _db.getOfflinePaidCount();
    final synced = await _db.getOfflineSyncedCount();
    if (mounted) {
      setState(() {
        _totalCustomers = total;
        _paidCount = paid;
        _syncedCount = synced;
      });
    }
  }

  /// Exit flow for the app-bar "Back to online" button (B7).
  ///
  /// Android parity: Offline_Activity.java:96-121 (toolbar logo) and
  /// :262-290 (alertForNavigation). Nothing is synced here, so nothing blocks.
  ///  • No network → stay here and reload the counts (Android re-opens
  ///    Offline_Dashboard; no message).
  ///  • No session (entered offline via the login gate, offlin="0") →
  ///    the online dashboard has no authToken/dealerId, so Android sends
  ///    the user back to LoginActivity to re-authenticate. We do the same
  ///    — and we do NOT sync (no machine id/session to sync with).
  ///  • Valid session (entered from the online dashboard, offlin="1") →
  ///    "Choose one!" dialog (cancellable). "Online Dashboard" opens the
  ///    online dashboard at once; it sends pending offline payments in the
  ///    background (DashboardScreen._autoSyncOfflinePayments, B-B1 = Android
  ///    MainActivity.onCreate → synvkkm). "Offline Dashboard" reloads this
  ///    screen; Back / outside tap just closes the dialog.
  Future<void> _exitOffline() async {
    if (_exiting) return;
    _exiting = true;
    try {
      final conn = await Connectivity().checkConnectivity();
      if (!mounted) return;
      if (conn.contains(ConnectivityResult.none)) {
        _exiting = false;
        await _refresh();
        return;
      }
      if (!SessionService.instance.isLoggedIn) {
        await OfflineModeService.instance.setOfflineMode(false);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }
      final toOnline = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Choose one!'),
          content: const Text('Where do you want to proceed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Offline Dashboard'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Online Dashboard'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (toOnline != true) {
        _exiting = false;
        if (toOnline == false) await _refresh();
        return;
      }
      await OfflineModeService.instance.setOfflineMode(false);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    } catch (error, stackTrace) {
      // Unexpected failure before navigating: allow another back press.
      _exiting = false;
      ErrorHandlerService.recordError(
        error,
        stackTrace,
        reason: 'OfflineDashboard._exitOffline',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        title: const Text(
          'OFFLINE DASHBOARD',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.wifi_off),
          tooltip: 'Back to online',
          onPressed: _exitOffline,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              OfflineModeService.instance.setOfflineMode(false);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(t),
              const SizedBox(height: 18),
              _statCard(t),
              const SizedBox(height: 18),
              _actionCard(
                t,
                icon: Icons.search_rounded,
                tint: const Color(0xFFF9A825),
                title: 'Search Customer',
                subtitle: 'Find a customer to collect payment',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchCustomerScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _actionCard(
                t,
                icon: Icons.bar_chart_rounded,
                tint: const Color(0xFFD32F2F),
                title: 'Reports',
                subtitle: 'Offline collections & miniday',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfflineReportsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              // Android parity: the offline dashboard has exactly THREE entries —
              // search customer, reports, and the Payments Collected card
              // (offline_dashboard.xml :84 / :124 / :145). The unpaid list is
              // reached ONLY through that card (Offline_Dashboard.java :160 and
              // :171, both -> Offline_Tabs_Fragment). A separate "Unpaid
              // Customers" tile existed here from commit 389da11 but has no
              // Android counterpart, so it has been removed.
              _paymentsCollectedCard(t),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gradient header (logo + offline context) ────────────────────────────
  Widget _header(AppThemeConst t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: t.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: t.headerGradient.first.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.asset(
              AppConfig.instance.flavor == Flavor.magik
                  ? 'assets/mainlogo.png'
                  : 'assets/ezy_digi_pics.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Offline Dashboard',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('Working offline — data is saved on this device',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary stats (Total / Paid-pending / Synced) ───────────────────────
  Widget _statCard(AppThemeConst t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          _stat(t, '$_totalCustomers', 'Total', t.accent),
          _statDivider(t),
          _stat(t, '$_paidCount', 'Paid · pending', const Color(0xFFEF6C00)),
          _statDivider(t),
          _stat(t, '$_syncedCount', 'Synced', const Color(0xFF2E7D32)),
        ],
      ),
    );
  }

  Widget _stat(AppThemeConst t, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: t.cardSubtitleText)),
        ],
      ),
    );
  }

  Widget _statDivider(AppThemeConst t) =>
      Container(width: 1, height: 34, color: t.dividerColor);

  // ── Premium action card (same style as Offline Reports) ─────────────────
  Widget _actionCard(
    AppThemeConst t, {
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tint, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: t.cardHeadingText)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: t.cardSubtitleText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.cardSubtitleText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Offline payments-collected CTA (same target as Unpaid, kept for
  //    Android parity) ─────────────────────────────────────────────────────
  Widget _paymentsCollectedCard(AppThemeConst t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payments Collected (Offline Mode)',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: t.cardHeadingText)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'View all un-paid customers to collect payments offline.',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: t.cardSubtitleText),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfflineUnpaidListScreen(),
                    ),
                  );
                  _refresh();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('VIEW',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
