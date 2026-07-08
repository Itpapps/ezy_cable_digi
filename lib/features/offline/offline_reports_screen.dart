import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import 'miniday_report_screen.dart';
import 'offline_collections_report_screen.dart';

/// Offline Reports hub — Android parity (Offline_Reports_Home_Fragment): two
/// entries, Collections and Miniday. Kept lightweight (static gradient + cards,
/// no animations) so it stays smooth on low-end devices in offline mode.
class OfflineReportsScreen extends StatelessWidget {
  const OfflineReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Gradient header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bar_chart_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Offline Reports',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('Collections & Miniday summary',
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
            const SizedBox(height: 20),
            _reportCard(
              context,
              t,
              title: 'Collections',
              subtitle: 'Offline collection summary',
              icon: Icons.receipt_long_rounded,
              tint: const Color(0xFF2E7D32),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OfflineCollectionsReportScreen(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _reportCard(
              context,
              t,
              title: 'Miniday Report',
              subtitle: 'Day-wise collection report',
              icon: Icons.today_rounded,
              tint: const Color(0xFF1565C0),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MinidayReportScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(
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
