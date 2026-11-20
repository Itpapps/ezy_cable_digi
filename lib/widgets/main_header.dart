import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../bluetooth/bluetooth_devices_screen.dart';
import '../core/config/app_config.dart';
import '../core/theme/theme_constants.dart';
import '../features/event/event_management_screen.dart';
import '../features/scan/scan_customer_screen.dart';
import '../features/search/search_customer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MainHeader — Android MainActivity's fixed toolbar (app_bar_main.xml):
// menu, logo, search, bluetooth, calendar, scan. Moved unchanged from the
// Dashboard (_PremiumAppBar) so the Dashboard and every screen Android shows
// inside MainActivity (see MainFrame) use the very same header.
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

class MainHeader extends StatelessWidget {
  /// Android toolbar_logo (MainActivity :340-361) → Dashboard home. The
  /// Dashboard switches to its tab 0; a MainFrame screen goes back to it.
  final VoidCallback onLogoTap;

  const MainHeader({super.key, required this.onLogoTap});

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
                  // ── Logo left of centre: a quarter of the way into the gap
                  // between the menu and the icons (Spacer 1 : 3 below),
                  // instead of the middle. Menu and icons stay where they were.
                  const SizedBox(width: 8.0),
                  const Spacer(),
                  // Android parity (MainActivity toolbar_logo:384-408): tapping the
                  // logo returns to the Dashboard home (see [onLogoTap]).
                  GestureDetector(
                    onTap: onLogoTap,
                    child: Image.asset(
                      _appBarLogoAsset(),
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Spacer(flex: 3),
                  // ── Action icons with pill containers ────────────────────
                  _AppBarIcon(
                    icon: Iconsax.search_normal,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchCustomerScreen(),
                      ),
                    ),
                  ),
                  if (AppConfig.bluetoothPrintingEnabled) ...[
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
                  ],
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
