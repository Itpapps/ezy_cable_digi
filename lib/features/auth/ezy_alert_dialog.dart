import 'package:flutter/material.dart';

/// Ezy (CloudDigi) start-up / registration UI pieces. Presentation only:
/// used by EzyStartGate and DeviceRegistrationScreen (KCCL never opens them).

enum EzyAlertType { error, warning, success }

const Color _navy = Color(0xFF0B1F4D);
const Color _body = Color(0xFF4B5563);

Color _colorOf(EzyAlertType t) => switch (t) {
      EzyAlertType.error => const Color(0xFFD32F2F),
      EzyAlertType.warning => const Color(0xFFEF6C00),
      EzyAlertType.success => const Color(0xFF2E7D32),
    };

IconData _iconOf(EzyAlertType t) => switch (t) {
      EzyAlertType.error => Icons.gpp_maybe_rounded,
      EzyAlertType.warning => Icons.error_outline_rounded,
      EzyAlertType.success => Icons.check_circle_rounded,
    };

/// Shows the styled alert. Returns true when OK was pressed, false when it
/// was closed another way (X / tap outside — only possible if [dismissible]).
/// [dismissible] keeps the exact behaviour of the old AlertDialog: when false
/// there is no X, no tap-outside and no back-button close.
Future<bool> showEzyAlert(
  BuildContext context, {
  required String title,
  required String message,
  EzyAlertType type = EzyAlertType.error,
  IconData? icon,
  bool dismissible = false,
}) async {
  final pressed = await showDialog<bool>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => PopScope(
      canPop: dismissible,
      child: _EzyAlert(
        title: title,
        message: message,
        color: _colorOf(type),
        icon: icon ?? _iconOf(type),
        dismissible: dismissible,
      ),
    ),
  );
  return pressed ?? false;
}

/// Non-dismissible "please wait" dialog. Close it with
/// `Navigator.of(context, rootNavigator: true).pop()`.
void showEzyProgress(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          child: Row(
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.8, color: Color(0xFF1565C0)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EzyAlert extends StatelessWidget {
  const _EzyAlert({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    required this.dismissible,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    const radius = 24.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EzyWave(color: color, height: 72),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBadge(icon: icon, color: color),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          color: _body,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _PillButton(
                        label: 'OK',
                        color: color,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ),
                if (dismissible)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF374151),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.07),
      ),
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.14),
        ),
        child: Icon(icon, size: 38, color: color),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return SizedBox(
      width: 180,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.lerp(color, Colors.white, 0.15)!, color],
          ),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two soft waves along the bottom edge of a card (decoration only).
class EzyWave extends StatelessWidget {
  const EzyWave({super.key, required this.color, this.height = 72});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _WavePainter(color)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final back = Path()
      ..moveTo(0, h * 0.30)
      ..quadraticBezierTo(w * 0.25, h * 0.02, w * 0.5, h * 0.42)
      ..quadraticBezierTo(w * 0.75, h * 0.82, w, h * 0.22)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = color.withValues(alpha: 0.07));

    final front = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.30, h * 0.28, w * 0.55, h * 0.70)
      ..quadraticBezierTo(w * 0.80, h * 1.02, w, h * 0.52)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = color.withValues(alpha: 0.11));
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}
