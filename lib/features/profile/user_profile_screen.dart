import 'package:flutter/material.dart';

import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import 'change_password_screen.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final s = SessionService.instance;
    final empName = s.employeeName.trim().isNotEmpty ? s.employeeName.trim() : '-';
    final userName = s.username.trim().isNotEmpty ? s.username.trim() : '-';
    final machine =
        s.machineNumber.trim().isNotEmpty ? s.machineNumber.trim() : '-';
    final business =
        s.businessName.trim().isNotEmpty ? s.businessName.trim() : '-';
    final initial = empName != '-'
        ? empName[0].toUpperCase()
        : (business != '-' ? business[0].toUpperCase() : '?');

    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        title: const Text('User Profile'),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          children: [
            // ── Gradient header with avatar ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: t.headerGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: t.headerGradient.first.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 2),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(empName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(userName,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // ── Info card ───────────────────────────────────────────────────
            Container(
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
                children: [
                  _ProfileRow(
                      t: t,
                      icon: Icons.badge_outlined,
                      label: 'Employee Name',
                      value: empName),
                  _divider(t),
                  _ProfileRow(
                      t: t,
                      icon: Icons.person_outline,
                      label: 'User Name',
                      value: userName),
                  _divider(t),
                  _ProfileRow(
                      t: t,
                      icon: Icons.smartphone_outlined,
                      label: 'Machine Number',
                      value: machine),
                  _divider(t),
                  _ProfileRow(
                      t: t,
                      icon: Icons.business_outlined,
                      label: 'Business Name',
                      value: business),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // ── Change password tile ────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: t.cardShadowColor,
                      blurRadius: 14,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.lock_outline_rounded,
                              color: t.accent, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Change Password',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: t.cardHeadingText)),
                              const SizedBox(height: 2),
                              Text('Update your login password',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: t.cardSubtitleText)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: t.cardSubtitleText),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(AppThemeConst t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: t.dividerColor),
      );
}

class _ProfileRow extends StatelessWidget {
  final AppThemeConst t;
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow({
    required this.t,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: t.accent),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.cardSubtitleText,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: t.cardBodyText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
