import 'package:flutter/foundation.dart';
import '../../core/data/customer.dart';
import '../../core/data/offline_customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/session_service.dart';
import 'data/search_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SearchProvider — ChangeNotifier for SearchCustomerScreen.
// Owns: criteria selection, search results, loading/error state.
// Calls the Customer Search (`sc`) API via SearchRepository.
// ─────────────────────────────────────────────────────────────────────────────
class SearchProvider extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  String _criteria = 'Name';
  List<Customer> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _error;

  // ── Getters ────────────────────────────────────────────────────────────────
  // `criteria` is clamped to the available options so the dropdown value is
  // always valid even when the dealer's allowed set changes.
  String         get criteria    =>
      criteriaItems.contains(_criteria) ? _criteria : criteriaItems.first;
  List<Customer> get results     => _results;
  bool           get isLoading   => _isLoading;
  bool           get hasSearched => _hasSearched;
  String?        get error       => _error;

  // Canonical Android search options: searchType id → dropdown label, in Android's
  // display order (SearchCustomer_Fragment_Newdesign:148-177).
  static const List<MapEntry<String, String>> _searchOptions = [
    MapEntry('1', 'Alt Customer Id'),
    MapEntry('2', 'Name'),
    MapEntry('3', 'Primary Mobile Number'),
    MapEntry('4', 'Lco Customer Id'),
    MapEntry('5', 'CRF Number'),
    MapEntry('6', 'Serial Number'),
    MapEntry('7', 'VC Number'),
    MapEntry('8', 'NickName'),
    MapEntry('9', 'Secondary Mobile Number'),
    MapEntry('16', 'Broadband User Id'),
  ];

  /// Dropdown options — Android parity: built from the dealer's allowed search
  /// types (validateLogin `customerAppSearch`, e.g. "1,2,5,6,16"), in Android's
  /// order. Falls back to all options if the flag is empty (never an empty list).
  List<String> get criteriaItems {
    final allowed = SessionService.instance.customerAppSearch
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final items = _searchOptions
        .where((o) => allowed.contains(o.key))
        .map((o) => o.value)
        .toList();
    return items.isEmpty
        ? _searchOptions.map((o) => o.value).toList()
        : items;
  }

  /// Selected label → Android `searchType` id. Single source of truth ([_searchOptions]).
  int _searchType() {
    final sel = criteria; // clamped to the available options
    for (final o in _searchOptions) {
      if (o.value == sel) return int.parse(o.key);
    }
    return 2; // default Name
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  void setCriteria(String value) {
    if (_criteria == value) return;
    _criteria = value;
    _results = [];
    _hasSearched = false;
    _error = null;
    notifyListeners();
  }

  // Offline search results (parallel to _results for offline mode)
  List<OfflineCustomer> _offlineResults = [];
  List<OfflineCustomer> get offlineResults => _offlineResults;

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    _isLoading = true;
    _hasSearched = true;
    _error = null;
    _offlineResults = [];
    notifyListeners();

    // Check if in offline mode
    final isOffline = await OfflineModeService.instance.isOfflineMode;
    if (isOffline) {
      await _searchOffline(q);
    } else {
      await _searchOnline(q);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _searchOnline(String q) async {
    try {
      final result = await SearchRepository.instance.search(
        searchType: _searchType(),
        value: q,
      );
      if (result.statusCode == 0) {
        _results = result.customers;
      } else {
        _results = [];
        _error = _searchError(result.statusCode, result.statusMessage);
      }
    } catch (error, stackTrace) {
      _error = _searchError(3, ''); // transport failure → Android status-3 path
      _results = [];
      ErrorHandlerService.recordError(
        error,
        stackTrace,
        reason: 'SearchProvider.search',
      );
    }
  }

  // Android parity (SearchCustomer_Fragment_Newdesign) — searchCustomer status map:
  //  1 = no records     → "No Records Found !" title / server message (:1336-1344)
  //  2 = "<message>: Contact Support" (:1359)
  //  3 = null/transport → "Large Count" dialog / "Please search using another filter" (:1178-1184)
  String _searchError(int status, String msg) {
    switch (status) {
      case 1:
        return msg.isEmpty ? 'No Records Found !' : msg;
      case 2:
        return msg.isEmpty ? 'Contact Support' : '$msg: Contact Support';
      default:
        return 'Please search using another filter';
    }
  }

  Future<void> _searchOffline(String q) async {
    final db = DatabaseHelper();
    try {
      List<OfflineCustomer> results;
      switch (criteria) {
        case 'Name':
        case 'NickName':
          results = await db.searchOfflineByName(q);
          break;
        case 'CRF Number':
          results = await db.searchOfflineByCrf(q);
          break;
        case 'Lco Customer Id':
          results = await db.searchOfflineByLcoId(q);
          break;
        case 'Primary Mobile Number':
        case 'Secondary Mobile Number':
          results = await db.searchOfflineByMobile(q);
          break;
        default:
          results = await db.searchOfflineByName(q);
      }
      _offlineResults = results;
      _results = []; // clear online results
      if (results.isEmpty) {
        _error = 'No records found';
      }
    } catch (e) {
      _error = 'Search failed: $e';
      _offlineResults = [];
    }
  }

  void clear() {
    _results = [];
    _offlineResults = [];
    _hasSearched = false;
    _error = null;
    notifyListeners();
  }

  String get hintText {
    // Hints match Android SearchCustomer_Fragment_Newdesign.setHint(...).
    if (_criteria.contains('Mobile')) return 'Eg: 9700000010';
    if (_criteria.contains('Id') || _criteria.contains('Number')) return 'Eg: 1234';
    if (_criteria.contains('Name')) return 'Eg: Ravi';
    return 'Enter search text...';
  }
}
