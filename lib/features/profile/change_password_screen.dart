import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import 'data/change_password_repository.dart';

/// Change Password — Android parity (UserProfile_ChangePsw_Fragment):
/// Old / New / Confirm, client validation (empty + mismatch), SOAP
/// `passwordChange`, Android-equivalent success/error messages.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final oldP = _old.text.trim();
    final newP = _new.text.trim();
    final conf = _confirm.text.trim();

    // Client validation (Android parity) — empty fields, then mismatch.
    if (oldP.isEmpty || newP.isEmpty || conf.isEmpty) {
      _snack('Password fields should not be empty.');
      return;
    }
    if (newP != conf) {
      _snack('New password and Confirm Password does not match.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final r = await ChangePasswordRepository.instance
        .change(oldPassword: oldP, newPassword: newP);
    if (!mounted) return;
    setState(() => _loading = false);

    if (r.success) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Password Updated!'),
          content: const Text('Password Updated Successfully'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      _snack(r.statusMessage.isEmpty
          ? 'Please check and Enter Valid Details'
          : r.statusMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Gradient header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
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
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Update Password',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('Keep your account secure.',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // ── Fields card ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: t.cardShadowColor,
                      blurRadius: 14,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    t: t,
                    label: 'Old Password',
                    icon: Icons.lock_clock_outlined,
                    controller: _old,
                    obscure: _obscureOld,
                    onToggle: () => setState(() => _obscureOld = !_obscureOld),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    t: t,
                    label: 'New Password',
                    icon: Icons.lock_outline_rounded,
                    controller: _new,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    t: t,
                    label: 'Confirm New Password',
                    icon: Icons.lock_reset_rounded,
                    controller: _confirm,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('UPDATE PASSWORD',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: 0.4)),
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

  Widget _field({
    required AppThemeConst t,
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: !_loading,
      style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: t.cardBodyText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.cardSubtitleText, fontSize: 13),
        filled: true,
        fillColor: t.inputBg,
        prefixIcon: Icon(icon, size: 20, color: t.accent),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.accent, width: 1.6),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: t.cardSubtitleText),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
