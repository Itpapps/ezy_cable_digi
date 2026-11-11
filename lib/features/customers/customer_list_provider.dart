import 'package:flutter/foundation.dart';
import '../../core/data/customer.dart';
import '../../core/services/error_handler_service.dart';
import 'data/dealer_groups_repository.dart';
import 'data/unpaid_customers_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomerListProvider — ChangeNotifier for CustomerListScreen.
// Customer List (`uc`) is API-only: the server returns the FULL list (no
// pagination, no local cache) — mirrors Android's Unpaid_Fragment.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerListProvider extends ChangeNotifier {
  // ── List state ───────────────────────────────────────────────────────────────
  List<Customer> _customers = [];
  bool _isLoading = false;
  bool _loaded = false;
  // Bumped by reset(); a fetch/loadGroups that started before a reset drops
  // its (stale) result instead of writing it into the new session.
  int _generation = 0;
  int _statusCode = 0; // 0 ok · 1 no records · 3 failed
  String _statusMessage = '';
  // Android Unpaid_Fragment filters — options HARDCODED exactly like Android
  // (statussp/stbsp/paidunpaid arrays); only Group is server-driven. The
  // repository already sends all of these (billmonth/customerstatus/stbstatus/
  // unpaidlist_type/group_id) — only the UI was missing.
  String _paidUnpaid = 'Total Unpaid List'; // sp_paidunpaid → unpaidlist_type 1/2/3
  String _customerStatus = 'All';           // cusstatus → customerstatus -1/1/2
  String _stbStatus = 'All';                // stbstatus → -1/1/2/3
  DateTime _billMonth = DateTime.now();      // billmonth "M-yyyy"
  String _group = 'Select';

  static const paidUnpaidOptions =
      ['Total Unpaid List', 'Partial Paid List', 'Zero Paid'];
  static const customerStatusOptions = ['All', 'Active', 'DeActive'];
  static const stbStatusOptions = ['All', 'Active', 'DeActive', 'All Deactive'];

  List<Customer> get customers     => _customers;
  bool           get isLoading     => _isLoading;
  bool           get loaded        => _loaded;
  int            get statusCode    => _statusCode;
  String         get statusMessage => _statusMessage;
  String         get paidUnpaid     => _paidUnpaid;
  String         get customerStatus => _customerStatus;
  String         get stbStatus      => _stbStatus;
  DateTime       get billMonth      => _billMonth;
  String         get group         => _group;
  bool           get hasError      => _loaded && _statusCode == 3;

  // ── Dealer groups (config key `dg`) for the Group filter dropdown ──────────────
  List<DealerGroup> _groups = const [DealerGroup(0, 'Select')];
  List<DealerGroup> get groups     => _groups;
  List<String>      get groupNames => _groups.map((g) => g.name).toList();

  /// group_id for the currently selected group name (sent to `uc`).
  int get selectedGroupId => _groups
      .firstWhere((g) => g.name == _group,
          orElse: () => const DealerGroup(0, 'Select'))
      .id;

  /// Load dealer groups from the API to populate the dropdown.
  Future<void> loadGroups() async {
    final gen = _generation;
    try {
      final groups = await DealerGroupsRepository.instance.fetch();
      if (gen != _generation) return; // reset() ran meanwhile — stale
      _groups = groups;
      notifyListeners();
    } catch (_) {
      // keep the default ['Select'] on failure
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────────
  void setPaidUnpaid(String value) {
    if (_paidUnpaid == value) return;
    _paidUnpaid = value;
    refresh();
  }

  // Advanced filters — Android cusstatus/stbstatus/bill-month DON'T auto-fetch;
  // they only set the value and are applied by the Search button (tv_search).
  // So these just update state + rebuild the dropdown; call refresh() (Search).
  void setCustomerStatus(String value) {
    if (_customerStatus == value) return;
    _customerStatus = value;
    notifyListeners();
  }

  void setStbStatus(String value) {
    if (_stbStatus == value) return;
    _stbStatus = value;
    notifyListeners();
  }

  void setBillMonth(DateTime value) {
    _billMonth = value;
    notifyListeners();
  }

  /// Apply the advanced filters (Android tv_search "Search" button → getunpaiddata).
  void applySearch() => refresh();

  void setGroup(String value) {
    if (_group == value) return;
    _group = value;
    refresh();
  }

  // ── Reset (D3) ──────────────────────────────────────────────────────────────
  /// Android parity: every Customer List open is a NEW Unpaid_Fragment (default
  /// filters + a fresh `uc` call), and logout finishes the activity. This
  /// provider is app-wide, so it must be cleared explicitly: on every list
  /// open and whenever the Login screen is shown.
  void reset() {
    _generation++;
    _customers = [];
    _isLoading = false;
    _loaded = false;
    _statusCode = 0;
    _statusMessage = '';
    _paidUnpaid = 'Total Unpaid List';
    _customerStatus = 'All';
    _stbStatus = 'All';
    _billMonth = DateTime.now();
    _group = 'Select';
    _groups = const [DealerGroup(0, 'Select')];
    notifyListeners();
  }

  // ── Load (uc) ────────────────────────────────────────────────────────────────
  Future<void> initialLoad() async {
    if (_loaded) return;
    await fetch();
  }

  Future<void> refresh() async {
    _loaded = false;
    await fetch();
  }

  Future<void> fetch() async {
    if (_isLoading || _loaded) return; // uc loads the full list once; no pagination
    final gen = _generation;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await UnpaidCustomersRepository.instance.fetch(
        customerStatus: _customerStatusValue(),
        stbStatus: _stbStatusValue(),
        unpaidListType: _unpaidListTypeValue(),
        groupId: selectedGroupId,
        billMonth: _billMonthValue(),
      );
      if (gen != _generation) return; // reset() ran meanwhile — stale
      _statusCode = result.statusCode;
      _statusMessage = result.statusMessage;
      _customers = result.customers;
    } catch (error, stackTrace) {
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'CustomerListProvider.fetch');
      if (gen != _generation) return; // reset() ran meanwhile — stale
      _statusCode = 3;
      _statusMessage = 'Server is busy or not reachable';
      _customers = [];
    } finally {
      if (gen == _generation) {
        _isLoading = false;
        _loaded = true;
        notifyListeners();
      }
    }
  }

  // Android position-based mappings (Unpaid_Fragment spinner listeners :247-298).
  // sp_paidunpaid → selectedpaidunpaid = position + 1 (Total Unpaid=1 · Partial
  // Paid=2 · Zero Paid=3).
  int _unpaidListTypeValue() => paidUnpaidOptions.indexOf(_paidUnpaid) + 1;

  // cusstatus: All → -1 · Active → 1 · DeActive → 2.
  int _customerStatusValue() {
    switch (_customerStatus) {
      case 'Active':
        return 1;
      case 'DeActive':
        return 2;
      default:
        return -1; // All
    }
  }

  // stbstatus: All → -1 · Active → 1 · DeActive → 2 · All Deactive → 3.
  int _stbStatusValue() {
    switch (_stbStatus) {
      case 'Active':
        return 1;
      case 'DeActive':
        return 2;
      case 'All Deactive':
        return 3;
      default:
        return -1; // All
    }
  }

  // billmonth format "M-yyyy" (Android: Unpaid_Fragment tv_dateset).
  String _billMonthValue() => '${_billMonth.month}-${_billMonth.year}';
}
