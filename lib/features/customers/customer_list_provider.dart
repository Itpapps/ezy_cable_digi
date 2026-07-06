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
    try {
      _groups = await DealerGroupsRepository.instance.fetch();
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
      _statusCode = result.statusCode;
      _statusMessage = result.statusMessage;
      _customers = result.customers;
    } catch (error, stackTrace) {
      _statusCode = 3;
      _statusMessage = 'Server is busy or not reachable';
      _customers = [];
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'CustomerListProvider.fetch');
    } finally {
      _isLoading = false;
      _loaded = true;
      notifyListeners();
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
