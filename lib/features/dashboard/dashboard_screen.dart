import 'package:ezy_cable_digi/bluetooth/bluetooth_devices_screen.dart';
import 'package:ezy_cable_digi/features/event/event_management_screen.dart';
import 'package:ezy_cable_digi/features/offline/offline_dashboard_screen.dart';
import 'package:ezy_cable_digi/features/offline/download_records_screen.dart';
import 'package:ezy_cable_digi/features/reports/mini_day_report_screen.dart';
import 'package:ezy_cable_digi/features/reports/monthly_report_screen.dart';
import 'package:ezy_cable_digi/features/scan/scan_customer_screen.dart';
import 'package:ezy_cable_digi/features/search/search_customer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/data/customer.dart';
import '../payment/payment_options_screen.dart';
import '../complaints/complaints_screen.dart';
import '../complaints/complaint_details_screen.dart';
import '../analytics/analytics_screen.dart';
import '../expenses/add_expenses_screen.dart';
import '../offline/static_content_screen.dart';
import '../notifications/data/notification_repository.dart';
import '../notifications/login_notification_dialog.dart';
import '../../core/services/session_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../../core/services/location_sync_service.dart';
import '../../main.dart';
import '../auth/login_screen.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../customers/customer_list_screen.dart';
import '../../features/settings/printer_settings_screen.dart';
import 'dashboard_controller.dart';
import 'dashboard_refresh_signal.dart';
import 'data/nearest_repository.dart';
import '../collections/data/pay_later.dart';
import '../../core/config/app_config.dart';

enum _FeedType { complaints, unpaid, nearest, payLater }

enum _TicketStatus { assigned, inprocess }

class _TicketItem {
  final String ticketId;
  final String name;
  final String description;
  final String customerId;
  final _TicketStatus status;
  final String? statusLabel; // real status text (complaints); null → use enum
  final String
  altCustomerId; // alt_cust_id from OpenComplaint (complaints feed)
  final String
  realComplaintId; // complaint_id from OpenComplaint (complaints feed)

