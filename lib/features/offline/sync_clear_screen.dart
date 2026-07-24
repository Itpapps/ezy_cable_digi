import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/widgets/premium_dialog.dart';

/// Sync / Clear Data — Android parity (SyncData_Fragment).
///
/// A screen with two actions and live counts, exactly like Android:
///  • Sync Data  → POST /GetCollectionData per pending payment (flag=1),
///    ACK→flag=2 / NAK / retry. Reuses [OfflineSyncService].
///  • Clear Data → deletes the offline DB, but ONLY after all paid customers
///    are synced (Android guards this). Reuses [OfflineDataService.clearAllData].
///
/// No new engine/logic — this only presents the existing offline services.
/// Toast/dialog strings mirror Android's hardcoded English text.
class SyncClearScreen extends StatefulWidget {
  const SyncClearScreen({super.key});

  @override
  State<SyncClearScreen> createState() => _SyncClearScreenState();
}

class _SyncClearScreenState extends State<SyncClearScreen> {
  final _db = DatabaseHelper();
  int _total = 0; // downloaded records
  int _pending = 0; // flag=1 (paid, not yet synced)
  int _synced = 0; // flag=2 (synced)
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final total = await OfflineModeService.instance.downloadedRecordCount;
    final pending = await _db.getOfflinePaidCount();
    final synced = await _db.getOfflineSyncedCount();
    if (!mounted) return;
    setState(() {
      _total = total;
      _pending = pending;
      _synced = synced;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final n = await OfflineSyncService.instance.syncPendingToServer();
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        n > 0
            ? '$n record(s) synced'
            // Android SyncData_Fragment exact toast when there is nothing to sync.
            : 'No payments has been made (or) Check your internet connection.',
        isSuccess: n > 0,
      );
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        'Error syncing data. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    // Android: block clear until every paid customer is synced.
    if (_pending > 0) {
      showPremiumSnackBar(
        context,
        'Please sync all paid customer before you clear offline data.',
        isError: true,
      );
      return;
    }
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Are you sure?',
      body:
          'You are about to clear all your previous offline data. Please re-login after clearing data to reset machine ID.',
      confirmLabel: 'OK',
      cancelLabel: 'Cancel',
      isDanger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final cleared = _total;
    try {
      await OfflineDataService.instance.clearAllData();
      if (!mounted) return;
      showPremiumSnackBar(
        context,
        '$cleared records has been cleared successfully',
        isSuccess: true,
      );
      await _refresh();
    } on OfflineDataException catch (e) {
      if (!mounted) return;
      showPremiumSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Clear failed. Please try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SYNC / CLEAR DATA',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.1, color: t.appBarFg),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: t.cardBg,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        // Soft, diffuse "floating" shadow (premium card look).
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _statRow(t, 'Downloaded records', '$_total'),
                        _statRow(t, 'Payments made (pending sync)', '$_pending'),
                        _statRow(t, 'Synced', '$_synced'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _NeonButton(
                    color: const Color(0xFF22E37E),
                    fill: t.scaffoldBg,
                    textColor: t.appBarFg,
                    icon: Icons.sync,
                    label: 'SYNC DATA',
                    onTap: _busy ? null : _sync,
                  ),
                  const SizedBox(height: 12),
                  _NeonButton(
                    color: const Color(0xFFFF3B5C),
                    fill: t.scaffoldBg,
                    textColor: t.appBarFg,
                    icon: Icons.delete_outline,
                    label: 'CLEAR DATA',
                    onTap: _busy ? null : _clear,
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _statRow(AppThemeConst t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: t.cardSubtitleText, fontSize: 14)),
          Text(value,
              style: TextStyle(
                  color: t.cardHeadingText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Neon action button whose glowing border sweeps one full rotation on tap.
/// Presentation only — the tap just calls the handler passed in via [onTap].
class _NeonButton extends StatefulWidget {
  final Color color; // neon border/glow colour
  final Color fill; // fill — matches the page so the button blends
  final Color textColor;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _NeonButton({
    required this.color,
    required this.fill,
    required this.textColor,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<_NeonButton>
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
    _c.forward(from: 0); // one light rotation around the border
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    const radius = 30.0;
    const borderW = 1.8;

    final inner = Container(
      decoration: BoxDecoration(
        color: widget.fill,
        borderRadius: BorderRadius.circular(radius - borderW),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? _handleTap : null,
          borderRadius: BorderRadius.circular(radius - borderW),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: widget.textColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(borderW),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: SweepGradient(
                transform: GradientRotation(_c.value * 2 * math.pi),
                colors: [
                  widget.color.withValues(alpha: 0.30),
                  widget.color,
                  Colors.white,
                  widget.color,
                  widget.color.withValues(alpha: 0.30),
                ],
                stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: child,
          );
        },
        child: inner,
      ),
    );
  }
}
