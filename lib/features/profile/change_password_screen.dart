import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import 'data/change_password_repository.dart';
import '../../core/widgets/premium_dialog.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Change Password — Android parity (UserProfile_ChangePsw_Fragment):
/// Old / New / Confirm, client validation (empty + mismatch), SOAP
/// `passwordChange`, Android-equivalent success/error messages.
/// Issue 1 (QA): the new password must also meet the web app's rules
/// ([_PasswordRule.all]) — checked after the Android checks, before the
/// request. Login with an existing password is not affected.
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
    // Issue 1: the web app's password rules, first unmet rule wins.
    for (final rule in _PasswordRule.all) {
      if (!rule.isMet(newP)) {
        _snack(rule.message);
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    // Android UserProfile_ChangePsw_Fragment :263: a non-cancellable
    // "Updating...,   Please wait..." while the change runs. It also keeps the
    // header / bottom bar / drawer from opening another screen meanwhile —
    // the success pop below must close THIS screen.
    showPremiumLoading(context,
        message: 'Updating...,   Please wait...', canPop: false);
    final r = await ChangePasswordRepository.instance
        .change(oldPassword: oldP, newPassword: newP);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
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
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
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
                  // Rules checklist (still tracks the New Password field)
                  // sits below both password fields, above the button.
                  const SizedBox(height: 12),
                  _rulesChecklist(t),
                  const SizedBox(height: 20),
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

  /// Issue 1: the web's rule list under "New Password"; each line turns green
  /// as the typed (trimmed, as sent) password meets it.
  Widget _rulesChecklist(AppThemeConst t) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _new,
      builder: (context, value, _) {
        final p = value.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rule in _PasswordRule.all)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      rule.isMet(p)
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: rule.isMet(p)
                          ? const Color(0xFF1AA95A)
                          : t.cardSubtitleText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: rule.isMet(p)
                              ? const Color(0xFF1AA95A)
                              : t.cardSubtitleText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Issue 1: the web app's change-password rules (labels as the web shows them).
class _PasswordRule {
  final String label;
  final String message;
  final bool Function(String) isMet;
  const _PasswordRule(this.label, this.message, this.isMet);

  static final List<_PasswordRule> all = [
    _PasswordRule('Be at least 8 characters',
        'Password requires at least 8 characters.', (p) => p.length >= 8),
    _PasswordRule('At least one letter',
        'Password requires at least one letter.',
        (p) => RegExp(r'[A-Za-z]').hasMatch(p)),
    _PasswordRule('At least one number',
        'Password requires at least one number.',
        (p) => RegExp(r'[0-9]').hasMatch(p)),
    _PasswordRule('At least one capital letter',
        'Password requires at least one capital letter.',
        (p) => RegExp(r'[A-Z]').hasMatch(p)),
  ];
}
