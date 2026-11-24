import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/server_url_resolver.dart';
import '../../core/theme/app_theme.dart';
import 'ezy_alert_dialog.dart';
import 'ezy_start_gate.dart';

/// Ezy (CloudDigi) one-time device registration — native CloudAuthentication.
/// Opened only by [EzyStartGate] when the BMS says this device is not
/// registered. The typed key goes to the same BMS call (smsCode); on success
/// the start-up check runs again, like native returning to
/// AppVersionCheck_Activity.
class DeviceRegistrationScreen extends StatefulWidget {
  const DeviceRegistrationScreen({super.key});

  @override
  State<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _registering = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_registering) return;
    FocusScope.of(context).unfocus();
    final key = _keyController.text.trim();

    // Native CloudAuthentication:152-167.
    if (key.isEmpty) {
      await _showDialog('Empty Fields!', 'SMS Key should not be empty.',
          type: EzyAlertType.warning);
      return;
    }

    // Native :171-186.
    final connectivity = await Connectivity().checkConnectivity();
    if (!mounted) return;
    if (connectivity.contains(ConnectivityResult.none)) {
      await _showDialog(
          'No Internet Connection', 'Please turn on device Wifi or Data Network',
          type: EzyAlertType.warning, icon: Icons.wifi_off_rounded);
      return;
    }

    setState(() => _registering = true);
    _showProgress(); // native ProgressDialog "Registering, Please wait..."
    final r = await ServerUrlResolver.instance.authenticate(smsCode: key);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress
    setState(() => _registering = false);

    final code = r.statusCode;
    if (code == 0) {
      // Native :343-378 (non-cancellable) → back to the start-up check.
      await _showDialog(
        'Registration Successful.',
        "Your Registration with this device is Successful. Press 'OK' to Login.",
        type: EzyAlertType.success,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const EzyStartGate()),
      );
      return;
    }
    if (code != null) {
      // Native :380-415 (1 and 2+ show the same message).
      await _showDialog('Registration Failed!',
          '${r.statusMessage}. Please check and enter valid details',
          icon: Icons.gpp_bad_rounded);
      return;
    }
    // Native :416-431 — no reply; stays on this screen.
    await _showDialog('Server connectivity error!',
        'Server is busy or unreachable!. Please try again after sometime.',
        dismissible: true,
        type: EzyAlertType.warning,
        icon: Icons.cloud_off_rounded);
  }

  // native ProgressDialog "Registering, Please wait..."
  void _showProgress() => showEzyProgress(context, 'Registering, Please wait...');

  Future<void> _showDialog(
    String title,
    String message, {
    bool dismissible = false,
    EzyAlertType type = EzyAlertType.error,
    IconData? icon,
  }) {
    return showEzyAlert(
      context,
      title: title,
      message: message,
      type: type,
      icon: icon,
      dismissible: dismissible,
    );
  }

  OutlineInputBorder _fieldBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.theme1,
      child: Scaffold(
        backgroundColor: _blueDark,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_blueLight, _blueDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Soft background circles (decoration only).
              const Positioned(top: -90, right: -70, child: _Bubble(240, 0.08)),
              const Positioned(
                  bottom: -110, left: -80, child: _Bubble(280, 0.07)),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _card(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card() {
    const radius = 28.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: EzyWave(color: AppColors.secondary, height: 84),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/ezy_digi_pics.png',
                      height: 64, fit: BoxFit.contain),
                  const SizedBox(height: 22),
                  const Text(
                    'User Registration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the registration key to register this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF5B6475)),
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: _keyController,
                    enabled: !_registering,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _register(),
                    style: const TextStyle(fontSize: 16, color: _navy),
                    decoration: InputDecoration(
                      hintText: 'Registration Key',
                      hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 14, right: 8),
                        child: Icon(Icons.vpn_key_outlined,
                            color: Color(0xFF4B5563)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 48),
                      filled: true,
                      fillColor: const Color(0xFFF5F8FE),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      border: _fieldBorder(_fieldLine),
                      enabledBorder: _fieldBorder(_fieldLine),
                      disabledBorder: _fieldBorder(_fieldLine),
                      focusedBorder: _fieldBorder(AppColors.secondary, 1.6),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _RegisterButton(
                    loading: _registering,
                    onPressed: _register,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'itpworld.com,  All Rights Reserved',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF5B6475)),
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

const Color _blueLight = Color(0xFF1E88E5);
const Color _blueDark = Color(0xFF0D47A1);
const Color _navy = Color(0xFF0B1F4D);
const Color _fieldLine = Color(0xFFD9E2F2);

class _Bubble extends StatelessWidget {
  const _Bubble(this.size, this.alpha);

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      ),
    );
  }
}

/// Pill REGISTER button with arrow. Same behaviour as before: taps are
/// ignored and a spinner shows while [loading].
class _RegisterButton extends StatelessWidget {
  const _RegisterButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_blueLight, _blueDark]),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: _blueDark.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: loading ? null : onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'REGISTER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 22),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
