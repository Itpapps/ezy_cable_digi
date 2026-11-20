import 'package:flutter/material.dart';

import '../../core/data/customer.dart';
import '../../core/theme/theme_constants.dart';
import 'custom_packages_activation_screen.dart';
import 'custom_packages_deactivation_screen.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Custom Packages hub — Android parity (`DigiPackage_Home`): two actions,
/// Activate and Deactivate, each opening a multi-select package cart.
///
/// Phase C step 1 (foundation): the hub + tile + `getDigiDealerPackages` repo.
/// The Activation (cart → BillDetails → `insertDigiDealerPackages`) and
/// Deactivation flows are wired in steps 2 and 3.
class CustomPackagesHomeScreen extends StatelessWidget {
  final Customer customer;
  const CustomPackagesHomeScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 40, // compact, same as Customer / Payment Details
        title: const Text('Custom Packages',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Gradient header (customer context) — compact: the title bar
            // above already says "Custom Packages".
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.widgets_outlined,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Custom Packages',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          customer.name.trim().isEmpty
                              ? 'Manage packages'
                              : customer.name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _actionCard(
              context,
              t,
              title: 'Activate Packages',
              subtitle: 'Add packages to this customer',
              icon: Icons.add_box_rounded,
              tint: const Color(0xFF2E7D32),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomPackagesActivationScreen(customer: customer),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _actionCard(
              context,
              t,
              title: 'Deactivate Packages',
              subtitle: 'Remove packages from this customer',
              icon: Icons.indeterminate_check_box_rounded,
              tint: const Color(0xFFD32F2F),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomPackagesDeactivationScreen(customer: customer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context,
    AppThemeConst t, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return Container(
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tint, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: t.cardHeadingText)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: t.cardSubtitleText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.cardSubtitleText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
