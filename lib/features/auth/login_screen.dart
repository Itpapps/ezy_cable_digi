import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ezy_cable_digi/core/services/auth_service.dart';
import 'package:ezy_cable_digi/core/services/error_handler_service.dart';
import 'package:ezy_cable_digi/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../customers/customer_list_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/location_sync_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/network/server_url_resolver.dart';
import '../offline/offline_dashboard_screen.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/services/app_version_service.dart';
import '../update/force_update_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  // Android parity: cb_rememberMe defaults to android:checked="true"
  // (activity_login_new.xml:103) — the box is ticked on every open and stays
  // ticked (creds persist) until the user manually unticks and logs in.
  bool _rememberMe = true;
  bool _isLoading = false;
  // Inline validation messages shown in red under each field (null = none).
  String? _userError;
  String? _passwordError;
  // Android disables the username/password EditTexts when offline
  // (LoginActivity.java:248-251). Mirrored via the field `enabled` flag.
  bool _isOffline = false;
  // Device last-known location captured once at login-screen open (Android
  // parity: GPSTracker in LoginActivity.onCreate). Sent with the login request;
  // stays 0.0/0.0 when permission/GPS/last-known are unavailable — login never
  // blocks on location.
  double _loginLat = 0.0;
  double _loginLng = 0.0;
  bool _forceUpdateShown = false;

  @override
  void initState() {
    super.initState();
    // The login screen never has an active offline session: clear any stale
    // offline flag (e.g. app killed inside the Offline Dashboard). The offline
    // login gate sets it again only when the user actually enters offline mode.
    OfflineModeService.instance.setOfflineMode(false);
    LocationSyncService.instance.onScreenOpened(TrackingScreen.login);
    _requestPermissions();
    _captureLoginLocation();
    _resolveServerUrl();
    _loadRememberedCredentials();
    _refreshOfflineState();
    // D3 / Android parity (logout finishes MainActivity): every way back to
    // login drops the previous session's Customer List, so the next user
    // never sees it. Post-frame: notifying listeners inside initState is unsafe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CustomerListProvider>().reset();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppVersion());
  }

  /// Android parity (LoginActivity.java:226-227): prefill the fields with the
  /// remembered credentials on every open. Empty when none were saved. The
  /// checkbox defaults to CHECKED (activity_login_new.xml:103), so remembering
  /// persists across logins unless the user unticks it.
  Future<void> _loadRememberedCredentials() async {
    final creds = await AuthService.instance.loadRememberedCredentials();
    if (!mounted) return;
    if (creds.username.isNotEmpty || creds.password.isNotEmpty) {
      setState(() {
        _userController.text = creds.username;
        _passwordController.text = creds.password;
      });
    }
  }

  /// Detect connectivity so the fields can be disabled offline (Android parity).
  Future<void> _refreshOfflineState() async {
    final connectivity = await Connectivity().checkConnectivity();
    final offline = connectivity.contains(ConnectivityResult.none);
    if (mounted && offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  /// Resolves the data-server URL from BMS in the background.
  /// This was previously done in SplashScreen; doing it here keeps
  /// the app snappy (no artificial 3-second wait) while still ensuring
  /// the URL is ready before the user taps SIGN IN.
  Future<void> _resolveServerUrl() async {
    // Ezy: EzyStartGate already did the BMS check at start-up, and native Ezy's
    // LoginActivity never calls the BMS. Only load the saved logo.
    if (AppConfig.instance.flavor == Flavor.ezy) {
      await ServerUrlResolver.instance.loadCached();
      return;
    }
    try {
      final resolved = await ServerUrlResolver.instance.resolve();
      if (!resolved) {
        await ServerUrlResolver.instance.loadCached();
      }
    } catch (_) {
      await ServerUrlResolver.instance.loadCached();
    }
  }

  /// iOS + Android force update. Never blocks on error.
  Future<void> _checkAppVersion() async {
    final version = await AppVersionService.instance.check();
    if (!mounted || !version.forceUpdate) return;
    _openForceUpdate(version.message);
  }

  void _openForceUpdate(String message) {
    if (_forceUpdateShown) return;
    _forceUpdateShown = true;
    showForceUpdateDialog(context, message);
  }

  /// Asks for Location + Nearby Devices (Bluetooth) as soon as login screen opens.
  Future<void> _requestPermissions() async {
    await [
      Permission.locationWhenInUse, // shows Location dialog
      Permission.bluetoothScan, // shows "Nearby devices" dialog on Android 12+
      Permission.bluetoothConnect,
      Permission.notification, // ask at login, not after the first payment
    ].request();
  }

  /// Capture the device's LAST-KNOWN location once (Android parity: GPSTracker —
  /// cached, non-blocking, never a fresh GPS fix). Stored for the login request.
  /// Does NOT prompt for permission (getLastKnownPosition returns null when not
  /// granted). Any failure → keep 0.0/0.0 and login proceeds normally.
  Future<void> _captureLoginLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        _loginLat = pos.latitude;
        _loginLng = pos.longitude;
      }
    } catch (_) {
      // Location unavailable → keep 0.0/0.0; never block login (Android parity).
    }
  }

  Future<void> _handleLogin() async {
    // Re-check connectivity at press time (Android: isNetworkAvailable()).
    final connectivity = await Connectivity().checkConnectivity();
    final noNetwork = connectivity.contains(ConnectivityResult.none);
    if (!mounted) return;
    if (noNetwork != _isOffline) setState(() => _isOffline = noNetwork);

    // OFFLINE: Android does NOT validate username/password — it applies the
    // 2-day offline gate and either opens the offline dashboard or shows the
    // "Sync Previous data" dialog (LoginActivity.java:270-305).
    if (noNetwork) {
      await _enterOfflineMode();
      return;
    }

    // ONLINE: validate, then real login.
    final username = _userController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _userError = username.isEmpty ? 'Please enter username' : null;
        _passwordError = password.isEmpty ? 'Please enter password' : null;
      });
      return;
    }
    if (_userError != null || _passwordError != null) {
      setState(() => _userError = _passwordError = null);
    }

    setState(() => _isLoading = true);

    try {
      // Outdated build (iOS/Android) cannot log in even if Sign In is tapped quickly.
      final version = await AppVersionService.instance.check();
      if (!mounted) return;
      if (version.forceUpdate) {
        _openForceUpdate(version.message);
        return;
      }
      final result = await AuthService.instance.login(
        username: username,
        password: password,
        rememberMe: _rememberMe,
        lat: _loginLat,
        lang: _loginLng,
      );

      if (!mounted) return;

      if (!result.success) {
        final title = result.dialogTitle;
        if (title != null) {
          // D-B6 / Android Commonempcrf status 1 (LoginActivity :989-1000):
          // non-cancellable dialog with the server message; stays on login.
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            // Android setCancelable(false): Back can't close it either.
            builder: (dialogCtx) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text(title),
                content: Text(result.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }

      await OfflineModeService.instance.setOfflineMode(false);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
      );
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(
        error,
        stackTrace,
        reason: 'LoginScreen._handleLogin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Offline-entry gate — Android parity (LoginActivity.java:270-305).
  /// Allows the offline dashboard only when the last ONLINE login was ≤ 2 days
  /// ago. Reproduces Android's `datediff` exactly: a missing/unparseable saved
  /// date leaves the difference at 0 (allow) — so a fresh install opens an empty
  /// offline dashboard, matching production. A valid date > 2 days → block dialog.
  Future<void> _enterOfflineMode() async {
    final savedDate = await OfflineModeService.instance.lastOnlineLoginDate;
    if (!mounted) return;

    if (_dayDifference(savedDate) <= 2) {
      await OfflineModeService.instance.setOfflineMode(true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const OfflineDashboardScreen()),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Sync Previous data'),
          content: const Text(
            'Please go online and sync previous offline collections data',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                SystemNavigator.pop(); // Android: finish() + System.exit(0)
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Whole-day gap between the saved server date and today, parsed with Android's
  /// `dd-MM-yyyy` format. On any parse failure returns 0 (Android's `datediff`
  /// swallows the exception and leaves the difference at its 0 default).
  int _dayDifference(String savedDate) {
    try {
      final fmt = DateFormat('dd-MM-yyyy');
      final saved = fmt.parse(savedDate);
      final today = fmt.parse(fmt.format(DateTime.now()));
      return today.difference(saved).inDays.abs();
    } catch (_) {
      return 0;
    }
  }

  // ── UI only ───────────────────────────────────────────────────────────────
  // Same fields, texts, flags and callbacks as before; only the look changed.
  // Soft (neumorphic) surfaces with light + dark shadows. Follows the user's
  // theme (Theme 1 blue / Theme 2 premium light) for both flavors.
  @override
  Widget build(BuildContext context) {
    final p = _LoginPalette(AppThemeConst.of(context).isLight);
    final isMagik = AppConfig.instance.flavor == Flavor.magik;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background sits outside the Scaffold, so it does not squeeze or
          // jump when the keyboard opens.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: p.background,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -110,
            right: -80,
            child: _Bubble(size: 260, color: p.bubble),
          ),
          Positioned(
            bottom: -130,
            left: -90,
            child: _Bubble(size: 300, color: p.bubble),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            // Centred when it fits, scrolls when it doesn't
                            // (small phones, big fonts, keyboard open).
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                constraints.maxHeight - 48,
                              ),
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [_buildCard(p, isMagik)],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    child: Text(
                      'itpworld.com, All Rights Reserved',
                      style: TextStyle(
                        color: p.footer,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_LoginPalette p, bool isMagik) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: p.cardGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: p.cardEdge, width: 1.2),
        boxShadow: p.cardShadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo inside the card, at the top (like the registration screen).
          Center(
            child: _CardLogo(isMagik: isMagik, palette: p),
          ),
          const SizedBox(height: 22),
          _LoginField(
            controller: _userController,
            hint: 'Username',
            enabled: !_isOffline,
            lottieAsset: 'assets/Profile Icon.json',
            palette: p,
            errorText: _userError,
            onChanged: (_) {
              if (_userError != null) setState(() => _userError = null);
            },
          ),
          const SizedBox(height: 20),
          _LoginField(
            controller: _passwordController,
            hint: 'Password',
            obscureText: true,
            enabled: !_isOffline,
            lottieAsset: 'assets/Login.json',
            showPasswordToggle: true,
            palette: p,
            errorText: _passwordError,
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                activeColor: p.accent,
                side: BorderSide(color: p.checkboxBorder, width: 1.5),
              ),
              Text(
                'Remember Me',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SignInButton(
            label: 'SIGN IN',
            isLoading: _isLoading,
            onPressed: _handleLogin,
            colors: p.button,
          ),
        ],
      ),
    );
  }
}

/// Colours and soft shadows for the login screen. [light] = Theme 2
/// (Premium Light); otherwise Theme 1 (Default Blue).
class _LoginPalette {
  const _LoginPalette(this.light);

  final bool light;

  static const Color _navy = Color(0xFF1A3C6E);
  static const Color _deepBlue = Color(0xFF06245A);

  List<Color> get background => light
      ? const [Color(0xFFF5F7FF), Color(0xFFE6ECFB)]
      : const [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1E88E5)];

  Color get bubble => light
      ? _navy.withValues(alpha: 0.05)
      : Colors.white.withValues(alpha: 0.07);

  /// Focus border, checkbox, cursor.
  Color get accent => light ? _navy : AppColors.primary;

  List<Color> get button => light
      ? const [_navy, Color(0xFF2563EB)]
      : const [Color(0xFF0D47A1), Color(0xFF1E88E5)];

  // ── Card ────────────────────────────────────────────────────────────────
  List<Color> get cardGradient => const [Color(0xFFFBFCFF), Color(0xFFEDF1FA)];
  Color get cardEdge =>
      light ? Colors.white : Colors.white.withValues(alpha: 0.75);
  List<BoxShadow> get cardShadows => light
      ? [
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-10, -10),
            blurRadius: 28,
          ),
          BoxShadow(
            color: _navy.withValues(alpha: 0.14),
            offset: const Offset(12, 14),
            blurRadius: 32,
          ),
        ]
      : [
          BoxShadow(
            color: _deepBlue.withValues(alpha: 0.38),
            offset: const Offset(0, 20),
            blurRadius: 40,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.10),
            offset: const Offset(0, -2),
            blurRadius: 14,
          ),
        ];

  // ── Soft (raised) elements inside the card ──────────────────────────────
  Color get softDark => const Color(0xFFB6C2DA).withValues(alpha: 0.55);
  Color get softLight => Colors.white;

  Color get fieldFill => const Color(0xFFF6F8FE);
  Color get fieldFillDisabled => const Color(0xFFE9EDF4);
  Color get checkboxBorder => const Color(0xFF9AA6BF);

  Color get textPrimary => AppColors.textPrimary;
  Color get textMuted => AppColors.textSecondary;
  Color get hint => const Color(0xFF8A94A6);

  Color get footer =>
      light ? AppColors.textSecondary : Colors.white.withValues(alpha: 0.85);

  /// Dark status-bar icons on the light theme, white icons on blue.
  SystemUiOverlayStyle get statusBar => SystemUiOverlayStyle(
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    statusBarBrightness: light ? Brightness.light : Brightness.dark,
  );
}

