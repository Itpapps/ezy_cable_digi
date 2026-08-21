import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../core/data/customer.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/session_service.dart';
import '../../features/collections/data/pay_later.dart';
import '../../features/collections/data/pay_later_repository.dart';
import '../customers/data/unpaid_customers_repository.dart';
import 'data/complaints_repository.dart';
import 'data/dashboard_repository.dart';
import 'data/nearest_repository.dart';
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
    if (loading) return; // guard against duplicate/overlapping KPI fetches
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

  // ── LCO Wallet (glda / getLCODepositAmount) ─────────────────────────────────
  // Android parity (DashboardHomeFragment): lcowallet() is called for DEALER/ADMIN
  // on every dashboard create; the card is shown only when useLcoDeposit==1
  // (ll_lcowallet visibility). Any failure keeps ₹0 (Android sets ₹0 / toasts).
  double lcoDeposit = 0;
  String get lcoWalletText => _money(lcoDeposit);

  /// Whether the LCO Wallet card is shown — Android gates on userLcoDeposit==1.
  bool get showLcoWallet => SessionService.instance.useLcoDeposit == 1;

  Future<void> loadWallet() async {
    final ut = SessionService.instance.userType.toUpperCase();
    if (ut != 'DEALER' && ut != 'ADMIN') return;
    try {
      lcoDeposit = await DashboardRepository.instance.fetchWalletBalance();
    } catch (e, s) {
      lcoDeposit = 0;
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadWallet');
    } finally {
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

  // ── Unpaid feed (unpaidCustomers `uc`) ──────────────────────────────────────
  // Dashboard-OWNED unpaid state, deliberately SEPARATE from CustomerListProvider
  // so the Customer List screen's filters (customerType/group) and its cache can
  // never bleed into the dashboard preview. Always fetches the FULL unpaid list
  // with fixed params — mirrors Android's dedicated `getunpaiddata` (hit_from=1)
  // path, which is independent of the Customer List (`Unpaid_Fragment`).
  List<Customer> unpaidCustomers = [];
  bool unpaidLoading = false;
  bool unpaidLoaded = false;
  bool unpaidError = false;
  String unpaidMessage = '';

  Future<void> loadUnpaid({bool force = false}) async {
    if (unpaidLoading) return;
    if (unpaidLoaded && !force) return;
    unpaidLoading = true;
    unpaidError = false;
    notifyListeners();
    try {
      final now = DateTime.now();
      final r = await UnpaidCustomersRepository.instance.fetch(
        customerStatus: -1, // Total Unpaid List (never the Customer List filter)
        stbStatus: -1,
        unpaidListType: 1,
        groupId: 0, // no group filter
        billMonth: '${now.month}-${now.year}',
      );
      unpaidMessage = r.statusMessage;
      if (r.statusCode == 0) {
        unpaidCustomers = r.customers; // may be empty → empty-state
        unpaidError = false;
      } else if (r.statusCode == 1) {
        unpaidCustomers = const []; // no records → empty-state, not an error
        unpaidError = false;
      } else {
        unpaidCustomers = const [];
        unpaidError = true; // status 2/3 → error message
      }
    } catch (e, s) {
      unpaidCustomers = const [];
      unpaidError = true;
      unpaidMessage = 'Could not load unpaid customers';
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadUnpaid');
    } finally {
      unpaidLoading = false;
      unpaidLoaded = true;
      notifyListeners();
    }
  }

  // ── Pay Later feed (scheduled_collection_data, from_dashboard=1) ───────────
  List<PayLaterSchedule> payLaterItems = [];
  bool payLaterLoading = false;
  bool payLaterLoaded = false;
  bool payLaterError = false;
  String payLaterMessage = '';

  Future<void> loadPayLater({bool force = false}) async {
    if (payLaterLoading) return;
    if (payLaterLoaded && !force) return;
    payLaterLoading = true;
    payLaterError = false;
    notifyListeners();
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final r = await PayLaterRepository.instance.getPayLaterList(
        scheduledStartDate: today,
        scheduledEndDate: today,
        fromDashboard: true,
      );
      payLaterMessage = r.statusMessage;
      if (r.statusCode == 0) {
        payLaterItems = r.schedules;
        payLaterError = false;
      } else {
        payLaterItems = const [];
        payLaterError = r.statusCode > 1;
      }
    } catch (e, s) {
      payLaterItems = const [];
      payLaterError = true;
      payLaterMessage = 'Could not load pay later';
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadPayLater');
    } finally {
      payLaterLoading = false;
      payLaterLoaded = true;
      notifyListeners();
    }
  }

  // ── Nearest feed (NearestNextCustomer REST, from_dashboard=1) ──────────────
  List<NearestCustomerItem> nearestItems = [];
  bool nearestLoading = false;
  bool nearestLoaded = false;
  bool nearestError = false;
  String nearestMessage = '';

  Future<void> loadNearest({bool force = false}) async {
    if (nearestLoading) return;
    if (nearestLoaded && !force) return;
    nearestLoading = true;
    nearestError = false;
    notifyListeners();
    try {
      double lat = 0;
      double lng = 0;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // GPS unavailable — send 0,0 as Android does
      }
      final r = await NearestRepository.instance.fetchNearest(
        lat: lat,
        lng: lng,
      );
      nearestMessage = r.statusMessage;
      if (r.statusCode == 0) {
        nearestItems = r.customers;
        nearestError = false;
      } else {
        nearestItems = const [];
        nearestError = r.statusCode > 1;
      }
    } catch (e, s) {
      nearestItems = const [];
      nearestError = true;
      nearestMessage = 'Could not load nearest customers';
      ErrorHandlerService.recordError(e, s,
          reason: 'DashboardController.loadNearest');
    } finally {
      nearestLoading = false;
      nearestLoaded = true;
      notifyListeners();
    }
  }
}
