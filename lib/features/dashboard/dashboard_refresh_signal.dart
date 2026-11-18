/// One-shot cross-screen signal for post-action dashboard refresh.
///
/// Android rebuilds the whole dashboard fragment after a successful payment, so
/// its KPI summary (Due / Collections / Month billing) always reflects the new
/// balance. Flutter returns to the *existing* dashboard route via
/// `popUntil(isFirst)`, which does NOT re-run `initState` — so without a signal
/// the KPI amounts stay stale. A collection action sets [markKpiDirty]; the
/// Dashboard consumes it once on return ([consumeKpiDirty]) and force-refreshes
/// KPIs only then. When the flag is unset (e.g. returning from a read-only
/// screen) nothing reloads — so there are no unnecessary refreshes.
class DashboardRefreshSignal {
  DashboardRefreshSignal._();
  static final DashboardRefreshSignal instance = DashboardRefreshSignal._();

  bool _kpiDirty = false;

  /// Flag that the dashboard KPIs are stale (e.g. after a successful payment).
  void markKpiDirty() => _kpiDirty = true;

  /// Returns whether a KPI refresh is pending and clears the flag (one-shot).
  bool consumeKpiDirty() {
    final was = _kpiDirty;
    _kpiDirty = false;
    return was;
  }

  /// Counts successful payments. A screen notes the value before opening the
  /// Payment screen and reloads its customer on return only if it changed —
  /// a plain Back without paying makes no extra API call. Not one-shot, so
  /// several screens can check it.
  int _paymentCount = 0;
  int get paymentCount => _paymentCount;
  void markPaymentDone() => _paymentCount++;
}
