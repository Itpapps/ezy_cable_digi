import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM BOTTOM NAVIGATION BAR
// Matches the grey/white style in the reference photo:
// white background, pill highlight on active icon, vivid blue active colour.
// ─────────────────────────────────────────────────────────────────────────────
class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// Bar height above the home indicator: the 60-px row + the 1-px top border.
  static const double height = 61;

  /// Labels follow the system text size only up to this factor, so a very
  /// large accessibility font cannot overflow the fixed 60-px bar.
  static const double maxLabelScale = 1.3;

  /// Dark-mode look. Off by default; only screens that opt in (via
  /// [MainFrame.dark]) use it.
  final bool dark;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
        icon: Iconsax.element_3,
        activeIcon: Iconsax.element_3,
        label: 'Dashboard',
      ),
      _NavItem(
        icon: Iconsax.message_question,
        activeIcon: Iconsax.message_question,
        label: 'Complaints',
      ),
      _NavItem(
        icon: Iconsax.graph,
        activeIcon: Iconsax.graph,
        label: 'Analytics',
      ),
      _NavItem(
        icon: Iconsax.wallet_3,
        activeIcon: Iconsax.wallet_3,
        label: 'Expenses',
      ),
    ];

    // Dark: all icons and labels white; the active tab keeps its pill + bold.
    final activeColor = dark ? Colors.white : AppColors.primary;
    final idleColor = dark ? Colors.white : Colors.grey.shade500;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111B30) : Colors.white,
        border: Border(
          top: BorderSide(
            color: dark ? const Color(0xFF1F2A44) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final active = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Icon with animated pill background ─────────────
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? activeColor.withValues(
                                    alpha: dark ? 0.18 : 0.12,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            items[i].icon,
                            size: 22,
                            color: active ? activeColor : idleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // ── Label ──────────────────────────────────────────
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: active ? activeColor : idleColor,
                          ),
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: maxLabelScale),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