  const _TicketItem({
    required this.ticketId,
    required this.name,
    required this.description,
    required this.customerId,
    required this.status,
    this.statusLabel,
    this.altCustomerId = '',
    this.realComplaintId = '',
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> with RouteAware {
  Widget _getScreen() {
    if (_selectedTab == 1) return const ComplaintsScreen();
    if (_selectedTab == 2) return const AnalyticsScreen();
    if (_selectedTab == 3) {
      return AddExpensesScreen(
        isTab: true,
        onSuccess: () => setState(() => _selectedTab = 0),
      );
    }
    if (_selectedTab == 4) {
      return const StaticContentScreen(
        title: 'About Us',
        body: kDummyAboutUs,
        hideAppBar: true,
      );
    }
    return const SizedBox();
  }

  void setTab(int index) {
    if (mounted) {
      setState(() {
        _selectedTab = index;
      });
    }
  }

  int _selectedTab = 0;
  bool _statsCollapsed = false;
  _FeedType _feed = _FeedType.complaints;

  // Client-side "Load more" — the APIs return the full list (no server paging,
  // same as Android); we just cap how many cards are BUILT to keep the feed
  // fast (shrinkWrap lists build every item). Resets to 30 on feed switch.
  static const int _feedPage = 30;
  int _feedShown = _feedPage;

  /// Wraps a feed list with a display cap + a "Load more" footer.
  /// [cap] — Android hard-caps some dashboard feeds (unpaid + complaints at 10,
  /// `getItemCount → size>9?10:size`) with NO Load More. When set, show
  /// `min(total, cap)` and no footer. Uncapped feeds keep the 30 + Load More.
  Widget _pagedListView({
    required int total,
    required IndexedWidgetBuilder itemBuilder,
    int? cap,
  }) {
    final limit = cap ?? _feedShown;
    final shown = total <= limit ? total : limit;
    final hasMore = cap == null && total > shown;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown + (hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (hasMore && i == shown) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _feedShown += _feedPage),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Load more (${total - shown} more)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          );
        }
        return itemBuilder(ctx, i);
      },
    );
  }

  // KPI cards (Section 1: dashBoardDetails). Defensive — never crashes the screen.
  final DashboardController _dash = DashboardController();
  void _onDash() {
    if (mounted) setState(() {});
  }

  // Android parity (DashboardHomeFragment.java:1364-1386, 1541-1558):
  // on KPI failure, show a dialog and redirect to LoginScreen.
  void _handleKpiResult() {
    if (!mounted || !_dash.hasError) return;
    final code = _dash.kpiStatusCode;
    if (code == 1) {
      _showKpiErrorDialog(
        title: 'No Details Found!',
        message: _dash.errorMessage ?? 'No Details Found',
      );
    } else if (code == 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_dash.errorMessage ?? 'Error'}: Contact Support',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      _showKpiErrorDialog(
        title: 'Server is busy or Un reachable!',
        message: 'Please login again after sometime',
      );
    }
  }

  void _showKpiErrorDialog({required String title, required String message}) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // DUMMY login-notification popup — one-shot guard so it shows only once.
  bool _notificationShown = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    LocationSyncService.instance.onScreenOpened(TrackingScreen.dashboard);
    _dash.addListener(_onDash);
    _dash.loadKpis().then((_) => _handleKpiResult());
    _dash
        .loadWallet(); // Android: lcowallet() on dashboard create (DEALER/ADMIN)
    _dash.loadComplaints(); // Complaints is the default feed tab.
    // DUMMY login notification popup (demo only). Comment out this line to
    // disable it until the real API is ready.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLoginNotification(),
    );
  }

  // DUMMY login notification popup — runs once after the first frame, over the
  // painted dashboard. To go live later, only NotificationRepository
  // .fetchLoginNotification()'s body changes (dummy → API); this stays the same.
  Future<void> _showLoginNotification() async {
    if (_notificationShown || !mounted) return;
    _notificationShown = true;
    // ALL notifications in ONE scrollable popup (not multiple popups).
    final list = await NotificationRepository.instance
        .fetchLoginNotifications();
    if (list.isEmpty || !mounted) return;
    await showPremiumDialog<void>(
      context: context,
      barrierDismissible: false,
      child: LoginNotificationDialog(notifications: list),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    LocationSyncService.instance.stopDashboardTracking();
    _dash.removeListener(_onDash);
    _dash.dispose();
    super.dispose();
  }

  @override
  void didPushNext() =>
      LocationSyncService.instance.onScreenOpened(TrackingScreen.other);

  @override
  void didPopNext() {
    LocationSyncService.instance.onScreenOpened(TrackingScreen.dashboard);
    // Force a one-shot KPI refresh if a collection action (e.g. a payment)
    // changed the totals while we were away — Android parity. Nothing reloads
    // when the flag is unset (returning from read-only screens).
    if (DashboardRefreshSignal.instance.consumeKpiDirty()) {
      _dash.loadKpis().then((_) => _handleKpiResult());
      _dash.loadWallet(); // Android refreshes the wallet on every recreate too
      // Android's changeFragment(replace) RECREATES the dashboard on return, so
      // onCreateView re-runs: KPIs + wallet + COMPLAINTS reload and the tab resets
      // to the default (Complaints); getunpaiddata stays lazy
      // (DashboardHomeFragment onCreateView :264-266). Mirror that so the Unpaid
      // feed can't show stale (already-paid) rows — re-tapping Unpaid then
      // force-refetches a fresh list.
      if (mounted) {
        setState(() {
          _feed = _FeedType.complaints;
          _feedShown = _feedPage;
        });
      }
      _dash.loadComplaints(force: true);
    }
  }

  // ── Build ──────
  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    // Back on a sub-tab returns to the Dashboard tab; back on the Dashboard tab
    // shows Android's "Close Application?" confirm before exiting the app
    // (DashboardHomeFragment OnBackPressedCallback:172-209 parity).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_selectedTab != 0) {
          setState(() => _selectedTab = 0);
          return;
        }
        // Android parity: "Yes" → EXIT=true → the app closes (LoginActivity
        // finishes the cleared task); "No" → stay.
        final leave = await showPremiumConfirm(
          context: context,
          title: 'Close Application?',
          body: 'Are you sure you want to logout? \n Click \'Yes\' to Logout!',
          confirmLabel: 'Yes',
          cancelLabel: 'No',
        );
        if (leave) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: _PremiumAppBar(),
        ),
        bottomNavigationBar: BottomNavBar(
          currentIndex: _selectedTab,
          onChanged: (i) => setState(() => _selectedTab = i),
        ),
        body: _selectedTab == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Fixed-blue hero: business header + KPI + Quick Actions.
                  //    Full-bleed blue in BOTH themes (3-B2 will NOT touch this).
                  Container(
                    color: t.scaffoldBg,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── itp label ─────────────────────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  SessionService
                                          .instance
                                          .businessName
                                          .isNotEmpty
                                      ? SessionService.instance.businessName
                                      : 'itp',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.headingText,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(
                                  () => _statsCollapsed = !_statsCollapsed,
                                ),
                                icon: Icon(
                                  _statsCollapsed
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                  color: t.headingText,
                                ),
                                tooltip: _statsCollapsed
                                    ? 'Show summary'
                                    : 'Hide summary',
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          // Collapsible gradient stat cards (Row 1 + Row 2).
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            alignment: Alignment.topCenter,
                            child: _statsCollapsed
                                ? SingleChildScrollView(
                                    // Compact summary when collapsed — a horizontally
                                    // scrollable ticker (swipe if it overflows), so
                                    // big amounts stay full-size. Read-only.
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        for (final chip
                                            in <(String, String, Color)>[
                                              (
                                                'Due',
                                                _dash.dueAmountText,
                                                const Color(0xFFEF4444),
                                              ),
                                              (
                                                'Bill',
                                                _dash.monthBillingText,
                                                const Color(0xFFF97316),
                                              ),
                                              (
                                                'Onetime',
                                                _dash.onetimeChargesText,
                                                const Color(0xFF26C6DA),
                                              ),
                                              if (_dash.showLcoWallet)
                                                (
                                                  'Wallet',
                                                  _dash.lcoWalletText,
                                                  const Color(0xFF22C55E),
                                                ),
                                              (
                                                'Coll',
                                                _dash.collectionsText,
                                                const Color(0xFF8B5CF6),
                                              ),
                                            ])
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 14,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: chip.$3,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  '${chip.$1}: ${chip.$2}',
                                                  style: TextStyle(
                                                    color: t.headingText,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 9),

                                      // ── Row 1: 3 Gradient Summary Cards ───────────────────────────
                                      // Due Amount  → deep blue-to-sky
                                      // Month Billing → rose-to-pink
                                      // Onetime Ch…  → amber-to-orange
                                      IntrinsicHeight(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _GradientSummaryCard(
                                                title: 'Due Amount',
                                                amount: _dash.dueAmountText,
                                                subtitle: '',
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFB91C1C),
                                                    Color(0xFFEF4444),
                                                    Color(0xFFFB7185),
                                                  ],
                                                  stops: [0.0, 0.55, 1.0],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                icon: Iconsax.receipt_item,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _GradientSummaryCard(
                                                title: 'Month Billing',
                                                amount: _dash.monthBillingText,
                                                subtitle: 'This month',
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFEA580C),
                                                    Color(0xFFF97316),
                                                    Color(0xFFFBBF24),
                                                  ],
                                                  stops: [0.0, 0.5, 1.0],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                icon: Iconsax.calendar_tick,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _GradientSummaryCard(
                                                title: 'Onetime Ch...',
                                                amount:
                                                    _dash.onetimeChargesText,
                                                subtitle: 'Installations',
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF0277BD),
                                                    Color(0xFF0288D1),
                                                    Color(0xFF26C6DA),
                                                  ],
                                                  stops: [0.0, 0.45, 1.0],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                icon: Iconsax.flash_circle,
                                                useDarkText: false,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 10),

                                      // ── Row 2: LCO Wallet + Collections ───────────────────────────
                                      // LCO Wallet  → green-to-cyan  (existing — premium mixing)
                                      // Collections → purple-to-violet matching the same diagonal style
                                      IntrinsicHeight(
                                        child: Row(
                                          children: [
                                            // LCO Wallet — Android shows this card only when
                                            // useLcoDeposit==1 (ll_lcowallet visibility); else hidden
                                            // and Collections spans full width.
                                            if (_dash.showLcoWallet) ...[
                                              Expanded(
                                                child: _LottieHighlightCard(
                                                  title: 'LCO Wallet',
                                                  amount: _dash.lcoWalletText,
                                                  subtitle: 'Available',
                                                  gradient:
                                                      const LinearGradient(
                                                        colors: [
                                                          Color(0xFF22C55E),
                                                          Color(0xFF0EA5E9),
                                                        ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      ),
                                                  lottieAsset:
                                                      'assets/Wallet Animation.json',
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            Expanded(
                                              child: _LottieHighlightCard(
                                                title: 'Collections',
                                                amount: _dash.collectionsText,
                                                subtitle: 'Today',
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFEC4899),
                                                    Color(0xFF8B5CF6),
                                                    Color(0xFF4F46E5),
                                                  ],
                                                  stops: [0.0, 0.5, 1.0],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                lottieAsset:
                                                    'assets/Growth Chart.json',
                                                // Android parity: Collections card tap opens the
                                                // Employee Collection report (Report_EmpCollect →
                                                // MonthlyReportScreen), same target as the Monthly
                                                // Report quick-action and Reports Home tile.
                                                onTap: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const MonthlyReportScreen(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),

                          const SizedBox(height: 10),

                          // ── Row 3: Quick Actions — horizontal scroll ───────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF3FF),
                              borderRadius: BorderRadius.circular(18),
                              // Premium Light: a hairline border + slightly
                              // stronger shadow so the pale card separates from
                              // the light body. Theme 1 (blue bg) unchanged.
                              border: t.isLight
                                  ? Border.all(color: t.inputBorderColor)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: t.isLight ? 16 : 12,
                                  spreadRadius: t.isLight ? 1 : 0,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 6,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _QuickActionTile(
                                    icon: Iconsax.user_tag,
                                    label: 'Customer List',
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const CustomerListScreen(),
                                      ),
                                    ),
                                  ),
                                  _QuickActionTile(
                                    icon: Iconsax.document_download,
                                    label: 'Download Data',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const DownloadRecordsScreen(),
                                      ),
                                    ),
                                  ),
                                  _QuickActionTile(
                                    icon: Iconsax.search_status,
                                    label: 'Offline Search',
                                    onTap: () async {
                                      if (!await offlineDataMatchesDealer()) {
                                        if (!context.mounted) return;
                                        await showIdMismatch(context);
                                        return;
                                      }
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const OfflineDashboardScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _QuickActionTile(
                                    icon: Iconsax.calendar_1,
                                    label: 'Miniday Report',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const MiniDayReportScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _QuickActionTile(
                                    icon: Iconsax.chart_2,
                                    label: 'Monthly Report',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const MonthlyReportScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _QuickActionTile(
                                    icon: Iconsax.setting_2,
                                    label: 'Settings',
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const PrinterSettingsScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ], // close hero inner Column children (A,B,C,D)
                      ), // close hero inner Column
                    ), // close hero Padding
                  ), // close hero Container
                  // ── Blue feed backdrop — the ONLY thing 3-B2 will re-theme.
                  //    3-B1: still AppColors.primary → no visual change.
                  Expanded(
                    child: Container(
                      color: t.scaffoldBg,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                        child: _buildFeedSection(),
                      ),
                    ),
                  ),
                ], // close outer Column children
              ) // close outer Column
            : _getScreen(),
      ),
    );
  }

  // The white feed card (filter chips + divider + the selected feed list),
  // extracted verbatim from the dashboard body — behaviour is UNCHANGED. Step 2
  // will place this inside an Expanded so only the feed scrolls under a fixed
  // header (the KPI cards + quick actions), matching Android's dashboard.
  /// True while the CURRENTLY SELECTED feed is re-fetching after its first
  /// successful load — i.e. a refresh, not the initial load.
  ///
  /// Read-only: derived purely from the loading/loaded flags the controller
  /// already maintains and already broadcasts via notifyListeners(). It adds no
  /// state, and deliberately ignores loadKpis()/loadWallet() — those run
  /// concurrently but render in the cards above this one, so letting them drive
  /// this bar would point it at content it does not describe.
  ///
  /// The `loaded` half is what preserves the first-load experience: on the very
  /// first fetch `loaded` is false, so this stays false and _FeedSkeleton owns
  /// the feedback exactly as before.
  bool get _selectedFeedRefreshing {
    switch (_feed) {
      case _FeedType.complaints:
        return _dash.complaintsLoading && _dash.complaintsLoaded;
      case _FeedType.unpaid:
        return _dash.unpaidLoading && _dash.unpaidLoaded;
      case _FeedType.nearest:
        return _dash.nearestLoading && _dash.nearestLoaded;
      case _FeedType.payLater:
        return _dash.payLaterLoading && _dash.payLaterLoaded;
    }
  }

  Widget _buildFeedSection() {
    return Container(
      width: double.infinity,
      // Clip the scrolling feed to the rounded shape so cards never paint past
      // the card's rounded corners (esp. the bottom corners / landscape). The
      // shadow is drawn by the decoration behind the clip, so it stays intact.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _FeedChip(
                    label: 'Complaints',
                    selected: _feed == _FeedType.complaints,
                    onTap: () {
                      setState(() {
                        _feed = _FeedType.complaints;
                        _feedShown = _feedPage;
                      });
                      _dash.loadComplaints(force: true);
                    },
                  ),
                  const SizedBox(width: 8),
                  _FeedChip(
                    label: 'Unpaid',
                    selected: _feed == _FeedType.unpaid,
                    onTap: () {
                      setState(() {
                        _feed = _FeedType.unpaid;
                        _feedShown = _feedPage;
                      });
                      // Dashboard-owned fetch (force = fresh each tap, like the
                      // Complaints tab). Decoupled from CustomerListProvider so
                      // the Customer List screen's filters never bleed in.
                      _dash.loadUnpaid(force: true);
                    },
                  ),
                  const SizedBox(width: 8),
                  _FeedChip(
                    label: 'Nearest',
                    selected: _feed == _FeedType.nearest,
                    onTap: () {
                      setState(() {
                        _feed = _FeedType.nearest;
                        _feedShown = _feedPage;
                      });
                      _dash.loadNearest(force: true);
                    },
                  ),
                  const SizedBox(width: 8),
                  _FeedChip(
                    label: 'PayLater',
                    selected: _feed == _FeedType.payLater,
                    onTap: () {
                      setState(() {
                        _feed = _FeedType.payLater;
                        _feedShown = _feedPage;
                      });
                      _dash.loadPayLater(force: true);
                    },
                  ),
                ],
              ),
            ),
          ),
          // Refresh feedback. The divider slot is reused so the layout height is
          // IDENTICAL in both states (1px) — the list never moves. Driven only by
          // the SELECTED feed's own loading flag, so KPI/wallet requests (which
          // run concurrently and render in the cards above) can never show or
          // hide it. Shown for refreshes only; first load still gets the
          // existing _FeedSkeleton, which is untouched.
          SizedBox(
            height: 1,
            child: _selectedFeedRefreshing
                ? LinearProgressIndicator(
                    minHeight: 1, // default is 4.0 — would shift the list by 3px
                    backgroundColor: AppThemeConst.of(context).dividerColor,
                    color: AppThemeConst.of(context).accent,
                    semanticsLabel: 'Refreshing',
                  )
                : const Divider(
                    height: 1, thickness: 0.6, indent: 12, endIndent: 12),
          ),
          // The feed fills the remaining card height and is the ONLY thing that
          // scrolls (the tab chips above stay fixed). LayoutBuilder + a viewport
          // min-height keeps the empty/error messages vertically CENTERED (restored)
          // while still scrolling when the list is tall — and nothing overflows the
          // bounded slot. Replaces the old MediaQuery min-height.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    child: _feed == _FeedType.unpaid
                        ? _buildUnpaidFeed()
                        : _feed == _FeedType.complaints
                        ? _buildComplaintsFeed()
                        : _feed == _FeedType.payLater
                        ? _buildPayLaterFeed()
                        : _buildNearestFeed(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Unpaid feed (real `unpaidCustomers` via DashboardController.loadUnpaid) ──
  // Defensive: loading / error / empty states; never crashes. One feed failing
  // does not affect the KPI cards or the other tabs.
  Widget _buildUnpaidFeed() {
    if (_dash.unpaidLoading && !_dash.unpaidLoaded) {
      return const _FeedSkeleton();
    }
    if (_dash.unpaidError) {
      return _feedMessage(
        Iconsax.warning_2,
        _dash.unpaidMessage.isEmpty
            ? 'Could not load unpaid customers'
            : _dash.unpaidMessage,
        onRetry: () => _dash.loadUnpaid(force: true),
      );
    }
    final list = _dash.unpaidCustomers;
    if (list.isEmpty) {
      return _feedMessage(Iconsax.tick_circle, 'No unpaid customers');
    }
    return _pagedListView(
      total: list.length,
      cap: 10, // Android UnpaidNewAdapter caps the dashboard preview at 10.
      itemBuilder: (_, i) =>
          _UnpaidCard(customer: list[i], isLast: i == list.length - 1),
    );
  }

  // ── Complaints feed (real `getopencomplaintslist` via DashboardController) ──
  // Reuses _TicketCard (status badge + Update Status → ComplaintDetailsScreen),
  // which fits a complaint. Defensive: loading / error / empty; never crashes.
  Widget _buildComplaintsFeed() {
    if (_dash.complaintsLoading && !_dash.complaintsLoaded) {
      return const _FeedSkeleton();
    }
    if (_dash.complaintsError) {
      return _feedMessage(
        Iconsax.warning_2,
        _dash.complaintsMessage.isEmpty
            ? 'Could not load complaints'
            : _dash.complaintsMessage,
        onRetry: () => _dash.loadComplaints(force: true),
      );
    }
    final list = _dash.complaints;
    if (list.isEmpty) {
      return _feedMessage(Iconsax.tick_circle, 'No complaints');
    }
    return _pagedListView(
      total: list.length,
      cap:
          10, // Android OpenComplaints adapter caps the dashboard preview at 10.
      itemBuilder: (_, i) {
        final c = list[i];
        final desc = c.description.isEmpty ? c.des : c.description;
        final item = _TicketItem(
          ticketId: c.tktNumber.isEmpty ? c.complaintId : c.tktNumber,
          name: c.name.isEmpty ? 'NA' : c.name,
          description: 'Description : $desc',
          // "LCO Customer ID" = alt_custom_number, matching Android
          // OpenComplaints_RecyclerView_Adapter:57 (getAltCustomNumber()) — NOT
          // the internal customer_id, which is a different number.
          customerId: c.altCustomNumber,
          status: _mapComplaintStatus(c.status),
          statusLabel: c.status.isEmpty ? null : c.status,
          altCustomerId: c.altCustId,
          realComplaintId: c.complaintId,
        );
        return _TicketCard(
          item: item,
          isLast: i == list.length - 1,
          onRefresh: () {
            _dash.loadComplaints(force: true);
            setState(() {});
          },
        );
      },
    );
  }

  _TicketStatus _mapComplaintStatus(String status) {
    final s = status.toUpperCase();
    if (s.contains('PROCESS') || s.contains('PROGRESS')) {
      return _TicketStatus.inprocess;
    }
    return _TicketStatus.assigned;
  }

  // ── Pay Later feed (real scheduled_collection_data via DashboardController) ─
  Widget _buildPayLaterFeed() {
    if (_dash.payLaterLoading && !_dash.payLaterLoaded) {
      return const _FeedSkeleton();
    }
    if (_dash.payLaterError) {
      return _feedMessage(
        Iconsax.warning_2,
        _dash.payLaterMessage.isEmpty
            ? 'Could not load pay later'
            : _dash.payLaterMessage,
        onRetry: () => _dash.loadPayLater(force: true),
      );
    }
    final list = _dash.payLaterItems;
    if (list.isEmpty) {
      return _feedMessage(Iconsax.tick_circle, 'No scheduled collections');
    }
    return _pagedListView(
      total: list.length,
      itemBuilder: (_, i) =>
          _PayLaterCard(item: list[i], isLast: i == list.length - 1),
    );
  }

  // ── Nearest feed (real NearestNextCustomer via DashboardController) ─────────
  Widget _buildNearestFeed() {
    if (_dash.nearestLoading && !_dash.nearestLoaded) {
      return const _FeedSkeleton();
    }
    if (_dash.nearestError) {
      return _feedMessage(
        Iconsax.warning_2,
        _dash.nearestMessage.isEmpty
            ? 'Could not load nearest customers'
            : _dash.nearestMessage,
        onRetry: () => _dash.loadNearest(force: true),
      );
    }
    final list = _dash.nearestItems;
    if (list.isEmpty) {
      return _feedMessage(Iconsax.location, 'No nearby customers found');
    }
    return _pagedListView(
      total: list.length,
      itemBuilder: (_, i) {
        final n = list[i];
        return _NearestCard(item: n, isLast: i == list.length - 1);
      },
    );
  }

  Widget _feedMessage(IconData icon, String text, {VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: Colors.black26, size: 34),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed skeleton — lightweight placeholder cards while a feed's API is loading.
// ─────────────────────────────────────────────────────────────────────────────
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) {
        return Container(
          height: 78,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF3FB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F5)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_bar(140, 12), const SizedBox(height: 10), _bar(90, 10)],
          ),
        );
      }),
    );
  }

  Widget _bar(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: const Color(0xFFD9E1F2),
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient Summary Card (Due Amount / Month Billing / Onetime Charges)
// [useDarkText] → true for light-coloured gradients (amber/yellow)
// ─────────────────────────────────────────────────────────────────────────────
class _GradientSummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final LinearGradient gradient;
  final IconData icon;
  final bool useDarkText;
  const _GradientSummaryCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    this.useDarkText = false,
  });
  @override
  Widget build(BuildContext context) {
    final Color base = useDarkText
        ? Colors.black.withValues(alpha: 0.75)
        : Colors.white;
    final Color muted = useDarkText
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.80);
    final Color dim = useDarkText
        ? Colors.black.withValues(alpha: 0.40)
        : Colors.white.withValues(alpha: 0.70);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 9, 6, 9),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: muted, size: 15),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: muted,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: base,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: dim,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lottie Highlight Card (LCO Wallet / Collections)
