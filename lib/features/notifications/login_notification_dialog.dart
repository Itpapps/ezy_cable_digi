import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../core/constants/app_colors.dart';
import 'data/login_notification.dart';

/// The login-notification popup — shows ALL notifications in ONE scrollable
/// dialog (blue title bar, scrollable HTML body, blue OK). Read them by
/// scrolling; the notices are separated by dividers.
///
/// Auto-close (merged, since it's a single popup): if ANY notification is
/// stay-until-dismissed (`duration_min`/`sec` both 0) the popup stays until OK;
/// otherwise it closes after the LONGEST duration (enough time to read all).
class LoginNotificationDialog extends StatefulWidget {
  final List<LoginNotification> notifications;
  const LoginNotificationDialog({super.key, required this.notifications});

  @override
  State<LoginNotificationDialog> createState() =>
      _LoginNotificationDialogState();
}

class _LoginNotificationDialogState extends State<LoginNotificationDialog> {
  Timer? _autoClose;
  bool _closed = false; // guard: never pop twice (timer + OK race)

  Duration get _mergedDuration {
    final list = widget.notifications;
    if (list.isEmpty) return Duration.zero;
    if (list.any((n) => n.autoClose == Duration.zero)) return Duration.zero;
    return list.map((n) => n.autoClose).reduce((a, b) => a > b ? a : b);
  }

  @override
  void initState() {
    super.initState();
    final d = _mergedDuration;
    if (d > Duration.zero) {
      _autoClose = Timer(d, _close);
    }
  }

  /// D6 / Android MainActivity :1201-1220: the timer and OK dismiss ONLY this
  /// popup (`if (dialog.isShowing()) dialog.dismiss()`). A plain pop() would
  /// close whatever is on top — e.g. a dashboard error/"login again" dialog
  /// opened over this one. So pop when this popup is on top, otherwise remove
  /// just this popup's route and leave the dialog above it untouched.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    _autoClose?.cancel();
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return; // already gone
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    final title = widget.notifications.isNotEmpty
        ? widget.notifications.first.title
        : 'Notifications';

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Blue title bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: AppColors.primary,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // ONE scrollable body holding every notification (HTML rendered),
            // separated by dividers — read them all by scrolling.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < widget.notifications.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 24, color: Color(0xFFE5E7EB)),
                      Html(
                        data: widget.notifications[i].body,
                        style: {
                          'body': Style(
                            margin: Margins.zero,
                            fontSize: FontSize(14),
                            color: Colors.black87,
                          ),
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Live countdown — isolated widget so only the label ticks each
            // second; the HTML body is never re-rendered. Hidden when the popup
            // is stay-until-dismissed (duration 0).
            if (_mergedDuration > Duration.zero)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _CountdownLabel(total: _mergedDuration),
                ),
              ),
            // Single blue OK button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _close,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Isolated 1-second countdown label. Owning its own state means only THIS
/// widget rebuilds each tick — the dialog's HTML body is never re-rendered.
class _CountdownLabel extends StatefulWidget {
  final Duration total;
  const _CountdownLabel({required this.total});

  @override
  State<_CountdownLabel> createState() => _CountdownLabelState();
}

class _CountdownLabelState extends State<_CountdownLabel> {
  late Duration _remaining = widget.total;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _remaining - const Duration(seconds: 1);
      setState(() => _remaining = next.isNegative ? Duration.zero : next);
      if (_remaining <= Duration.zero) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Text(
      'Remaining Time: ${_fmt(_remaining)}',
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
