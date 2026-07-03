import 'dart:math';
import 'package:flutter/material.dart';

import '../../core/services/error_handler_service.dart';
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
    final double total = outstanding + collection;
    final double outPct = total == 0 ? 0 : outstanding / total;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: AppBar(
        title: const Text(
          "Analytics",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFDCE2F0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error && outstanding == 0 && collection == 0
              ? const Center(
                  child: Text('Could not load analytics data',
                      style: TextStyle(
                          color: Colors.black45, fontWeight: FontWeight.w600)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Collections Overview',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A3C6E))),
                        ),
                        const SizedBox(height: 20),
                        // Big, responsive donut — fills the card width (capped),
                        // so it reads large like the Android chart.
                        LayoutBuilder(
                          builder: (context, c) {
                            final double s =
                                c.maxWidth < 340 ? c.maxWidth : 340;
                            final double stroke = s * 0.15;
                            return AnimatedBuilder(
                              animation: _anim,
                              builder: (context, child) {
                                return SizedBox(
                                  width: s,
                                  height: s,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: s,
                                        height: s,
                                        child: CustomPaint(
                                          painter: _DoughnutChartPainter(
                                            progress: _anim.value,
                                            outstandingPct: outPct,
                                            strokeWidth: stroke,
                                            outColor: _orange,
                                            colColor: _purple,
                                          ),
                                        ),
                                      ),
                                      // Center: Collection amount in purple
                                      // (small, always fits — no "0%").
                                      SizedBox(
                                        width: s - stroke * 2 - 28,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '₹${collection.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w900,
                                                  color: _purple,
                                                  height: 1.0,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Collected',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        // Value badges — orange Outstanding, purple Collection
                        // (full amounts, FittedBox keeps any value in width).
                        Row(
                          children: [
                            Expanded(
                                child: _valueBadge(
                                    'Outstanding', outstanding, _orange)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _valueBadge(
                                    'Collection', collection, _purple)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  // Value badge — tinted pill matching a segment colour: dot + label + full
  // amount. FittedBox keeps a very large amount within the badge width.
  Widget _valueBadge(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A3C6E))),
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

  _DoughnutChartPainter({
    required this.progress,
    required this.outstandingPct,
    required this.strokeWidth,
    required this.outColor,
    required this.colColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect =
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Subtle track behind the segments (fills the gaps on the white card).
    final trackPaint = Paint()
      ..color = const Color(0xFFEDEFF7)
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