/// Logo at the top of the login card, sized per flavor so each logo is
/// fully readable.
class _CardLogo extends StatelessWidget {
  const _CardLogo({required this.isMagik, required this.palette});

  final bool isMagik;
  final _LoginPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;

    if (isMagik) {
      // Square artwork → small soft raised icon with a white rim.
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: p.softDark,
              offset: const Offset(4, 6),
              blurRadius: 14,
            ),
            BoxShadow(
              color: p.softLight,
              offset: const Offset(-4, -4),
              blurRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.asset(
            'assets/mainlogo_hd.jpg',
            width: 68,
            height: 68,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Ezy: the wide word-mark sits in the middle of a square, transparent
    // PNG. Showing only that band keeps "EZY CABLEDIGI" readable.
    return ClipRect(
      child: Image.asset(
        'assets/ezy_digi_pics.png',
        width: 140,
        height: 64,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _LoginField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final String lottieAsset;
  final bool enabled;
  // Android parity: the login password TextInputLayout shows a password-toggle
  // eye by default for textPassword fields. Enabled only for the password field.
  final bool showPasswordToggle;
  final _LoginPalette palette;

  /// Red message shown under the field (and a red border) when not null.
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _LoginField({
    required this.controller,
    required this.hint,
    required this.lottieAsset,
    required this.palette,
    this.obscureText = false,
    this.enabled = true,
    this.showPasswordToggle = false,
    this.errorText,
    this.onChanged,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField>
    with SingleTickerProviderStateMixin {
  late bool _obscure = widget.obscureText;
  bool _focused = false;

  // Drives the field's Lottie icon: it plays ONCE when the field gains focus
  // (the user taps it) instead of looping forever. Purely decorative — it does
  // not affect the text input in any way.
  final FocusNode _focus = FocusNode();
  late final AnimationController _lottieCtrl = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) _lottieCtrl.forward(from: 0);
    if (mounted && _focused != _focus.hasFocus) {
      setState(() => _focused = _focus.hasFocus); // focus border only
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _lottieCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final enabled = widget.enabled;
    const none = InputBorder.none;
    const errorRed = Color(0xFFD32F2F);
    final error = widget.errorText;

    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: enabled ? p.fieldFill : p.fieldFillDisabled,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: error != null
              ? errorRed
              : _focused
              ? p.accent.withValues(alpha: 0.85)
              : Colors.white,
          width: error != null || _focused ? 1.6 : 1.4,
        ),
        // Soft raised look: dark shadow bottom-right, white light top-left.
        boxShadow: [
          BoxShadow(
            color: p.softDark,
            offset: const Offset(5, 6),
            blurRadius: 14,
          ),
          BoxShadow(
            color: p.softLight,
            offset: const Offset(-5, -5),
            blurRadius: 12,
          ),
          if (_focused)
            BoxShadow(color: p.accent.withValues(alpha: 0.12), spreadRadius: 3),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          // Soft round badge holding the field's Lottie icon.
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFE9EEF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: p.softDark,
                  offset: const Offset(2, 3),
                  blurRadius: 6,
                ),
                BoxShadow(
                  color: p.softLight,
                  offset: const Offset(-2, -2),
                  blurRadius: 5,
                ),
              ],
            ),
            child: RepaintBoundary(
              child: Opacity(
                opacity: enabled ? 1 : 0.5,
                child: SizedBox(
                  height: 30,
                  width: 30,
                  child: Lottie.asset(
                    widget.lottieAsset,
                    fit: BoxFit.contain,
                    // Driven by our controller → no auto-loop; plays once on focus.
                    controller: _lottieCtrl,
                    onLoaded: (composition) =>
                        _lottieCtrl.duration = composition.duration,
                    renderCache: RenderCache.raster,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: _obscure,
              enabled: enabled,
              onChanged: widget.onChanged,
              cursorColor: p.accent,
              style: TextStyle(
                color: enabled ? p.textPrimary : p.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              // Every border set explicitly, so neither theme's input style
              // draws a second box inside the field.
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: p.hint,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
                border: none,
                enabledBorder: none,
                focusedBorder: none,
                disabledBorder: none,
                errorBorder: none,
                focusedErrorBorder: none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 8,
                ),
              ),
            ),
          ),
          if (widget.showPasswordToggle)
            IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 21,
                color: p.accent.withValues(alpha: 0.75),
              ),
              splashRadius: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          const SizedBox(width: 6),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topLeft,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: errorRed,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                            color: errorRed,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// SIGN IN pill. Same behaviour as before: taps are ignored and a spinner
/// shows while [isLoading].
class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
    required this.colors,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.40),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        // Soft gloss on the top half (decoration only, does not block taps).
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: isLoading ? null : onPressed,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
