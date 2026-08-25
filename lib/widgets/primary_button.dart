import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';

/// Primary action button — keeps its ORIGINAL filled colour (AppColors.accent),
/// with a green light that sweeps once around the border on tap (like the
/// offline Sync button).
///
/// Presentation only. Login behaviour unchanged: [onPressed] fires on tap and
/// [isLoading] shows the spinner + blocks taps.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleTap() {
    // Preserve the original guard: no-op while loading or when disabled.
    if (widget.isLoading || widget.onPressed == null) return;
    _c.forward(from: 0); // one green light sweep around the border
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = AppColors.primary; // button + sweep colour (brand blue)
    const radius = 16.0;
    const borderW = 1.8;
    final enabled = widget.onPressed != null && !widget.isLoading;

    // The button itself — unchanged colour (AppColors.accent) + white content.
    final inner = Container(
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: BorderRadius.circular(radius - borderW),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? _handleTap : null,
          borderRadius: BorderRadius.circular(radius - borderW),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.paddingM),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: Opacity(
        opacity: (widget.onPressed == null && !widget.isLoading) ? 0.6 : 1,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            // The green sweep ring wraps AROUND the button (border + glow only).
            return Container(
              padding: const EdgeInsets.all(borderW),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: _c.isDismissed ? accentColor : null,
                gradient: _c.isDismissed
                    ? null
                    : SweepGradient(
                        transform: GradientRotation(_c.value * 2 * math.pi),
                        colors: const [
                          accentColor,
                          accentColor,
                          Colors.white,
                          accentColor,
                          accentColor
                        ],
                        stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
                      ),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: inner,
        ),
      ),
    );
  }
}
