import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ezy_cable_digi/core/services/auth_service.dart';
import 'package:ezy_cable_digi/core/services/error_handler_service.dart';
import 'package:ezy_cable_digi/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../customers/customer_list_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/location_sync_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/network/server_url_resolver.dart';
import '../offline/offline_dashboard_screen.dart';
import '../../widgets/primary_button.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username and password')),
      );
      return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    // iPad-only: iPhone keeps its original (unchanged) layout below.
    final isTablet = size.shortestSide >= 600;

    final loginCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        margin: const EdgeInsets.only(top: 38),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusXL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 30,
              spreadRadius: 1,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: 440,
          borderRadius: AppSizes.radiusXL,
          blur: 18,
          alignment: Alignment.center,
          border: 1.6,
          linearGradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.68),
              Colors.white.withValues(alpha: 0.22),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderGradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0.35),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingL,
              56,
              AppSizes.paddingL,
              AppSizes.paddingL,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassTextField(
                    controller: _userController,
                    hint: 'Username',
                    enabled: !_isOffline,
                    lottieAsset: 'assets/Profile Icon.json',
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  _GlassTextField(
                    controller: _passwordController,
                    hint: 'Password',
                    obscureText: true,
                    enabled: !_isOffline,
                    lottieAsset: 'assets/Login.json',
                    showPasswordToggle: true,
                  ),
                  const SizedBox(height: AppSizes.paddingS),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                        activeColor: AppColors.accent,
                      ),
                      const Text(
                        'Remember Me',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  PrimaryButton(
                    label: 'SIGN IN',
                    isLoading: _isLoading,
                    onPressed: _handleLogin,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final logoRing = _GlowLogoRing(
      asset: AppConfig.instance.flavor == Flavor.magik
          ? 'assets/mainlogo.png'
          : 'assets/ezy_digi_pics.png',
    );

    return Theme(
      data: AppTheme.theme1,
      child: Scaffold(
        backgroundColor: AppTheme.theme1.scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: size.height * 0.55,
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.paddingM,
                ),
                child: Column(
                  children: [
                    // "Welcome to <appName>" removed per request. Keep the same
                    // vertical space so the blur login card does NOT move up.
                    const SizedBox(height: 108),
                    Expanded(
                      child: isTablet
                          // iPad only: align the card block's own vertical
                          // center with the vertical center of the white
                          // background panel below (Align+height 0.55 further
                          // up), matching the phone reference instead of just
                          // centering in the leftover blue space above it.
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final expandedTop = topInset + 108;
                                final panelTop = size.height * 0.45;
                                final panelCenter =
                                    panelTop + (size.height * 0.55) * -0.15;
                                final localCenter = panelCenter - expandedTop;
                                final alignY = constraints.maxHeight > 0
                                    ? ((localCenter / constraints.maxHeight) *
                                                  2 -
                                              1)
                                          .clamp(-1.0, 1.0)
                                    : 0.0;
                                return Align(
                                  alignment: Alignment(0, alignY),
                                  child: Stack(
                                    alignment: Alignment.topCenter,
                                    children: [loginCard, logoRing],
                                  ),
                                );
                              },
                            )
                          // iPhone: original, untouched layout.
                          : Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: loginCard,
                                ),
                                logoRing,
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'itpworld.com, All Rights Reserved',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final String lottieAsset;
  final bool enabled;
  // Android parity: the login password TextInputLayout shows a password-toggle
  // eye by default for textPassword fields. Enabled only for the password field.
  final bool showPasswordToggle;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.lottieAsset,
    this.obscureText = false,
    this.enabled = true,
    this.showPasswordToggle = false,
  });

  @override
  State<_GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<_GlassTextField>
    with SingleTickerProviderStateMixin {
  late bool _obscure = widget.obscureText;

  // Drives the field's Lottie icon: it plays ONCE when the field gains focus
  // (the user taps it) instead of looping forever. Purely decorative — it does
  // not affect the text input in any way.
  final FocusNode _focus = FocusNode();
  late final AnimationController _lottieCtrl = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) _lottieCtrl.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _lottieCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.primary.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          RepaintBoundary(
            child: SizedBox(
              height: 40,
              width: 40,
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
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: _obscure,
              enabled: widget.enabled,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
              ),
            ),
          ),
          // Eye toggle — size-constrained to the 40px row height so the
          // fixed-height glass card never overflows.
          if (widget.showPasswordToggle)
            IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: AppColors.primary.withValues(alpha: 0.75),
              ),
              splashRadius: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Circular logo with a red-neon ring whose bright spot sweeps one full lap
/// around the ring on tap (same effect as the Sync/Clear buttons).
/// Presentation only — tapping just plays the animation, no navigation.
class _GlowLogoRing extends StatefulWidget {
  final String asset;
  const _GlowLogoRing({required this.asset});

  @override
  State<_GlowLogoRing> createState() => _GlowLogoRingState();
}

class _GlowLogoRingState extends State<_GlowLogoRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B5C);
    return GestureDetector(
      onTap: () => _c.forward(from: 0), // one light sweep around the ring
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Container(
            height: 78,
            width: 78,
            padding: const EdgeInsets.all(3), // ring thickness
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _c.isDismissed ? red : null,
              gradient: _c.isDismissed
                  ? null
                  : SweepGradient(
                      transform: GradientRotation(_c.value * 2 * math.pi),
                      colors: const [red, red, Colors.white, red, red],
                      stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: red.withValues(alpha: 0.4),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          );
        },
        child: ClipOval(
          child: Image.asset(
            widget.asset,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