// ─────────────────────────────────────────────────────────────────────────────
class _LottieHighlightCard extends StatefulWidget {
  final String title;
  final String amount;
  final String subtitle;
  final LinearGradient gradient;
  final String lottieAsset;
  // Optional tap action (Android parity: the Collections card navigates to the
  // Employee Collection report). When null (e.g. LCO Wallet card) the card keeps
  // its original replay-only behaviour.
  final VoidCallback? onTap;

  const _LottieHighlightCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.gradient,
    required this.lottieAsset,
    this.onTap,
  });

  @override
  State<_LottieHighlightCard> createState() => _LottieHighlightCardState();
}

class _LottieHighlightCardState extends State<_LottieHighlightCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _replay() {
    _controller.reset();
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _replay();
        widget.onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: widget.gradient.colors.first.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Android parity: fixed box, truncate large amounts with "…"
                  // (ellipsis) instead of shrinking the text so it stays legible.
                  Text(
                    widget.amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 48,
              height: 48,
              child: Lottie.asset(
                widget.lottieAsset,
                controller: _controller,
                fit: BoxFit.contain,
                repeat: false,
                onLoaded: (composition) {
                  _controller.duration = composition.duration;
                  _controller.forward(); // play once on load
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action Tile
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Intrinsic width — no hard fixed width so text fits in one line
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          // Same premium frosted-light card as reference — white bg, soft shadow
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed Filter Chip
// ─────────────────────────────────────────────────────────────────────────────
class _FeedChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 13, color: AppColors.primary),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.primary : Colors.black54,
              ),
            ),
            if (!selected)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: Colors.black45,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ticket Card
// ─────────────────────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final _TicketItem item;
  final bool isLast;
  final VoidCallback? onRefresh; // called after a successful status update

