import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../widgets/main_frame.dart';
import '../constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// showPremiumDialog — generic wrapper that centres any widget as a premium dialog
// ─────────────────────────────────────────────────────────────────────────────
Future<T?> showPremiumDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (_, anim, __, w) {
      return ScaleTransition(
        // easeOutCubic = smooth scale-in with NO overshoot (easeOutBack bounced
        // past its size then snapped back, which read as a jump/lag).
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: FadeTransition(opacity: anim, child: w),
      );
    },
    pageBuilder: (ctx, _, __) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Material(
          color: Colors.transparent,
          child: child,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PremiumDialogShell — white rounded card + floating ✕ close button
// ─────────────────────────────────────────────────────────────────────────────
class PremiumDialogShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onClose;

  const PremiumDialogShell({super.key, required this.child, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
        // ── Floating ✕ button ────────────────────────────────────────────────
        Positioned(
          top: -13,
          right: -13,
          child: GestureDetector(
            onTap: onClose ?? () => Navigator.of(context).pop(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.close_rounded, size: 15, color: Colors.black54),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// showPremiumConfirm — confirm / cancel dialog with polished buttons
// Returns true if user confirmed, false/null otherwise.
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> showPremiumConfirm({
  required BuildContext context,
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.primary,
  bool isDanger = false,
}) async {
  // iOS 26 "liquid glass" confirm: frosted card, centred title/body, and two iOS
  // pill buttons (Cancel = soft grey, Confirm = filled brand colour, or iOS red
  // when destructive). API + return value unchanged: true only when Confirm tapped.
  final confirmFill = isDanger ? const Color(0xFFFF3B30) : confirmColor;
  final result = await showPremiumDialog<bool>(
    context: context,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              // Light blur (was 30) — cheap even on low-end GPUs; the higher card
              // opacity keeps the frosted look and a near-solid fallback.
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55), width: 1),
                ),
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black.withValues(alpha: 0.55),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _IosPillButton(
                            label: cancelLabel,
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _IosPillButton(
                            label: confirmLabel,
                            onTap: () => Navigator.of(context).pop(true),
                            fillColor: confirmFill,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return result == true;
}

// iOS-style pill button used by showPremiumConfirm. filled (fillColor set) = solid
// capsule + white text; otherwise a soft grey capsule with dark text (Cancel).
class _IosPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? fillColor;
  const _IosPillButton({required this.label, required this.onTap, this.fillColor});

  @override
  Widget build(BuildContext context) {
    final filled = fillColor != null;
    return Material(
      color: filled ? fillColor : Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// showPremiumLoading — centered loading overlay (not barrierDismissible)
// Call Navigator.of(context).pop() to dismiss.
// [canPop] false = Back is ignored while it shows (Android's non-cancellable
// ProgressDialog). Default true keeps every existing caller unchanged; use false
// only where the caller always closes the loader itself (A2: payment).
// ─────────────────────────────────────────────────────────────────────────────
void showPremiumLoading(BuildContext context,
    {String message = 'Loading, please wait...', bool canPop = true}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => PopScope(
      canPop: canPop,
      child: Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// showPremiumSnackBar — themed replacement for plain SnackBar
// ─────────────────────────────────────────────────────────────────────────────
void showPremiumSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
}) {
  final color = isError
      ? Colors.red.shade600
      : isSuccess
          ? Colors.green.shade600
          : AppColors.primary;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : isSuccess
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // Lifted above the screen's own bottom action bar inside a MainFrame
      // (0 everywhere else, i.e. the old 16-px margin).
      margin: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MainFrame.snackBarLiftOf(context)),
      elevation: 4,
      duration: const Duration(seconds: 3),
    ),
  );
}
