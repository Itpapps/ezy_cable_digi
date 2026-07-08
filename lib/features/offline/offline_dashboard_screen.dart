import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/offline_sync_service.dart';
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

  @override
  State<OfflineDashboardScreen> createState() => _OfflineDashboardScreenState();
}

class _OfflineDashboardScreenState extends State<OfflineDashboardScreen> {
  final _db = DatabaseHelper();
  int _totalCustomers = 0;
  int _paidCount = 0;
  int _syncedCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
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
          onPressed: () async {
            // Android parity (Offline_Activity.java:101-114): how we exit offline
            // depends on whether there is an active online session.
            //  • No session (entered offline via the login gate, offlin="0") →
            //    the online dashboard has no authToken/dealerId, so Android sends
            //    the user back to LoginActivity to re-authenticate. We do the same
            //    — and we do NOT sync (no machine id/session to sync with).
            //  • Valid session (entered from the online dashboard, offlin="1") →
            //    sync pending payments, then return to the online dashboard.
            if (!SessionService.instance.isLoggedIn) {
              await OfflineModeService.instance.setOfflineMode(false);
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
              return;
            }
            final n = await OfflineSyncService.instance.syncPendingToServer();
            await OfflineModeService.instance.setOfflineMode(false);
            if (!context.mounted) return;
            if (n > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Synced $n record(s)')),
              );
            }
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (_) => false,
            );
          },
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
              const SizedBox(height: 14),
              _actionCard(
                t,
                icon: Icons.people_alt_rounded,
                tint: const Color(0xFF1565C0),
                title: 'Unpaid Customers',
                subtitle: 'View all un-paid customers',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfflineUnpaidListScreen(),
                    ),
                  );
                  _refresh();
                },
              ),
              const SizedBox(height: 18),
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
