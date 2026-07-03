import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:ezi_cable_digi/core/services/auth_service.dart';
import 'package:ezi_cable_digi/core/services/error_handler_service.dart';
import 'package:ezi_cable_digi/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/location_sync_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/network/server_url_resolver.dart';
import '../offline/offline_dashboard_screen.dart';
import '../../widgets/primary_button.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/app_strings.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    LocationSyncService.instance.onScreenOpened(TrackingScreen.login);
    _requestPermissions();
    _resolveServerUrl();
    _loadRememberedCredentials();
    _refreshOfflineState();
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
    try {
      final resolved = await ServerUrlResolver.instance.resolve();
      if (!resolved) {
        await ServerUrlResolver.instance.loadCached();
      }
    } catch (_) {
      await ServerUrlResolver.instance.loadCached();
    }
  }

  /// Asks for Location + Nearby Devices (Bluetooth) as soon as login screen opens.
  Future<void> _requestPermissions() async {
    await [
      Permission.locationWhenInUse,  // shows Location dialog
      Permission.bluetoothScan,      // shows "Nearby devices" dialog on Android 12+
      Permission.bluetoothConnect,
      Permission.notification,       // ask at login, not after the first payment
    ].request();
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
      final result = await AuthService.instance.login(
        username: username,
        password: password,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      await OfflineModeService.instance.setOfflineMode(false);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const DashboardScreen(),
        ),
      );
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace, reason: 'LoginScreen._handleLogin');
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

    return Theme(
      data: AppTheme.theme1,
      child: Scaffold(
        backgroundColor: AppTheme.theme1.scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
DropdownButton<String>(
  value: AppStrings.currentLang,
  items: const [
    DropdownMenuItem(value: 'en', child: Text('English')),
    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
    DropdownMenuItem(value: 'te', child: Text('Telugu')),
    DropdownMenuItem(value: 'ta', child: Text('Tamil')),
    DropdownMenuItem(value: 'or', child: Text('Odia')),
    DropdownMenuItem(value: 'bn', child: Text('Bengali')),
    DropdownMenuItem(value: 'ml', child: Text('Malayalam')),
  ],
  onChanged: (value) {
    AppStrings.currentLang = value!;
    setState(() {});
  },
),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingM),
              child: Column(
                children: [
                  // "Welcome to <appName>" removed per request. Keep the same
                  // vertical space so the blur login card does NOT move up.
                  const SizedBox(height: 108),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Container(
                              margin: const EdgeInsets.only(top: 38),
                              decoration: BoxDecoration(
                                borderRadius:
                                BorderRadius.circular(AppSizes.radiusXL),
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
                                    padding: EdgeInsets.only(
                                      bottom: bottomInset > 0 ? 12 : 0,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        _GlassTextField(
                                          controller: _userController,
                                          hint: 'Username',
                                          enabled: !_isOffline,
                                          lottieAsset:
                                          'assets/Profile Icon.json',
                                        ),
                                        const SizedBox(height: AppSizes.paddingM),
                                        _GlassTextField(
                                          controller: _passwordController,
                                          hint: 'Password',
                                          obscureText: true,
                                          enabled: !_isOffline,
                                          lottieAsset: 'assets/Login.json',
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
                          ),
                        ),
                        Container(
                          height: 78,
                          width: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Android-style: the logo fills the circle (no white
                            // padding) inside a blue ring.
                            border: Border.all(
                              color: AppColors.primary,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 16,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              AppConfig.instance.flavor == Flavor.magik
                                  ? 'assets/mainlogo.png'
                                  : 'assets/ezy_digi_pics.png',
                              width: 78,
                              height: 78,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
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

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final String lottieAsset;
  final bool enabled;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.lottieAsset,
    this.obscureText = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.primary.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
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
                lottieAsset,
                fit: BoxFit.contain,
                renderCache: RenderCache.raster,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              enabled: enabled,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hint,
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
        ],
      ),
    );
  }
}