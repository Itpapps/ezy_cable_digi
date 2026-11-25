import 'dart:math';
import 'package:flutter/material.dart';

import '../../core/services/error_handler_service.dart';
import '../../core/theme/theme_constants.dart';
import '../dashboard/data/dashboard_repository.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  double outstanding = 0;
  double collection = 0;
  bool _loading = true;
  bool _error = false;

  // Segment colours (orange = Outstanding, purple = Collection).
  static const Color _orange = Color(0xFFFF6A00);
  static const Color _purple = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _anim = CurveTween(curve: Curves.easeOutCubic).animate(_ctrl);
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
        _ctrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final double total = outstanding + collection;
    final double outPct = total == 0 ? 0 : outstanding / total;

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
                            _heroCard(outPct),
                            const SizedBox(height: 12),
                            // Outstanding / Collection tiles — same labels and
                            // full amounts; equal height side by side.
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _statTile(
                                      t,
                                      label: 'Outstanding',
                                      amount: outstanding,
                                      icon: Icons.hourglass_bottom_rounded,
                                      colors: const [
                                        Color(0xFFFFA23D),
                                        _orange,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _statTile(
                                      t,
                                      label: 'Collection',
                                      amount: collection,
                                      icon: Icons.currency_rupee_rounded,
                                      colors: const [
                                        Color(0xFFA855F7),
                                        _purple,
                                      ],
                                    ),
                                  ),
                                ],
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

  /// "₹2683.00" → bold "₹2683" + smaller ".00". Text is unchanged.
  static TextSpan _amountSpan(String amount) {
    const big = TextStyle(
      fontSize: 28,
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
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  // Hero card — "Collections Overview" + collected amount (as the old donut
  // centre) + the same animated donut, compact on the right.
  Widget _heroCard(double outPct) {
    const radius = 22.0;
    const double donut = 104;
    const double stroke = donut * 0.15;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Collections Overview',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    _amountSpan('₹${collection.toStringAsFixed(2)}'),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Collected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Same donut + animation as before (orange = Outstanding,
          // purple = Collection) on a soft glass disc.
          Container(
            width: donut + 8,
            height: donut + 8,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, child) => CustomPaint(
                painter: _DoughnutChartPainter(
                  progress: _anim.value,
                  outstandingPct: outPct,
                  strokeWidth: stroke,
                  outColor: _orange,
                  colColor: _purple,
                  trackColor: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stat tile — gradient icon badge + label + full amount. FittedBox keeps a
  // very large amount within the tile width.
  Widget _statTile(
    AppThemeConst t, {
    required String label,
    required double amount,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: t.isLight ? Border.all(color: t.dividerColor) : null,
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: t.cardSubtitleText,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A3C6E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoughnutChartPainter extends CustomPainter {
  final double progress;
  final double outstandingPct;
  final double strokeWidth;
  final Color outColor;
  final Color colColor;
  final Color trackColor;

  _DoughnutChartPainter({
    required this.progress,
    required this.outstandingPct,
    required this.strokeWidth,
    required this.outColor,
    required this.colColor,
    this.trackColor = const Color(0xFFEDEFF7),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect =
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Subtle track behind the segments (fills the gaps).
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);

    const double gap = 0.14; // radians — visual gap between the two segments
    final double swept = 2 * pi * progress;
    final double drawable = (swept - gap * 2).clamp(0.0, 2 * pi);
    final double outSweep = drawable * outstandingPct;
    final double colSweep = drawable * (1 - outstandingPct);
    final double start = -pi / 2 + gap / 2;

    // Outstanding = orange gradient.
    final outPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFFFA23D), outColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Collection = purple gradient.
    final colPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFA855F7), colColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (outSweep > 0.001) {
      canvas.drawArc(rect, start, outSweep, false, outPaint);
    }
    if (colSweep > 0.001) {
      canvas.drawArc(rect, start + outSweep + gap, colSweep, false, colPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DoughnutChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.outstandingPct != outstandingPct ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
