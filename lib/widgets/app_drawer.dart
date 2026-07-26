import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ezy_cable_digi/core/services/theme_service.dart';
import 'package:ezy_cable_digi/features/expenses/list_expenses_screen.dart';
import 'package:ezy_cable_digi/features/offline/offline_dashboard_screen.dart';
import 'package:ezy_cable_digi/features/offline/sync_clear_screen.dart';
import 'package:ezy_cable_digi/features/reports/reports_home_screen.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../core/services/auth_service.dart';
import '../core/services/session_service.dart';
import '../core/constants/app_colors.dart';
import '../core/services/offline_mode_service.dart';
import '../core/widgets/premium_dialog.dart';
import '../features/auth/login_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/settings/printer_settings_screen.dart';
import '../core/config/app_config.dart';
import '../features/search/search_customer_screen.dart';
import '../features/customers/nearest_customers_screen.dart';
import '../features/customers/customer_list_screen.dart';
import '../features/customers/paid_customers_screen.dart';
import '../features/collections/collection_schedule_screen.dart';
import '../features/event/event_management_screen.dart';
import '../features/employee_track/employee_track_screen.dart';
import '../features/offline/download_records_screen.dart';
import '../features/offline/static_content_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/debug/debug_console_screen.dart';

void _closeDrawerThen(
  BuildContext drawerContext,
  void Function(BuildContext navigatorContext) action,
) {
  final navigator = Navigator.of(drawerContext);
  navigator.pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (navigator.context.mounted) {
      action(navigator.context);
    }
  });
}

/// offline data must belong to THIS dealer — the machineNumber stored at
/// download must match the current login's machineNumber. If not, Android shows
/// an "ID Mismatch!" dialog and blocks entry (also covers "no data downloaded").
Future<bool> offlineDataMatchesDealer() async {
  final stored = (await OfflineModeService.instance.machineId).trim();
  final current = SessionService.instance.machineNumber.trim();
  return stored.isNotEmpty &&
      current.isNotEmpty &&
      stored.toLowerCase() == current.toLowerCase();
}

/// Android "ID Mismatch!" dialog (MainActivity:697-710 / :722-731).
Future<void> showIdMismatch(BuildContext ctx) async {
  final usercode = await OfflineModeService.instance.userCode;
  if (!ctx.mounted) return;
  await showPremiumConfirm(
    context: ctx,
    title: 'ID Mismatch!',
    body:
        'You have not downloaded the data or Data already present for $usercode',
    confirmLabel: 'OK',
    cancelLabel: 'Close',
  );
}

