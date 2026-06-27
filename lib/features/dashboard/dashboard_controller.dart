import 'package:flutter/foundation.dart';

import '../../core/services/error_handler_service.dart';
import '../../core/services/session_service.dart';
import 'data/complaints_repository.dart';
import 'data/dashboard_repository.dart';
import 'data/open_complaint.dart';

/// Owns the dashboard KPI-card state (Due / Month Billing / Onetime /
/// Collections). Defensive by design: any failure (null/malformed response,
/// non-zero status code, network/timeout) leaves the amounts at their safe
/// `₹0.00` fallback and flags [hasError] — it NEVER throws to the UI, so one
/// failing section cannot crash the dashboard. See server docs/DASHBOARD_FLOW.md.
class DashboardController extends ChangeNotifier {
  bool loading = false;
  bool hasError = false;
  String? errorMessage;

  double dueAmount = 0;
  double monthBilling = 0;
  double onetimeCharges = 0;
  double collections = 0;

  /// Android feeds "Collections" from `employeeCollectionAmount` for EMPLOYEE,
  /// else `collectionAmount`.
  bool get _isEmployee =>
      SessionService.instance.userType.toUpperCase() == 'EMPLOYEE';

  // NOTE: amounts are shown as-is (₹%.2f), matching Android's ACTUAL mode.
  // Android's optional ROUND/CEIL modes depend on the login `amount_round`
  // flag, which is not yet captured at login — tracked as a follow-up.
  String _money(double v) => '₹${v.toStringAsFixed(2)}';
  String get dueAmountText => _money(dueAmount);
  String get monthBillingText => _money(monthBilling);
  String get onetimeChargesText => _money(onetimeCharges);
  String get collectionsText => _money(collections);

  Future<void> loadKpis() async {
    loading = true;
    hasError = false;
    errorMessage = null;
    notifyListeners();
    try {
      final r = await DashboardRepository.instance.fetchKpis();
      if (r.isSuccess) {
        dueAmount = r.outstandingAmount;
        monthBilling = r.billAmount;
        onetimeCharges = r.onetimeChargeAmount;
        collections =
            _isEmployee ? r.employeeCollectionAmount : r.collectionAmount;
      } else {
        // statusCode 1/2/3 — keep safe ₹0.00 values, surface a soft message.
        hasError = true;
        errorMessage =
            r.statusMessage.isEmpty ? 'Could not load dashboard' : r.statusMessage;
      }
    } catch (e, s) {
      // Network / timeout / parse — never crash; keep zeros.
      hasError = true;
      errorMessage = 'Could not load dashboard';
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadKpis');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Complaints feed (getopencomplaintslist) ─────────────────────────────────
  List<OpenComplaint> complaints = [];
  bool complaintsLoading = false;
  bool complaintsLoaded = false;
  bool complaintsError = false;
  String complaintsMessage = '';

  /// Loads open complaints. Lazy by default; pass [force] to refetch (the
  /// Complaints tab refetches on tap, mirroring Android). Defensive — any
  /// failure leaves an empty list + [complaintsError], never throws to the UI.
  Future<void> loadComplaints({bool force = false}) async {
    if (complaintsLoading) return;
    if (complaintsLoaded && !force) return;
    complaintsLoading = true;
    complaintsError = false;
    notifyListeners();
    try {
      final r = await ComplaintsRepository.instance.fetchOpenComplaints();
      complaintsMessage = r.statusMessage;
      if (r.statusCode == 0) {
        complaints = r.complaints; // may be empty → empty-state
        complaintsError = false;
      } else if (r.statusCode == 1) {
        complaints = const []; // no records → empty-state, not an error
        complaintsError = false;
      } else {
        complaints = const [];
        complaintsError = true; // status 2/3 → error message
      }
    } catch (e, s) {
      complaints = const [];
      complaintsError = true;
      complaintsMessage = 'Could not load complaints';
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadComplaints');
    } finally {
      complaintsLoading = false;
      complaintsLoaded = true;
      notifyListeners();
    }
  }
}
