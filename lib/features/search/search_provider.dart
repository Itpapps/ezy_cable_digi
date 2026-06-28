import 'package:flutter/foundation.dart';
import '../../core/data/customer.dart';
import '../../core/data/offline_customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/offline_mode_service.dart';
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
  String         get criteria    => _criteria;
  List<Customer> get results     => _results;
  bool           get isLoading   => _isLoading;
  bool           get hasSearched => _hasSearched;
  String?        get error       => _error;

  static const criteriaItems = [
    'Name',
    'Alt Customer Id',
    'Lco Customer Id',
    'Primary Mobile Number',
    'Secondary Mobile Number',
    'CRF Number',
    'Serial Number',
    'VC Number',
    'NickName',
  ];

  // Criteria → Android `searchType` (from SearchCustomer_Fragment_Newdesign hints).
  // Confirmed: Name=2, Alt Customer Id=1, Primary Mobile=3, Secondary Mobile=9,
  // CRF=5, NickName=8. To verify on test: Lco/Serial/VC (the alphanumeric 4/6/7).
  int _searchType() {
    switch (_criteria) {
      case 'Alt Customer Id':
        return 1;
      case 'Name':
        return 2;
      case 'Primary Mobile Number':
        return 3;
      case 'Lco Customer Id':
        return 4; // verify
      case 'CRF Number':
        return 5;
      case 'Serial Number':
        return 6; // verify
      case 'VC Number':
        return 7; // verify
      case 'NickName':
        return 8;
      case 'Secondary Mobile Number':
        return 9;
      default:
        return 2;
    }
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
        _error = result.statusMessage.isEmpty
            ? 'No records found'
            : result.statusMessage;
      }
    } catch (error, stackTrace) {
      _error = 'Search failed. Please try again.';
      _results = [];
      ErrorHandlerService.recordError(
        error,
        stackTrace,
        reason: 'SearchProvider.search',
      );
    }
  }

  Future<void> _searchOffline(String q) async {
    final db = DatabaseHelper();
    try {
      List<OfflineCustomer> results;
      switch (_criteria) {
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
    if (_criteria.contains('Mobile')) return 'Eg: 9876543210';
    if (_criteria.contains('Id') || _criteria.contains('Number')) return 'Eg: 1234';
    if (_criteria.contains('Name')) return 'Eg: Bala';
    return 'Enter search text...';
  }
}