// ── Theme Picker — premium dialog ────────────────────────────────────────────
void showThemePicker(BuildContext context) {
  int selected = ThemeService.instance.themeIndex;
  var isSaving = false;
  showPremiumDialog<void>(
    context: context,
    child: StatefulBuilder(
      builder: (ctx2, setDlg) {
        return PremiumDialogShell(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.palette_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Select Theme',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                // Radio tiles
                RadioListTile<int>(
                  value: 0,
                  groupValue: selected,
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Theme 1',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  onChanged: isSaving
                      ? null
                      : (v) {
                          if (v != null) setDlg(() => selected = v);
                        },
                ),
                RadioListTile<int>(
                  value: 1,
                  groupValue: selected,
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Theme 2',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  onChanged: isSaving
                      ? null
                      : (v) {
                          if (v != null) setDlg(() => selected = v);
                        },
                ),
                if (isSaving)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(width: 12),
                        Text('Applying...'),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSaving ? null : () => Navigator.pop(ctx2),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setDlg(() => isSaving = true);
                                try {
                                  await ThemeService.instance.setTheme(
                                    selected,
                                  );
                                  if (ctx2.mounted) Navigator.pop(ctx2);
                                } finally {
                                  if (ctx2.mounted) {
                                    setDlg(() => isSaving = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Apply',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) => _buildDrawer(context);

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Premium Header ────────────────────────────────────────────
            _PremiumDrawerHeader(
              onLogout: () async {
                // Android parity: clear only the active session. Remembered
                // credentials and the offline database are preserved.
                await AuthService.instance.logout();
                await OfflineModeService.instance.setOfflineMode(false);
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              onProfileTap: () => _closeDrawerThen(context, (navCtx) {
                Navigator.of(navCtx).push(
                  MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                );
              }),
              userId: SessionService.instance.username.isNotEmpty
                  ? SessionService.instance.username
                  : 'EDD00485',
              lastLogin: SessionService.instance.lastLogin.isNotEmpty
                  ? SessionService.instance.lastLogin
                  : '2026-03-16  12:37:59',
              lastLoginLabel: 'Last Login',
            ),

            const Divider(height: 1, thickness: 0.5),

            // ── Nav items ─────────────────────────────────────────────────
            _DrawerItem(icon: Iconsax.element_3, labelKey: 'dashboard'),
            _DrawerItem(
              icon: Iconsax.search_normal,
              labelKey: 'search_customer',
            ),
            _DrawerItem(icon: Iconsax.graph, labelKey: 'reports'),
            _DrawerItem(icon: Iconsax.location, labelKey: 'employee_track'),
            _DrawerItem(icon: Iconsax.setting_2, labelKey: 'settings'),
            _DrawerItem(icon: Iconsax.sun_1, labelKey: 'select_theme'),
            _DrawerItem(icon: Iconsax.user_tag, labelKey: 'customer_list'),
            _DrawerItem(icon: Iconsax.money_recive, labelKey: 'paid_customers'),
            _DrawerItem(
              icon: Iconsax.location_tick,
              labelKey: 'nearest_customer',
            ),
            _DrawerItem(icon: Iconsax.wallet_3, labelKey: 'list_expenses'),
            _DrawerItem(
              icon: Iconsax.calendar_1,
              labelKey: 'collection_schedule',
            ),
            _DrawerItem(
              icon: Iconsax.calendar_tick,
              labelKey: 'calendar_event_list',
            ),

            const Divider(height: 12, thickness: 0.5),
            // ── Offline Options ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Text(
                'OFFLINE OPTIONS',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 1,
              ),
              leading: const Icon(
                Icons.wifi_off,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                'Switch to Offline Mode',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () {
                _closeDrawerThen(context, (navCtx) async {
                  // Android: block if this dealer's data isn't downloaded.
                  if (!await offlineDataMatchesDealer()) {
                    if (navCtx.mounted) await showIdMismatch(navCtx);
                    return;
                  }
                  final conn = await Connectivity().checkConnectivity();
                  final online = !conn.contains(ConnectivityResult.none);
                  if (!navCtx.mounted) return;
                  if (online) {
                    // Android "Internet Connected" info dialog before entering.
                    final ok = await showPremiumConfirm(
                      context: navCtx,
                      title: 'Internet Connected',
                      body:
                          'You are connected to internet. You can turn off internet connection in OFFLINE MODE.',
                      confirmLabel: 'OK',
                      cancelLabel: 'Cancel',
                    );
                    if (!ok || !navCtx.mounted) return;
                  }
                  Navigator.push(
                    navCtx,
                    MaterialPageRoute(
                      builder: (_) => const OfflineDashboardScreen(),
                    ),
                  );
                });
              },
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 1,
              ),
              leading: const Icon(
                Icons.download,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                'Download Data (OFFLINE)',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () {
                _closeDrawerThen(context, (navCtx) {
                  Navigator.push(
                    navCtx,
                    MaterialPageRoute(
                      builder: (_) => const DownloadRecordsScreen(),
                    ),
                  );
                });
              },
            ),

            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 1,
              ),
              leading: const Icon(
                Icons.sync,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                'Sync / Clear Data',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () {
                // Android nav_syncdata: machineNumber guard → SyncData_Fragment
                // (a screen with Sync + Clear + counts). No one-shot dialog.
                _closeDrawerThen(context, (navCtx) async {
                  if (!await offlineDataMatchesDealer()) {
                    if (navCtx.mounted) await showIdMismatch(navCtx);
                    return;
                  }
                  if (!navCtx.mounted) return;
                  Navigator.push(
                    navCtx,
                    MaterialPageRoute(builder: (_) => const SyncClearScreen()),
                  );
                });
              },
            ),

            const Divider(height: 12, thickness: 0.5),

            // ── Other ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Text(
                'Other',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 1,
              ),
              title: Text('About Us', style: const TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                final state = context
                    .findAncestorStateOfType<DashboardScreenState>();
                if (state != null) {
                  state.setTab(4);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaticContentScreen(
                        title: 'About Us',
                        body: kDummyAboutUs,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 1,
              ),
              title: Text(
                'Privacy Policy',
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyWebView(),
                  ),
                );
              },
            ),
            // API Debug Console — dev + profile builds only. Both kDebugMode and
            // kProfileMode are compile-time `false` in a RELEASE build, so this
            // entry AND the DebugConsoleScreen reference are tree-shaken out — it
            // can never ship in the Play Store (release) build.
            if (kDebugMode || kProfileMode)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 1,
                ),
                leading: const Icon(
                  Icons.bug_report,
                  color: AppColors.primary,
                  size: 20,
                ),
                title: const Text(
                  'API Debug Console',
                  style: TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context); // close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DebugConsoleScreen(),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PremiumDrawerHeader — compact, exclusive, production-safe.
// No BackdropFilter / CustomPainter — pure Container + Stack for perf.
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumDrawerHeader extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final String userId;
  final String lastLogin;
  final String lastLoginLabel;

  const _PremiumDrawerHeader({
    required this.onLogout,
    required this.onProfileTap,
    required this.userId,
    required this.lastLogin,
    required this.lastLoginLabel,
  });
  @override
  Widget build(BuildContext context) {
    // Derive initials from userId (e.g. "EDD00485" → "ED")
    final initials = userId.length >= 2
        ? userId.substring(0, 2).toUpperCase()
        : userId.toUpperCase();
    final topPadding = MediaQuery.of(context).padding.top;
    return GestureDetector(
      onTap: onProfileTap,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050E24), Color(0xFF0A2472), Color(0xFF1565C0)],
            stops: [0.0, 0.50, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // ── Subtle decorative circles (pure Containers = zero GPU cost) ──
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -10,
              left: -15,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),

            // ── Main content ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(16, topPadding + 22, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Row 1: Logo  +  Logout pill ───────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: Image.asset(
                          AppConfig.instance.flavor == Flavor.magik
                              ? 'assets/mainlogo.png'
                              : 'assets/ezy_digi_pics.png',
                          height: 28,
                          fit: BoxFit.contain,
                        ),
                      ),

                      const Spacer(),

                      // Logout pill
                      GestureDetector(
                        onTap: onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFEF4444,
                              ).withValues(alpha: 0.40),
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Iconsax.logout,
                                color: Colors.white,
                                size: 13,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'LOGOUT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ── Row 2: Avatar  +  User info ───────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar circle with initials
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 2.0,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // User ID + last login
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userId,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '$lastLoginLabel  $lastLogin',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Chevron → profile hint
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 20,
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// _DrawerItem — compact nav tiles
// ─────────────────────────────────────────────────────────────────────────────
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String labelKey;

  const _DrawerItem({required this.icon, required this.labelKey});

  // labelKey also drives the routing switch below — keep both in sync.
  static const Map<String, String> _labels = {
    'dashboard': 'Dashboard',
    'search_customer': 'Search Customer',
    'reports': 'Reports',
    'employee_track': 'Employee Track',
    'settings': 'Settings',
    'select_theme': 'Select Theme',
    'customer_list': 'Customer List',
    'paid_customers': 'Paid Customers',
    'nearest_customer': 'Nearest Customer',
    'list_expenses': 'List Expenses',
    'collection_schedule': 'Collection Schedule',
    'calendar_event_list': 'Calendar Event List',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[labelKey] ?? labelKey;

    void handleTap() {
      // Dashboard returns to the dashboard feed (tab 0) from ANY bottom-nav tab —
      // Android parity (MainActivity nav_dashboard → DashboardHomeFragment). The
      // DashboardScreenState must be resolved from THIS drawer context (a
      // descendant), NOT the root-navigator context _closeDrawerThen passes back
      // (an ancestor → would resolve null). Mirrors the About Us item's setTab(4).
      if (labelKey == 'dashboard') {
        final dash = context.findAncestorStateOfType<DashboardScreenState>();
        Navigator.of(context).pop(); // close drawer
        dash?.setTab(0);
        return;
      }
      _closeDrawerThen(context, (navCtx) {
        switch (labelKey) {
          case 'search_customer':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const SearchCustomerScreen()),
            );
            break;
          case 'settings':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            );
            break;
          case 'nearest_customer':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const NearestCustomersScreen()),
            );
            break;
          case 'customer_list':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const CustomerListScreen()),
            );
            break;
          case 'paid_customers':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const PaidCustomersScreen()),
            );
            break;
          case 'list_expenses':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const ListExpensesScreen()),
            );
            break;
          case 'collection_schedule':
            Navigator.of(navCtx).push(
              MaterialPageRoute(
                builder: (_) => const CollectionScheduleScreen(),
              ),
            );
            break;
          case 'calendar_event_list':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const EventManagementScreen()),
            );
            break;
          case 'employee_track':
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const EmployeeTrackScreen()),
            );
            break;
          case 'select_theme':
            showThemePicker(navCtx);
            break;
          case 'reports':
            // Android parity: drawer → Reports opens the Reports Home screen
            // (ReportsHome_Fragment), not a bottom sheet.
            Navigator.of(navCtx).push(
              MaterialPageRoute(builder: (_) => const ReportsHomeScreen()),
            );
            break;
          default:
            break;
        }
      });
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
      leading: Icon(icon, size: 20, color: AppColors.primary),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: handleTap,
    );
  }
}
