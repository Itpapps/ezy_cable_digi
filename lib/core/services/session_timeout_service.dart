import 'package:flutter/material.dart';

import '../../features/auth/login_screen.dart';
import '../../features/offline/offline_dashboard_screen.dart';
import 'auth_service.dart';
import 'error_handler_service.dart';
import 'offline_mode_service.dart';
import 'session_service.dart';

/// Root navigator / messenger keys so services can navigate and show a
/// message without a widget BuildContext. Wired into MaterialApp in main.dart.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Logs the user out when the app has been in the background for
/// [backgroundTimeout] or longer.
///
/// The background time is measured with wall-clock timestamps (not a Timer,
/// which the OS suspends in the background, and not a Stopwatch, whose
/// monotonic clock stops while an Android device sleeps).
///
/// Logout here is the same "logout only" as the drawer's Logout button:
/// [AuthService.logout] clears the in-memory session. Remembered credentials,
/// the offline database, pending offline payments and all saved preferences
/// are NOT touched.
///
/// Covered cases:
///  • Online session (logged in) → logout + Login screen.
///  • Offline dashboard (with or without an online session) → leave offline
///    mode + Login screen (offline data is kept).
///  • Already on the Login screen (nobody logged in) → nothing happens, so the
///    typed username/password are not wiped.
///  • App killed by the OS while in the background → it restarts on the Login
///    screen anyway (MaterialApp home).
///  • Short trips out of the app (QR scanner permission, url_launcher, share
///    sheet, UPI app) count as background time from the moment the app left
///    the foreground; under 10 minutes nothing happens.
///  • Open dialogs / bottom sheets / pickers are removed with every other
///    route; screens awaiting API calls already guard with `mounted`.
class SessionTimeoutService {
  SessionTimeoutService._();
  static final SessionTimeoutService instance = SessionTimeoutService._();

  static const Duration backgroundTimeout = Duration(minutes: 10);

  AppLifecycleListener? _listener;
  DateTime? _backgroundedAt;
  bool _loggingOut = false;

  /// Call once after `WidgetsFlutterBinding.ensureInitialized()`.
  void start() {
    _listener ??= AppLifecycleListener(onStateChange: _onStateChange);
  }

  void _onStateChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Keep the FIRST moment the app left the foreground.
        _backgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since == null) return;
        final away = DateTime.now().difference(since);
        // A negative value means the device clock was moved back — treat it
        // as expired rather than letting a clock change extend the session.
        if (away >= backgroundTimeout || away.isNegative) {
          _logoutIfNeeded();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // inactive = notification shade, control centre, system dialogs —
        // the app is still on screen, so it is not counted.
        break;
    }
  }

  Future<void> _logoutIfNeeded() async {
    final online = SessionService.instance.isLoggedIn;
    final offline = OfflineDashboardScreen.isOpen;
    if (!online && !offline) return; // Already on Login — nothing to do.
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      // Same as the drawer Logout: session only, no data is deleted.
      if (online) await AuthService.instance.logout();
      await OfflineModeService.instance.setOfflineMode(false);

      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootMessengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
            ),
          );
      });
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(
        error,
        stackTrace,
        reason: 'SessionTimeoutService.logout',
      );
    } finally {
      _loggingOut = false;
    }
  }
}
