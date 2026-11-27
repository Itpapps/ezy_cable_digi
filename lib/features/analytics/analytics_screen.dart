import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/services/error_handler_service.dart';
import '../../core/theme/theme_constants.dart';
import '../dashboard/data/dashboard_repository.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  /// Load sequence (0 → 1): cards reveal, donut and bar fill, amounts count
  /// up. Starts once the KPIs are loaded.
  late AnimationController _ctrl;

  // Presentation only (never changes any amount): the glowing dot's pulse,
  // the Outstanding / Collection split that the donut dot and the
  // progress-bar knob can be dragged along (both spring back), and the
  // donut's 3D rotation in radians about the X and Y axes.
  late final AnimationController _pulse;
  late final AnimationController _split;
  late final AnimationController _rotX;
  late final AnimationController _rotY;

  double outstanding = 0;
  double collection = 0;
  bool _loading = true;
  bool _error = false;

  // Segment colours (orange = Outstanding, purple = Collection).
  static const Color _orange = Color(0xFFFF6A00);
  static const Color _purple = Color(0xFF7C3AED);
  static const List<Color> _orangeGrad = [Color(0xFFFFB547), _orange];
  static const List<Color> _purpleGrad = [Color(0xFFA855F7), _purple];
  static const Color _amountText = Color(0xFF1A3C6E);

  /// Resting pose: tipped back a little so the ring's thickness shows.
  static const double _restTilt = -0.28;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _split = AnimationController.unbounded(vsync: this);
    _rotX = AnimationController.unbounded(vsync: this, value: _restTilt);
    _rotY = AnimationController.unbounded(vsync: this);
    _loadKpis();
  }

  Future<void> _loadKpis() async {
    try {
      final r = await DashboardRepository.instance.fetchKpis();
      if (r.isSuccess) {
        outstanding = r.outstandingAmount;
        collection = r.collectionAmount;
      }
    } catch (e, s) {
      _error = true;
      ErrorHandlerService.recordError(e, s,
          reason: 'AnalyticsScreen._loadKpis');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _split.value = _visualSplit;
        _ctrl.forward();
        _pulse.repeat(reverse: true);
        // One full 3D turn as the donut appears.
        _rotY.animateWith(SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 30, damping: 9),
          -2 * pi,
          0,
          0,
        ));
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulse.dispose();
    _split.dispose();
    _rotX.dispose();
    _rotY.dispose();
    super.dispose();
  }

  // ── Animation helpers (presentation only) ─────────────────────────────────

  /// Eased 0 → 1 progress of the [a]–[b] slice of the load sequence.
  double _phase(double a, double b) =>
      Interval(a, b, curve: Curves.easeOutCubic).transform(_ctrl.value);

  /// Orange (Outstanding) share. Display only: a tiny share is widened to
  /// 4 % so both colours stay visible — the amounts stay exact.
  double get _visualSplit {
    final total = outstanding + collection;
    if (total <= 0) return 0;
    final s = (outstanding / total).clamp(0.0, 1.0);
    if (outstanding > 0 && collection > 0) return s.clamp(0.04, 0.96);
    return s;
  }

  /// Released (donut dot or bar knob) → springs back to the real split.
  void _springBack(double velocity) {
    _split.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 180, damping: 14),
      _split.value,
      _visualSplit,
      velocity.clamp(-3.0, 3.0),
    ));
  }

  // 3D rotation: drag inside the donut in any direction to turn it a full
  // 360°; a flick keeps it spinning, then it settles facing front.
  void _spinGrab() {
    _rotX.stop();
    _rotY.stop();
  }

  void _spinDrag(Offset delta, double d) {
    final k = 2 / d; // radians per pixel
    _rotX.value += delta.dy * k;
    _rotY.value += delta.dx * k;
  }

  void _spinRelease(Offset velocity, double d) {
    final k = 2 / d;
    _settle(_rotX, _restTilt, velocity.dy * k);
    _settle(_rotY, 0, velocity.dx * k);
  }

  /// Springs [c] to the nearest full turn of [rest], carrying the flick.
  void _settle(AnimationController c, double rest, double velocity) {
    const turn = 2 * pi;
    final v = velocity.clamp(-30.0, 30.0);
    final target =
        rest + ((c.value + v * 0.3 - rest) / turn).roundToDouble() * turn;
    c.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 50, damping: 10),
      c.value,
      target,
      v,
    ));
  }

  // Ring geometry — shared by the painters, the touch areas and the drag.
  static double _ringStroke(double d) => (d * 0.09).clamp(16.0, 26.0);
  static double _ringPad(double stroke) => stroke * 0.8;
  static double _ringRadius(double d) {
    final stroke = _ringStroke(d);
    return d / 2 - stroke / 2 - _ringPad(stroke);
  }

  /// Position on the ring: 0 at the top, growing anticlockwise (the way
  /// the orange fills).
  static double _ringT(Offset local, double d) {
    final v = local - Offset(d / 2, d / 2);
    return ((-pi / 2 - atan2(v.dy, v.dx)) / (2 * pi)) % 1.0;
  }

  /// A touch that starts on the ring moves the dot.
  static bool _onRing(Offset local, double d) {
    final dist = (local - Offset(d / 2, d / 2)).distance;
    return (dist - _ringRadius(d)).abs() <= max(_ringStroke(d) * 1.1, 24.0);
  }

  /// A touch inside the donut (off the ring) turns it.
  static bool _inDonut(Offset local, double d) =>
      (local - Offset(d / 2, d / 2)).distance <= d / 2 && !_onRing(local, d);

  /// Glowing dot follows the finger around the ring.
  void _ringDrag(Offset local, double d, {bool jump = false}) {
    var t = _ringT(local, d);
    final cur = _split.value.clamp(0.0, 1.0);
    // No wrapping across the top while dragging: stop at the start / end.
    if (!jump && (t - cur).abs() > 0.5) t = cur > 0.5 ? 1.0 : 0.0;
    _split.value = t; // setting value stops a running spring
  }

  void _ringRelease(Offset velocity, double d) {
    final a = -pi / 2 - _split.value * 2 * pi;
    final along = velocity.dx * sin(a) - velocity.dy * cos(a);
    _springBack(along / (2 * pi * _ringRadius(d)));
  }

  // Progress bar: purple (Collection) runs from the left = 1 − split.
  void _barDrag(double dx, double w) {
    if (w <= 0) return;
    _split.value = 1 - (dx / w).clamp(0.0, 1.0);
  }

  void _barRelease(double vx, double w) {
    if (w <= 0) return;
    _springBack(-vx / w);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);

    return Scaffold(
      backgroundColor: t.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page heading (was the grey AppBar — same "Analytics" title; the
          // bar had no buttons, so nothing else depended on it).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Analytics',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: t.headingText,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: t.loadingColor))
                : _error && outstanding == 0 && collection == 0
                    ? Center(
                        child: Text('Could not load analytics data',
                            style: TextStyle(
                                color: t.subtitleText,
                                fontWeight: FontWeight.w600)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _reveal(0.0, 0.45, _heroCard()),
                            const SizedBox(height: 14),
                            _reveal(0.15, 0.6, _splitCard(t)),
                            const SizedBox(height: 14),
                            // Collection / Outstanding tiles — equal height
                            // side by side.
                            _reveal(
                              0.3,
                              0.8,
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _statTile(
                                        t,
                                        label: 'Collection',
                                        amount: collection,
                                        icon: Icons.currency_rupee_rounded,
                                        colors: _purpleGrad,
                                        tint: const Color(0xFFF4ECFF),
                                        amountColor: const Color(0xFF6D28D9),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _statTile(
                                        t,
                                        label: 'Outstanding',
                                        amount: outstanding,
                                        icon: Icons.hourglass_bottom_rounded,
                                        colors: _orangeGrad,
                                        tint: const Color(0xFFFFF3E6),
                                        amountColor: const Color(0xFFC2410C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Staggered fade + slide-up as the load sequence runs.
  Widget _reveal(double a, double b, Widget child) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: child,
      builder: (context, child) {
        final v = _phase(a, b);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 18),
            child: child,
          ),
        );
      },
    );
  }

  /// "₹2683.00" → bold "₹2683" + smaller ".00". Text is unchanged.
  static TextSpan _amountSpan(String amount) {
    const big = TextStyle(
      fontSize: 32,
      color: Colors.white,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    final dot = amount.lastIndexOf('.');
    if (dot <= 0 || dot == amount.length - 1) {
      return TextSpan(text: amount, style: big);
    }
    return TextSpan(
      style: big,
      children: [
        TextSpan(text: amount.substring(0, dot)),
        TextSpan(
          text: amount.substring(dot),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration(AppThemeConst t) => BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: t.isLight ? Border.all(color: t.dividerColor) : null,
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );

  // Hero — 3D donut (orange = Outstanding share, purple = Collection
  // share). Drag on the ring → the glowing dot moves; drag inside it → the
  // donut turns 360° in 3D. Both spring back. The TV icon, "Collections
  // Overview" and the collected amount (counting up) float inside.
  Widget _heroCard() {
    const radius = 24.0;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2F4FD0), Color(0xFF5B5FEF)],
          stops: [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            // Soft wave along the bottom (decoration only).
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 90,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WavePainter(Colors.white, 0.06, 0.10),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final d = min(c.maxWidth, 280.0);
                  final stroke = _ringStroke(d);
                  // Text box that fits inside the ring; scales down as a
                  // whole on large font sizes so it never spills onto it.
                  final inner = (_ringRadius(d) - stroke / 2) * 2 * 0.8;
                  final content = SizedBox(
                    width: inner,
                    height: inner * 0.9,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: inner,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.connected_tv_rounded,
                              size: 38,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Collections Overview',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Counts up to the exact collected amount.
                            AnimatedBuilder(
                              animation: _ctrl,
                              builder: (context, _) => FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text.rich(
                                  _amountSpan(
                                    '₹${(collection * _phase(0.1, 0.8)).toStringAsFixed(2)}',
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            Text(
                              'Collected',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  return Center(
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      gestures: <Type, GestureRecognizerFactory>{
                        _RingDragRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                _RingDragRecognizer>(
                          () => _RingDragRecognizer(debugOwner: this),
                          (g) => g
                            ..accept = ((p) => _onRing(p, d))
                            ..onStart =
                                ((e) => _ringDrag(e.localPosition, d, jump: true))
                            ..onUpdate = ((e) => _ringDrag(e.localPosition, d))
                            ..onEnd = ((e) =>
                                _ringRelease(e.velocity.pixelsPerSecond, d))
                            ..onCancel = (() => _ringRelease(Offset.zero, d)),
                        ),
                        _SpinRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                _SpinRecognizer>(
                          () => _SpinRecognizer(debugOwner: this),
                          (g) => g
                            ..accept = ((p) => _inDonut(p, d))
                            ..onStart = ((_) => _spinGrab())
                            ..onUpdate = ((e) => _spinDrag(e.delta, d))
                            ..onEnd = ((e) =>
                                _spinRelease(e.velocity.pixelsPerSecond, d))
                            ..onCancel = (() => _spinRelease(Offset.zero, d)),
                        ),
                      },
                      child: SizedBox(
                        width: d,
                        height: d,
                        child: _donut3D(stroke, content),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The donut as real 3D layers — back face, a stack of edge slices and
  /// the front face — each at its own depth, turned together with
  /// perspective. Layers are drawn far-to-near, so the order flips when the
  /// back faces the viewer. The text floats just above whichever face shows.
  Widget _donut3D(double stroke, Widget content) {
    final pad = _ringPad(stroke);
    final half = stroke * 0.4; // half the ring's thickness
    const slices = 12;
    final show = outstanding + collection > 0;

    return AnimatedBuilder(
      animation: Listenable.merge([_rotX, _rotY]),
      builder: (context, _) {
        final ax = _rotX.value;
        final ay = _rotY.value;
        final facing = cos(ax) * cos(ay) >= 0;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX(ax)
          ..rotateY(ay);

        Widget layer(String key, double z, Widget child, [Matrix4? flip]) {
          final t = m.clone()..multiply(Matrix4.translationValues(0.0, 0.0, z));
          if (flip != null) t.multiply(flip);
          return Positioned.fill(
            key: ValueKey(key),
            child: Transform(
              alignment: Alignment.center,
              transform: t,
              child: child,
            ),
          );
        }

        final layers = <Widget>[
          // Seen from behind: the text reads the right way round there too.
          if (!facing)
            layer(
              'backText',
              half + 6,
              Center(child: content),
              cos(ay) < 0 ? Matrix4.rotationY(pi) : Matrix4.rotationX(pi),
            ),
          layer(
            'back',
            half,
            RepaintBoundary(
              child: CustomPaint(
                painter: _RingFacePainter(
                  load: _ctrl,
                  split: _split,
                  stroke: stroke,
                  pad: pad,
                  showSegments: show,
                ),
              ),
            ),
          ),
          for (var i = 1; i < slices; i++)
            layer(
              'slice$i',
              half - 2 * half * i / slices,
              RepaintBoundary(
                child: CustomPaint(
                  painter: _RingSlicePainter(
                    load: _ctrl,
                    split: _split,
                    stroke: stroke,
                    pad: pad,
                    shade: 1 - i / slices,
                    showSegments: show,
                  ),
                ),
              ),
            ),
          layer(
            'front',
            -half,
            RepaintBoundary(
              child: CustomPaint(
                painter: _RingFacePainter(
                  load: _ctrl,
                  split: _split,
                  pulse: _pulse,
                  glass: true,
                  stroke: stroke,
                  pad: pad,
                  showSegments: show,
                ),
              ),
            ),
          ),
          if (facing) layer('frontText', -half - 6, Center(child: content)),
        ];
        return Stack(
          clipBehavior: Clip.none,
          children: facing ? layers : layers.reversed.toList(),
        );
      },
    );
  }

  // Split card — Collection (left) / Outstanding (right) amounts over one
  // bar: purple = Collection share, orange = Outstanding share. The bar
  // fills on load; its knob can be dragged sideways and springs back.
  Widget _splitCard(AppThemeConst t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: _cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _splitLegend(t, 'Collection', collection, _purple,
                    alignEnd: false),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _splitLegend(t, 'Outstanding', outstanding, _orange,
                    alignEnd: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              // Horizontal drag only, so the page still scrolls vertically.
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (e) => _barDrag(e.localPosition.dx, w),
                onHorizontalDragUpdate: (e) => _barDrag(e.localPosition.dx, w),
                onHorizontalDragEnd: (e) =>
                    _barRelease(e.velocity.pixelsPerSecond.dx, w),
                onHorizontalDragCancel: () => _barRelease(0, w),
                child: SizedBox(
                  height: 34, // taller than the bar → easier to grab
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SplitBarPainter(
                        load: _ctrl,
                        split: _split,
                        trackColor: const Color(0xFFEEF0F8),
                        showSegments: outstanding + collection > 0,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _splitLegend(
    AppThemeConst t,
    String label,
    double amount,
    Color color, {
    required bool alignEnd,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.cardSubtitleText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              '₹${(amount * _phase(0.25, 0.85)).toStringAsFixed(2)}',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _amountText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Stat tile — gradient icon badge on top, label, amount that counts up to
  // the exact value. FittedBox keeps a very large amount within the tile.
  Widget _statTile(
    AppThemeConst t, {
    required String label,
    required double amount,
    required IconData icon,
    required List<Color> colors,
    required Color tint,
    required Color amountColor,
  }) {
    const radius = 20.0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.cardBg, tint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: t.isLight ? Border.all(color: t.dividerColor) : null,
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 46,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WavePainter(colors.last, 0.08, 0.12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: colors.last.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.cardBodyText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '₹${(amount * _phase(0.35, 0.95)).toStringAsFixed(2)}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: amountColor,
                        ),
                      ),
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
}

/// Pan that claims a touch at once when [accept] says it started in its
/// area (so the page doesn't scroll meanwhile) and ignores every other
/// touch (so the page scrolls as normal).
class _EagerPanRecognizer extends PanGestureRecognizer {
  _EagerPanRecognizer({super.debugOwner});

  bool Function(Offset local)? accept;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (accept?.call(event.localPosition) ?? false) &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Touch on the ring → moves the glowing dot.
class _RingDragRecognizer extends _EagerPanRecognizer {
  _RingDragRecognizer({super.debugOwner});
}

/// Touch inside the donut (off the ring) → turns the donut in 3D.
class _SpinRecognizer extends _EagerPanRecognizer {
  _SpinRecognizer({super.debugOwner});
}

/// One face of the donut: empty groove, orange (Outstanding) from the top
/// running anticlockwise up to [split], purple (Collection) for the rest,
/// with glow, tube shading and top-left light. The front face also has the
/// glass centre ([glass]) and the pulsing glowing ball ([pulse]).
class _RingFacePainter extends CustomPainter {
  _RingFacePainter({
    required this.load,
    required this.split,
    this.pulse,
    this.glass = false,
    required this.stroke,
    required this.pad,
    required this.showSegments,
  }) : super(repaint: Listenable.merge([load, split, pulse]));

  final Animation<double> load;
  final Animation<double> split;
  final Animation<double>? pulse;
  final bool glass;
  final double stroke;
  final double pad;
  final bool showSegments;

  static const Color _orangeA = Color(0xFFFFC24D);
  static const Color _orangeB = Color(0xFFFF7A00);
  static const Color _purpleA = Color(0xFFC084FC);
  static const Color _purpleB = Color(0xFF8B5CF6);
  static const Color _shadow = Color(0xFF0B1240);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke / 2 - pad;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = const Interval(0.1, 0.8, curve: Curves.easeOutCubic)
        .transform(load.value);
    final s = split.value.clamp(0.0, 1.0);

    Paint line({Color? color, Shader? shader, double blur = 0}) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      if (shader != null) paint.shader = shader;
      if (color != null) paint.color = color;
      if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      return paint;
    }

    // 0 = top, anticlockwise.
    void arc(double from, double to, Paint paint) {
      if (to - from > 0.001) {
        canvas.drawArc(rect, -pi / 2 - from * 2 * pi,
            -(to - from) * 2 * pi, false, paint);
      }
    }

    final orangeEnd = min(p, s);
    final hasPurple = showSegments && p > s;
    // Filled part of the ring (orange, then purple) — 0 … filledEnd.
    final filledEnd = !showSegments ? 0.0 : (hasPurple ? p : orangeEnd);

    if (glass) {
      // Glass centre, with a soft inner shadow so it sits below the ring.
      final inner = r - stroke / 2;
      canvas.drawCircle(
        c,
        inner,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFF1E2A78).withValues(alpha: 0.10),
            const Color(0xFF1E2A78).withValues(alpha: 0.45),
          ]).createShader(Rect.fromCircle(center: c, radius: inner)),
      );
      canvas.drawCircle(
        c,
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.5
          ..color = _shadow.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.35),
      );
    }

    // Empty groove (track).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    if (filledEnd > 0.001) {
      // Soft coloured glow.
      if (hasPurple) {
        arc(s, p,
            line(color: _purpleB.withValues(alpha: 0.35), blur: stroke * 0.6));
      }
      arc(0, orangeEnd,
          line(color: _orangeB.withValues(alpha: 0.35), blur: stroke * 0.6));

      // Faces (purple first so the orange cap sits on top at the join,
      // under the dot).
      if (hasPurple) {
        arc(
          s,
          p,
          line(
            shader: const LinearGradient(
              colors: [_purpleA, _purpleB],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(rect),
          ),
        );
      }
      arc(
        0,
        orangeEnd,
        line(
          shader: const LinearGradient(
            colors: [_orangeA, _orangeB],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect),
        ),
      );

      // Tube shading across the ring (dark edges, bright band) plus light
      // from the top-left — drawn once over the whole filled part.
      final outer = Rect.fromCircle(center: c, radius: r + stroke / 2);
      final e = (r - stroke / 2) / (r + stroke / 2);
      final tube = RadialGradient(
        colors: [
          Colors.black.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.28),
        ],
        stops: [
          e,
          e + (1 - e) * 0.35,
          e + (1 - e) * 0.5,
          e + (1 - e) * 0.7,
          1.0,
        ],
      ).createShader(outer);
      final light = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.16),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(outer);
      if (filledEnd >= 0.999) {
        // Full ring: a circle avoids doubled caps at the top.
        final full = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke;
        canvas.drawCircle(c, r, full..shader = tube);
        canvas.drawCircle(c, r, full..shader = light);
      } else {
        arc(0, filledEnd, line(shader: tube));
        arc(0, filledEnd, line(shader: light));
      }
    }

    final pulse = this.pulse;
    if (pulse == null) return;

    // Glowing ball at the split (rides the fill head while loading).
    final dotT = showSegments ? orangeEnd : 0.0;
    final a = -pi / 2 - dotT * 2 * pi;
    final pos = c + Offset(cos(a), sin(a)) * r;
    final fade = (load.value * 4).clamp(0.0, 1.0);
    final pv = pulse.value;
    final ball = stroke * 0.42;
    canvas.drawCircle(
      pos + Offset(0, stroke * 0.3),
      ball,
      Paint()
        ..color = _shadow.withValues(alpha: 0.35 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.2),
    );
    canvas.drawCircle(
      pos,
      stroke * (0.85 + 0.35 * pv),
      Paint()
        ..color = Colors.white.withValues(alpha: (0.32 - 0.18 * pv) * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.45),
    );
    canvas.drawCircle(
      pos,
      stroke * 0.7,
      Paint()
        ..color = const Color(0xFFFFE8B0).withValues(alpha: 0.5 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.3),
    );
    // Lit sphere: highlight top-left, warm shade bottom-right.
    canvas.drawCircle(
      pos,
      ball,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: fade),
            const Color(0xFFFFF3D9).withValues(alpha: fade),
            const Color(0xFFE2B866).withValues(alpha: fade),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: ball)),
    );
  }

  @override
  bool shouldRepaint(_RingFacePainter old) =>
      old.load != load ||
      old.split != split ||
      old.pulse != pulse ||
      old.glass != glass ||
      old.stroke != stroke ||
      old.pad != pad ||
      old.showSegments != showSegments;
}

/// One slice of the ring's edge (between the two faces): the coloured parts
/// in darker shades — [shade] 0 = next to the front face, 1 = next to the
/// back face. Stacked, the slices form the ring's solid side.
class _RingSlicePainter extends CustomPainter {
  _RingSlicePainter({
    required this.load,
    required this.split,
    required this.stroke,
    required this.pad,
    required this.shade,
    required this.showSegments,
  }) : super(repaint: Listenable.merge([load, split]));

  final Animation<double> load;
  final Animation<double> split;
  final double stroke;
  final double pad;
  final double shade;
  final bool showSegments;

  static const Color _orangeNear = Color(0xFFE06A00);
  static const Color _orangeFar = Color(0xFF8A3A00);
  static const Color _purpleNear = Color(0xFF6D28D9);
  static const Color _purpleFar = Color(0xFF3B1478);

  @override
  void paint(Canvas canvas, Size size) {
    if (!showSegments) return;
    final r = size.width / 2 - stroke / 2 - pad;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final p = const Interval(0.1, 0.8, curve: Curves.easeOutCubic)
        .transform(load.value);
    final s = split.value.clamp(0.0, 1.0);
    final orangeEnd = min(p, s);

    void arc(double from, double to, Color color) {
      if (to - from > 0.001) {
        canvas.drawArc(
          rect,
          -pi / 2 - from * 2 * pi,
          -(to - from) * 2 * pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      }
    }

    if (p > s) arc(s, p, Color.lerp(_purpleNear, _purpleFar, shade)!);
    arc(0, orangeEnd, Color.lerp(_orangeNear, _orangeFar, shade)!);
  }

  @override
  bool shouldRepaint(_RingSlicePainter old) =>
      old.load != load ||
      old.split != split ||
      old.stroke != stroke ||
      old.pad != pad ||
      old.shade != shade ||
      old.showSegments != showSegments;
}

/// One rounded bar: purple (Collection) pill from the left up to 1 − split
/// with a soft glow, orange (Outstanding) for the rest. Fills on load.
class _SplitBarPainter extends CustomPainter {
  _SplitBarPainter({
    required this.load,
    required this.split,
    required this.trackColor,
    required this.showSegments,
  }) : super(repaint: Listenable.merge([load, split]));

  final Animation<double> load;
  final Animation<double> split;
  final Color trackColor;
  final bool showSegments;

  static const double _h = 14;
  static const Color _orangeA = Color(0xFFFFB547);
  static const Color _orangeB = Color(0xFFFF7A00);
  static const Color _purpleA = Color(0xFFC084FC);
  static const Color _purpleB = Color(0xFF7C3AED);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final top = (size.height - _h) / 2;
    const rad = Radius.circular(_h / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(0, top, w, top + _h, rad),
      Paint()..color = trackColor,
    );
    if (!showSegments) return;

    final g = const Interval(0.25, 0.85, curve: Curves.easeOutCubic)
        .transform(load.value);
    final s = split.value.clamp(0.0, 1.0);
    final join = (1 - s) * w; // purple | orange
    final head = g * w; // fill head while loading

    var purpleW = min(join, head);
    final hasPurple = purpleW > 0.5;
    if (hasPurple) purpleW = max(purpleW, _h); // at least a round knob

    // Orange — starts under the purple's round end, runs to the fill head.
    final orangeL = hasPurple ? max(0.0, purpleW - _h / 2) : 0.0;
    if (head > orangeL + 0.5 && head > join) {
      final r = Rect.fromLTRB(orangeL, top, head, top + _h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, rad),
        Paint()
          ..shader = const LinearGradient(colors: [_orangeA, _orangeB])
              .createShader(r),
      );
    }

    if (hasPurple) {
      final r = Rect.fromLTRB(0, top, purpleW, top + _h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(1), rad),
        Paint()
          ..color = _purpleB.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, rad),
        Paint()
          ..shader = const LinearGradient(colors: [_purpleA, _purpleB])
              .createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_SplitBarPainter old) =>
      old.load != load ||
      old.split != split ||
      old.trackColor != trackColor ||
      old.showSegments != showSegments;
}

/// Soft two-layer wave (decoration only).
class _WavePainter extends CustomPainter {
  const _WavePainter(this.color, this.backAlpha, this.frontAlpha);

  final Color color;
  final double backAlpha;
  final double frontAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(0, h * 0.75)
      ..quadraticBezierTo(w * 0.45, h * 0.05, w * 0.70, h * 0.45)
      ..quadraticBezierTo(w * 0.85, h * 0.70, w, h * 0.30)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = color.withValues(alpha: backAlpha));
    final front = Path()
      ..moveTo(0, h * 0.95)
      ..quadraticBezierTo(w * 0.50, h * 0.35, w * 0.78, h * 0.70)
      ..quadraticBezierTo(w * 0.90, h * 0.85, w, h * 0.60)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        front, Paint()..color = color.withValues(alpha: frontAlpha));
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color ||
      old.backAlpha != backAlpha ||
      old.frontAlpha != frontAlpha;
}