  const _TicketCard({required this.item, required this.isLast, this.onRefresh});

  /// Maps the real backend status string to its display colour.
  /// Mirrors the Android app badge colours for each known status value.
  static Color _statusColor(String s) {
    final u = s.toUpperCase();
    if (u.contains('ASSIGN')) return const Color(0xFF1565C0); // blue
    if (u.contains('PROCESS') || u.contains('PROGRESS'))
      return const Color(0xFFF59E0B); // amber
    if (u.contains('HOLD')) return const Color(0xFFE53935); // red
    if (u.contains('RESOLV')) return const Color(0xFF43A047); // green
    if (u.contains('CLOS')) return const Color(0xFF757575); // grey
    return const Color(0xFF1565C0); // default → blue
  }

  @override
  Widget build(BuildContext context) {
    final isAssigned = item.status == _TicketStatus.assigned;
    final statusText =
        item.statusLabel ?? (isAssigned ? 'ASSIGNED' : 'INPROCESS');
    final statusColor = _statusColor(statusText);

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar with ticket ID + location icon
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.ticketId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    /* TODO: open map navigation */
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Iconsax.location,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Name : ${item.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        'Status : $statusText',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'LCO Customer ID : ${item.customerId}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // Full-width Update Status button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ComplaintDetailsScreen(
                            complaintId: item.ticketId,
                            customerName: item.name,
                            complaint: item.description,
                            currentStatus:
                                item.statusLabel ??
                                (item.status == _TicketStatus.assigned
                                    ? 'ASSIGNED'
                                    : 'INPROCESS'),
                            altCustomerId: item.altCustomerId,
                            realComplaintId: item.realComplaintId,
                          ),
                        ),
                      ).then((ok) {
                        if (ok == true) onRefresh?.call();
                      });
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    label: const Text('Update Status'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unpaid Customer Card — real `unpaidCustomers` row. Tap → customer details
// (same target as the Customer List screen). No complaint status / update button.
// ─────────────────────────────────────────────────────────────────────────────
class _UnpaidCard extends StatelessWidget {
  final Customer customer;
  final bool isLast;
  const _UnpaidCard({required this.customer, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final pending =
        customer.pendingAmount; // already '₹…' from Customer.fromJson
    final account = customer.altCustomerId.isEmpty
        ? 'NA'
        : customer.altCustomerId;
    // "LCO Customer ID" = Android alt_custom_number (customer-facing LCO id), NOT
    // lcoCustomerId (== customer_id, the internal operation key).
    final lcoId = customer.altCustomNumber.isEmpty
        ? 'NA'
        : customer.altCustomNumber;

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Android parity (UnpaidNewAdapter:103-179, hit_from==1): the
            // dashboard Unpaid row is a collection shortcut — tap opens Make
            // Payment directly, gated by the make_payment permission (SERVICE /
            // make_payment=="0" → "Access denied!"). It does NOT open Customer
            // Details. The Customer is the same object that already reached
            // payment via Details, so it is payment-compatible.
            if (!SessionService.instance.canMakePayment) {
              showPremiumConfirm(
                context: context,
                title: 'Access denied!',
                body: 'You have no access to do payments.',
                confirmLabel: 'OK',
                cancelLabel: 'Close',
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentOptionsScreen(customer: customer),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name.isEmpty ? 'NA' : customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: t.cardBodyText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        pending,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Account : $account',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.cardSubtitleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'LCO Customer ID : $lcoId',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.cardSubtitleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nearest Customer Card — real `NearestNextCustomer` row (parallel-array API).
// Shows name, alt_custom_number, and distance from the REST response.
// ─────────────────────────────────────────────────────────────────────────────
class _NearestCard extends StatelessWidget {
  final NearestCustomerItem item;
  final bool isLast;
  const _NearestCard({required this.item, required this.isLast});
  //google maps direction to the customer's lat/lang
  void _openDirections(BuildContext context) {
    if (item.latitude == 0 && item.longitude == 0) return;
    launchUrl(
      Uri.parse(
        'http://maps.google.com/maps?daddr=${item.latitude},${item.longitude}',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return GestureDetector(
      onTap: () => _openDirections(context),
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.30)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + Account
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name.isEmpty ? 'NA' : item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: t.cardBodyText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.altCustomNumber.isEmpty
                          ? 'NA'
                          : item.altCustomNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: t.cardSubtitleText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Distance badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF43A047).withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Iconsax.location,
                      size: 13,
                      color: Color(0xFF43A047),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.distance} km',
                      style: const TextStyle(
                        color: Color(0xFF43A047),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pay Later Card — real `scheduled_collection_data` row. Android parity
// (PayLaterAdapter: tv_custname / tv_crf / tv_lastpaiddate=status /
// tv_Amount=scheduled_date) — a plain collection row, NOT the complaint ticket
// card. Shows name + schedule date + status/CRF + amount.
// ─────────────────────────────────────────────────────────────────────────────
class _PayLaterCard extends StatelessWidget {
  final PayLaterSchedule item;
  final bool isLast;
  const _PayLaterCard({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final name = item.customerName.trim().isEmpty
        ? 'NA'
        : item.customerName.trim();
    final date = item.scheduledDate.trim().isEmpty
        ? 'NA'
        : item.scheduledDate.trim();
    final status = item.status.trim();
    final crf = item.crfno.trim();
    final amount = item.amount.trim();
    final showAmount = amount.isNotEmpty && amount != '0' && amount != '0.0';

    final t = AppThemeConst.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  name != 'NA' ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + schedule date + status/CRF
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: t.cardBodyText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event, size: 13, color: t.cardSubtitleText),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Schedule: $date',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: t.cardSubtitleText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (status.isNotEmpty || crf.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (status.isNotEmpty) 'Status: $status',
                        if (crf.isNotEmpty) 'CRF: $crf',
                      ].join('    '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: t.cardSubtitleText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Amount badge (when present)
            if (showAmount) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '₹$amount',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium AppBar
// ─────────────────────────────────────────────────────────────────────────────

/// Logo asset for the current flavor. Reads [AppConfig.instance] defensively:
/// a hot reload can transiently reset the `late` static field, and we must not
/// let the AppBar crash. Falls back to the Magik logo (the primary flavor).
String _appBarLogoAsset() {
  try {
    return AppConfig.instance.flavor == Flavor.magik
        ? 'assets/mainlogo.png'
        : 'assets/ezy_digi_pics.png';
  } catch (_) {
    return 'assets/mainlogo.png';
  }
}

class _PremiumAppBar extends StatelessWidget {
  const _PremiumAppBar();
  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Status-bar icons (time/battery/wifi) must contrast the app bar: DARK on
      // the light Premium-Light bar, LIGHT on the blue bar — else they vanish
      // white-on-white (the issue seen vs the reference Uber light UI).
      // (.dark = dark icons for a light bar; .light = light icons for a dark bar)
      value: t.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          color: t.isLight ? t.appBarBg : null,
          gradient: t.isLight
              ? null
              : const LinearGradient(
                  colors: [
                    Color(0xFF0D47A1),
                    Color(0xFF1565C0),
                    Color(0xFF1976D2),
                  ],
                  stops: [0.0, 0.6, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          boxShadow: [
            BoxShadow(
              color: t.isLight
                  ? Colors.black.withValues(alpha: 0.08)
                  : const Color(0xFF0D47A1).withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  // ── Hamburger — white pill, premium exclusive touch ────────
                  Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: t.appBarFg.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: t.appBarFg.withValues(alpha: 0.30),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Iconsax.menu_1,
                          color: t.appBarFg,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  // ── Logo centred ───────────────────────────────────────────
                  const SizedBox(width: 8.0),
                  const Spacer(),
                  // Android parity (MainActivity toolbar_logo:384-408): tapping the
                  // logo returns to the Dashboard home. Flutter's logo lives only on
                  // the dashboard scaffold, so from a sub-tab this jumps back to the
                  // Dashboard tab (deep screens use their own back button).
                  GestureDetector(
                    onTap: () => context
                        .findAncestorStateOfType<DashboardScreenState>()
                        ?.setTab(0),
                    child: Image.asset(
                      _appBarLogoAsset(),
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Spacer(),
                  // ── Action icons with pill containers ────────────────────
                  _AppBarIcon(
                    icon: Iconsax.search_normal,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchCustomerScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _AppBarIcon(
                    icon: Iconsax.bluetooth,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BluetoothDevicesScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _AppBarIcon(
                    icon: Iconsax.calendar,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EventManagementScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _AppBarIcon(
                    icon: Iconsax.scan_barcode,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanCustomerScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AppBarIcon — small icon with translucent rounded pill container
// ─────────────────────────────────────────────────────────────────────────────
class _AppBarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AppBarIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: t.appBarFg.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: t.appBarFg.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
        child: Icon(icon, color: t.appBarFg, size: 20),
      ),
    );
  }
}
