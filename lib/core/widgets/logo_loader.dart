import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Loader with the app logo in the middle and a spinning ring around it,
/// used in place of a plain [CircularProgressIndicator].
///
///   if (_loading) return const Center(child: LogoLoader());
class LogoLoader extends StatefulWidget {
  /// Outer size of the ring.
  final double size;

  /// Ring colour. Defaults to the theme's primary colour.
  final Color? color;

  const LogoLoader({super.key, this.size = 72, this.color});

  /// Logo for the current flavor (same as the top bar). Falls back to the
  /// Magik logo if [AppConfig.instance] is not ready (e.g. after hot reload).
  static String get logoAsset {
    try {
      return AppConfig.instance.flavor == Flavor.magik
          ? 'assets/mainlogo.png'
          : 'assets/ezy_digi_pics.png';
    } catch (_) {
      return 'assets/mainlogo.png';
    }
  }

  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader>
    with SingleTickerProviderStateMixin {
  // Gentle "breathing" of the logo while the ring spins.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final size = widget.size;
    final stroke = size * 0.05;
    final logoSize = size - stroke * 2 - size * 0.14;

    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Faint full track behind the spinning arc.
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: stroke,
                color: color.withValues(alpha: 0.15),
              ),
            ),
            SizedBox.expand(
              child: CircularProgressIndicator(
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                color: color,
              ),
            ),
            ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(LogoLoader.logoAsset, fit: BoxFit.cover),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
