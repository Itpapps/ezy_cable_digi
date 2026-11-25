import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ezy_cable_digi/features/offline/offline_dashboard_screen.dart';
import 'package:ezy_cable_digi/features/offline/download_records_screen.dart';
import 'package:ezy_cable_digi/features/reports/mini_day_report_screen.dart';
import 'package:ezy_cable_digi/features/reports/monthly_report_screen.dart';
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
import '../../core/database/database_helper.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../../core/services/location_sync_service.dart';
import '../../main.dart';
import '../auth/login_screen.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/main_frame.dart';
import '../../widgets/main_header.dart';
import '../customers/customer_list_screen.dart';
import '../../features/settings/printer_settings_screen.dart';
import 'dashboard_controller.dart';
import 'dashboard_refresh_signal.dart';
import 'data/nearest_repository.dart';
import '../collections/data/pay_later.dart';

enum _FeedType { complaints, unpaid, nearest, payLater }

/// D8: RouteAware listener for [pageRouteObserver] — calls [onReturn] when a
/// full screen above the dashboard is closed back to it.
class _PageReturnWatcher with RouteAware {
  final VoidCallback onReturn;
  _PageReturnWatcher(this.onReturn);

  @override
  void didPopNext() => onReturn();
}

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
  final Uri? mapUri; // OpenComplaint.mapUri — null: no customer location

  const _TicketItem({
    required this.ticketId,
    required this.name,
    required this.description,
    required this.customerId,
    required this.status,
    this.statusLabel,
    this.altCustomerId = '',
    this.realComplaintId = '',
    this.mapUri,
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

  /// The live Dashboard — the root route of an online session. MainFrame
  /// screens (pushed routes, so findAncestorStateOfType cannot see it) use it
  /// for their bottom bar, logo and drawer "Dashboard". Set in initState and
  /// cleared only by the same instance (an old and a new Dashboard can be
  /// mounted together for one transition).
  static DashboardScreenState? current;

  /// The selected bottom-bar tab (MainFrame highlights the same one).
  int get selectedTab => _selectedTab;

  int _selectedTab = 0;
  bool _statsCollapsed = false;

  // D-B1 / Android DashboardHomeFragment :261-283 — user-type gating.
  //  DEALER/ADMIN: everything. EMPLOYEE: hides ll1 (Due / Month Billing /
  //  Onetime). SERVICE: no DashboardDetails call; hides ll1 + ll2 (all money
  //  cards), ll_operations (quick actions) and the Unpaid/PayLater tabs.
  String get _userType =>
      SessionService.instance.userType.trim().toUpperCase();
  bool get _isService => _userType == 'SERVICE';
  bool get _showMoneyCards => !_isService;
  bool get _showRow1Cards => !_isService && _userType != 'EMPLOYEE';
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

  // D8: KPIs now reload on every return, so never stack a second KPI error
  // dialog on top of one that is still open.
  bool _kpiDialogOpen = false;

  void _showKpiErrorDialog({required String title, required String message}) {
    if (!mounted || _kpiDialogOpen) return;
    _kpiDialogOpen = true;
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
    ).whenComplete(() => _kpiDialogOpen = false);
  }

  // DUMMY login-notification popup — one-shot guard so it shows only once.
  bool _notificationShown = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    current = this;
    LocationSyncService.instance.onScreenOpened(TrackingScreen.dashboard);
    _dash.addListener(_onDash);
    // D-B1: Android never calls DashboardDetails for SERVICE users.
    if (!_isService) {
      _dash.loadKpis().then((_) => _handleKpiResult());
    }
    _dash
        .loadWallet(); // Android: lcowallet() on dashboard create (DEALER/ADMIN)
    _dash.loadComplaints(); // Complaints is the default feed tab.
    // DUMMY login notification popup (demo only). Comment out this line to
    // disable it until the real API is ready.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLoginNotification(),
    );
    _autoSyncOfflinePayments(); // B-B1
  }

  /// B-B1 / Android MainActivity.onCreate → synvkkm() (:423, :910-919): when the
  /// online dashboard opens with pending offline payments and a network, send
  /// them in the background. Same single-flight sync as Sync/Clear (rejected
  /// payments stay pending). No machine-ID check, exactly like Android (user's
  /// decision). Never throws; silent when nothing is pending or offline.
  Future<void> _autoSyncOfflinePayments() async {
    try {
      final pending = await DatabaseHelper().getOfflinePaidCount();
      if (pending == 0) return;
      final conn = await Connectivity().checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) return;
      final r = await OfflineSyncService.instance.syncPendingToServer();
      if (!mounted) return;
      if (r.failed > 0) {
        showPremiumSnackBar(
            context, 'Synced ${r.synced} record(s), ${r.failed} not synced',
            isError: true);
      } else if (r.synced > 0) {
        showPremiumSnackBar(context, 'Synced ${r.synced} record(s)',
            isSuccess: true);
      }
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'Dashboard offline auto-sync');
    }
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

  // D8: separate listener on the page-only observer, so only a full screen
  // closing back to the dashboard reloads it (dialogs / sheets never do).
  late final _PageReturnWatcher _pageWatcher =
      _PageReturnWatcher(_onReturnedFromScreen);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)!;
    routeObserver.subscribe(this, route);
    if (route is PageRoute) pageRouteObserver.subscribe(_pageWatcher, route);
  }

  @override
  void dispose() {
    if (identical(current, this)) current = null;
    routeObserver.unsubscribe(this);
    pageRouteObserver.unsubscribe(_pageWatcher);
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
  }

  /// D8 / Android DashboardHomeFragment.onCreateView (:262-283): every return
  /// to the dashboard (changeFragment replace) RE-CREATES it, so the KPIs,
  /// the wallet and the COMPLAINTS feed reload and the feed resets to the
  /// default (Complaints); getunpaiddata stays lazy (re-tapping Unpaid
  /// force-refetches). Previously Flutter did this only after a payment.
  /// Called only when a full screen is popped back to the dashboard (never
  /// for dialogs/sheets). Every load below is crash-safe (never throws, keeps
  /// ₹0.00/empty on failure) and single-flight (a call while the same load is
  /// running is skipped), so quick back-and-forth can't stack requests.
  void _onReturnedFromScreen() {
    if (!mounted) return;
    // The payment flag is now covered by this reload — clear it so it can't
    // linger and fire later.
    DashboardRefreshSignal.instance.consumeKpiDirty();
    try {
      if (!_isService) {
        _dash.loadKpis().then((_) => _handleKpiResult()); // D-B1
      }
      _dash.loadWallet();
      setState(() {
        _feed = _FeedType.complaints;
        _feedShown = _feedPage;
      });
      _dash.loadComplaints(force: true);
    } catch (error, stackTrace) {
      // Defensive only — the loads above never throw synchronously.
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'Dashboard reload on return');
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
          // Android parity (MainActivity toolbar_logo): the logo returns to
          // the Dashboard tab. Same header as every MainFrame screen.
          child: MainHeader(onLogoTap: () => setTab(0)),
        ),
        bottomNavigationBar: BottomNavBar(
          currentIndex: _selectedTab,
          onChanged: (i) {
            // D-B3 / Android MainActivity :186-200: Expenses opens only with
            // the role's `expenses` permission; otherwise "No Access".
            if (!MainNav.tabAllowed(context, i)) return;
            setState(() => _selectedTab = i);
          },
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
                              // Name first, the collapse toggle right after it
                              // (Flexible: a long name still ellipsizes).
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      // "Hello" lighter, the name bold.
                                      TextSpan(
                                        text: 'Hello ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: t.headingText
                                              .withValues(alpha: 0.80),
                                        ),
                                      ),
                                      TextSpan(
                                        text: SessionService
                                                .instance
                                                .businessName
                                                .isNotEmpty
                                            ? SessionService
                                                .instance.businessName
                                            : 'itp',
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.headingText,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (_showMoneyCards) ...[ // D-B1: no cards → no toggle
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => setState(
                                  () => _statsCollapsed = !_statsCollapsed,
                                ),
                                icon: Icon(
                                  _statsCollapsed
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                  color: t.headingText,
                                  size: 20,
                                ),
                                tooltip: _statsCollapsed
                                    ? 'Show summary'
                                    : 'Hide summary',
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  backgroundColor: t.isLight
                                      ? const Color(0xFF1A3C6E)
                                          .withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              ],
                            ],
                          ),
                          // Collapsible gradient stat cards (Row 1 + Row 2).
                          // D-B1: SERVICE sees no money cards (Android ll1+ll2).
                          if (_showMoneyCards)
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
                                              // D-B1: Due/Bill/Onetime hidden
                                              // for EMPLOYEE (Android ll1).
                                              if (_showRow1Cards) ...[
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
                                              ],
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
                                : Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    // One hero card: Collections on top, the
                                    // other amounts as small tiles inside it.
                                    // Same values, titles and visibility rules
                                    // as the old separate cards.
                                    child: _KpiHeroCard(
                                      title: 'Collections',
                                      amount: _dash.collectionsText,
                                      lottieAsset: 'assets/Growth Chart.json',
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
                                      stats: [
                                        // D-B1: Due / Month Billing / Onetime
                                        // hidden for EMPLOYEE (Android ll1).
                                        if (_showRow1Cards) ...[
                                          _MiniStatData(
                                            'Due Amount',
                                            _dash.dueAmountText,
                                            '',
                                            const Color(0xFFF87171),
                                          ),
                                          _MiniStatData(
                                            'Month Billing',
                                            _dash.monthBillingText,
                                            'This month',
                                            const Color(0xFFFBBF24),
                                          ),
                                          _MiniStatData(
                                            'Onetime Ch...',
                                            _dash.onetimeChargesText,
                                            'Installations',
                                            const Color(0xFF22D3EE),
                                          ),
                                        ],
                                      ],
                                      // LCO Wallet — Android shows it only
                                      // when useLcoDeposit==1 (ll_lcowallet).
                                      // Full-width glassy green tile.
                                      wallet: _dash.showLcoWallet
                                          ? _MiniStatData(
                                              'LCO Wallet',
                                              _dash.lcoWalletText,
                                              'Available',
                                              const Color(0xFF4ADE80),
                                            )
                                          : null,
                                    ),
                                  ),
                          ),

                          // D-B1: SERVICE has no quick actions (Android
                          // ll_operations GONE).
                          if (!_isService) ...[
                          const SizedBox(height: 10),

                          // ── Row 3: Quick Actions — horizontal scroll ───────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              // Premium Light: a hairline border so the white
                              // card separates from the light body.
                              border: t.isLight
                                  ? Border.all(color: t.inputBorderColor)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: t.isLight
                                      ? const Color(0xFF1A3C6E)
                                          .withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
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
                                    colors: const [
                                      Color(0xFF60A5FA),
                                      Color(0xFF1D4ED8),
                                    ],
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
                                    colors: const [
                                      Color(0xFF4ADE80),
                                      Color(0xFF15803D),
                                    ],
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
                                    colors: const [
                                      Color(0xFFFDBA74),
                                      Color(0xFFEA580C),
                                    ],
                                    onTap: () async {
                                      if (!await offlineDataMatchesDealer()) {
                                        if (!context.mounted) return;
                                        await showIdMismatch(context);
                                        return;
                                      }
                                      // Same as the drawer's "Switch to Offline
                                      // Mode": Android "Internet Connected" info
                                      // dialog before entering.
                                      final conn =
                                          await Connectivity().checkConnectivity();
                                      final online = !conn
                                          .contains(ConnectivityResult.none);
                                      if (!context.mounted) return;
                                      if (online) {
                                        final ok = await showPremiumConfirm(
                                          context: context,
                                          title: 'Internet Connected',
                                          body:
                                              'You are connected to internet. You can turn off internet connection in OFFLINE MODE.',
                                          confirmLabel: 'OK',
                                          cancelLabel: 'Cancel',
                                        );
                                        if (!ok || !context.mounted) return;
                                      }
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
                                    colors: const [
                                      Color(0xFFC4B5FD),
                                      Color(0xFF7C3AED),
                                    ],
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
                                    colors: const [
                                      Color(0xFFF9A8D4),
                                      Color(0xFFDB2777),
                                    ],
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
                                    colors: const [
                                      Color(0xFF5EEAD4),
                                      Color(0xFF0F766E),
                                    ],
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
                          ],
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
        borderRadius: BorderRadius.circular(24),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            // Segmented tab bar: a soft track, the selected tab is a raised
            // white pill. Still scrolls sideways on narrow phones.
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4FA),
                borderRadius: BorderRadius.circular(14),
              ),
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
                  // D-B1: SERVICE gets Complaints + Nearest only (Android
                  // ll_tabs GONE → ll_tabs1).
                  if (!_isService) ...[
                  const SizedBox(width: 4),
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
                  ],
                  const SizedBox(width: 4),
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
                  if (!_isService) ...[ // D-B1
                  const SizedBox(width: 4),
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
                ],
              ),
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
    // The customers shown on the dashboard (max 10) — Payment Details ◄ / ►
    // moves through exactly these.
    final shownList = list.take(10).toList();
    return _pagedListView(
      total: list.length,
      cap: 10, // Android UnpaidNewAdapter caps the dashboard preview at 10.
      itemBuilder: (_, i) => _UnpaidCard(
        customer: list[i],
        isLast: i == list.length - 1,
        unpaidList: shownList,
        index: i,
      ),
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
          mapUri: c.mapUri,
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
// KPI hero card — Collections (big, tappable, Lottie) + the other amounts as
// small glass tiles inside the same card. Presentation only: titles, values
// and visibility rules come from the dashboard exactly as before.
// ─────────────────────────────────────────────────────────────────────────────
class _MiniStatData {
  final String title;
  final String amount;
  final String subtitle;
  final Color dot;
  const _MiniStatData(this.title, this.amount, this.subtitle, this.dot);
}

class _KpiHeroCard extends StatefulWidget {
  final String title;
  final String amount;
  final String lottieAsset;
  final VoidCallback onTap;
  final List<_MiniStatData> stats;

  /// LCO Wallet (null = hidden) — its own full-width glassy green tile.
  final _MiniStatData? wallet;

  const _KpiHeroCard({
    required this.title,
    required this.amount,
    required this.lottieAsset,
    required this.onTap,
    required this.stats,
    this.wallet,
  });

  @override
  State<_KpiHeroCard> createState() => _KpiHeroCardState();
}

class _KpiHeroCardState extends State<_KpiHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _replay() {
    _controller.reset();
    _controller.forward();
  }

  /// "₹2683.00" → bold "₹2683" + smaller ".00". Text is unchanged.
  static TextSpan _amountSpan(String amount) {
    const big = TextStyle(
      fontSize: 24,
      color: Colors.white,
      fontWeight: FontWeight.w900,
    );
    final dot = amount.lastIndexOf('.');
    if (dot <= 0 || dot == amount.length - 1) {
      return TextSpan(text: amount, style: big);
    }
    return TextSpan(
      style: big,
      children: [
        TextSpan(text: amount.substring(0, dot)),
        TextSpan(
          text: amount.substring(dot),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _tiles() {
    final tiles = [for (final s in widget.stats) _MiniStat(data: s)];
    Widget row(List<Widget> items) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
    // Up to 3 tiles share one row; 4 (with LCO Wallet) become 2 × 2 so the
    // amounts stay readable on small phones.
    if (tiles.length <= 3) return row(tiles);
    return Column(
      children: [
        row(tiles.sublist(0, 2)),
        const SizedBox(height: 8),
        row(tiles.sublist(2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const radius = 22.0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2F4FD0), Color(0xFF5B5FEF)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Collections — only this part is tappable (as before the
                  // Due / Billing / Onetime / Wallet amounts have no action).
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _replay();
                      widget.onTap();
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Android parity: truncate large amounts with
                              // "…" instead of shrinking the text. Same text;
                              // only the decimals (".00") are drawn smaller.
                              Text.rich(
                                _amountSpan(widget.amount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 46,
                          height: 46,
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
                  if (widget.stats.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _tiles(),
                  ],
                  if (widget.wallet != null) ...[
                    const SizedBox(height: 8),
                    _WalletTile(data: widget.wallet!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LCO Wallet — full-width frosted-glass tile with a green accent: wallet
/// badge, title + amount, "Available" pill and a soft green wave.
class _WalletTile extends StatelessWidget {
  final _MiniStatData data;
  const _WalletTile({required this.data});

  static const Color _green = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.38),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            // Soft green wave along the bottom (decoration only).
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 24,
              child: IgnorePointer(
                child: CustomPaint(painter: _GlassWavePainter(
                  Color(0xFF4ADE80),
                  Color(0xFF34D399),
                )),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  // Glass badge with the wallet icon.
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF7FFF9), Color(0xFFD1FAE5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFF16A34A),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 26,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.amount,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFBBF7D0), // light green
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (data.subtitle.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14532D).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF86EFAC).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: data.dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            data.subtitle,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft two-layer wave along the bottom of a glass tile (decoration only).
class _GlassWavePainter extends CustomPainter {
  final Color back;
  final Color front;
  const _GlassWavePainter(this.back, this.front);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final backPath = Path()
      ..moveTo(0, h * 0.75)
      ..quadraticBezierTo(w * 0.45, h * 0.05, w * 0.70, h * 0.45)
      ..quadraticBezierTo(w * 0.85, h * 0.70, w, h * 0.30)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      backPath,
      Paint()..color = back.withValues(alpha: 0.16),
    );
    final frontPath = Path()
      ..moveTo(0, h * 0.95)
      ..quadraticBezierTo(w * 0.50, h * 0.35, w * 0.78, h * 0.70)
      ..quadraticBezierTo(w * 0.90, h * 0.85, w, h * 0.60)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      frontPath,
      Paint()..color = front.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_GlassWavePainter oldDelegate) =>
      oldDelegate.back != back || oldDelegate.front != front;
}

/// Due Amount / Month Billing / Onetime Charges — small frosted-glass tile in
/// the LCO Wallet style, tinted with its own accent (the tile's dot colour):
/// glowing dot, light-accent amount, accent glow and a soft accent wave.
/// Same compact size as before so all three still fit one row.
class _MiniStat extends StatelessWidget {
  final _MiniStatData data;
  const _MiniStat({required this.data});

  @override
  Widget build(BuildContext context) {
    const radius = 14.0;
    final accent = data.dot;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 16,
              child: IgnorePointer(
                child: CustomPaint(painter: _GlassWavePainter(accent, accent)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Glowing accent dot (as the wallet's pill dot).
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.8),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          data.title,
                          // 2 lines (as the old cards) so narrow phones don't
                          // cut it.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.amount,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        // Light tint of the accent (wallet: light green).
                        color: Color.lerp(accent, Colors.white, 0.6),
                      ),
                    ),
                  ),
                  if (data.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action Tile — coloured gradient icon square + label (same actions).
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Intrinsic width — no hard fixed width so text fits in one line
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
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
// Feed Filter Chip — one tab of the segmented bar (selected = raised pill).
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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

  /// Android OpenComplaints_RecyclerView_Adapter :78-117 (map icon): Google
  /// Maps directions to the customer, or "Location details not found.".
  void _openMap(BuildContext context) {
    final uri = item.mapUri;
    if (uri == null) {
      showPremiumSnackBar(context, 'Location details not found.');
      return;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isAssigned = item.status == _TicketStatus.assigned;
    final statusText =
        item.statusLabel ?? (isAssigned ? 'ASSIGNED' : 'INPROCESS');
    final statusColor = _statusColor(statusText);

    final initial = item.name.trim().isEmpty
        ? '?'
        : item.name.trim()[0].toUpperCase();

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECF5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + name + status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(statusColor, Colors.white, 0.25)!,
                              statusColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Name : ${item.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.30),
                                ),
                              ),
                              child: Text(
                                'Status : $statusText',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Details panel: ticket id, description, LCO customer id
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F8FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.ticketId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: AppColors.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'LCO Customer ID : ${item.customerId}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Update Status (gradient pill) + map button
                  Row(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E40AF), Color(0xFF3B5BDB)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1E40AF)
                                    .withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
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
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.3,
                              ),
                            ),
                            label: const Text('Update Status'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Android map icon: directions to the customer.
                      Material(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openMap(context),
                          child: const SizedBox(
                            width: 46,
                            height: 46,
                            child: Icon(
                              Iconsax.location,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Status colour stripe on the left edge (decoration only).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(width: 2.5, color: statusColor),
              ),
            ),
          ],
        ),
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
  final List<Customer> unpaidList;
  final int index;
  const _UnpaidCard({
    required this.customer,
    required this.isLast,
    required this.unpaidList,
    required this.index,
  });

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
        border: Border.all(color: const Color(0xFFE6ECF5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
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
                builder: (_) => PaymentOptionsScreen(
                  customer: customer,
                  unpaidList: unpaidList,
                  unpaidIndex: index,
                ),
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
          border: Border.all(color: const Color(0xFFE6ECF5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
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
        border: Border.all(color: const Color(0xFFE6ECF5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
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

