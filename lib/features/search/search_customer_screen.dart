import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../core/constants/app_sizes.dart';
import '../../core/data/customer.dart';
import '../../core/data/offline_customer.dart';
import '../../core/services/offline_mode_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../customer/customer_details_screen.dart';
import 'data/search_repository.dart';
import '../customer/customer_map_screen.dart';
import '../offline/offline_payment_flow.dart';
import 'search_dealers.dart';
import 'search_provider.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

class SearchCustomerScreen extends StatefulWidget {
  const SearchCustomerScreen({super.key});
  @override
  State<SearchCustomerScreen> createState() => _SearchCustomerScreenState();
}

class _SearchCustomerScreenState extends State<SearchCustomerScreen>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _sweepCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  // Selected CRF prefix (Android crf_selected). Defaults to the first prefix.
  String? _crfPrefix;
  // D-B6: common employees only — Android's Dealer dropdown
  // (searchcustomer_searchoptions_spdealer), default "----Select Dealer----".
  // Online search only: Android's offline search (Offline_Search_Fragment)
  // has no Dealer dropdown, and this screen is reused for offline search.
  bool _isCommonEmployee = false;
  List<SearchDealer> _dealers = const [kSelectDealer];
  int _dealerId = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    // Play one blue sweep each time the field gains focus (touch/tap).
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) _sweepCtrl.forward(from: 0);
    });

    // Clear previous search results exactly as requested when opening the screen
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) context.read<SearchProvider>().clear();
      // Offline mode → Android's fixed offline search options.
      if (mounted) await context.read<SearchProvider>().loadSearchMode();
      // D-B6 / Android :506-510: load the Dealer list for a common employee
      // (online search only — see _isCommonEmployee).
      // Android :506 shows the Dealer dropdown when common_employee != 0.
      if (SessionService.instance.commonEmployee == 0) return;
      if (await OfflineModeService.instance.isOfflineMode) return;
      if (!mounted) return;
      setState(() => _isCommonEmployee = true);
      _loadDealers();
    });
  }

  Future<void> _loadDealers() async {
    final list = await loadSearchDealers(context);
    if (list == null || !mounted) return;
    setState(() {
      _dealers = list;
      _dealerId = 0; // Android: items[0] "----Select Dealer----" is selected
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _sweepCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    _focusNode.unfocus();
    final provider = context.read<SearchProvider>();
    // D4 / Android cust_search: the non-cancellable "Searching..., Please
    // wait..." loader allows only one search at a time — a second Search
    // (button or keyboard) while one is running is ignored.
    if (provider.isLoading) return;
    // Android parity (SearchCustomer_Fragment_Newdesign:615-617): empty field →
    // "Please enter any value in the fields" instead of silently doing nothing.
    final typed = _searchController.text.trim();
    if (typed.isEmpty) {
      showPremiumSnackBar(
        context,
        'Please enter any value in the fields',
        isError: true,
      );
      return;
    }
    // CRF with a prefix dropdown: full CRF = prefix + last digits (Android :565).
    final prefixes = SessionService.instance.crfPrefixes;
    final isCrf = provider.criteria.contains('CRF');
    final query = (isCrf && prefixes.isNotEmpty)
        ? '${_crfPrefix ?? prefixes.first}$typed'
        : typed;
    // D-B6 / Android :928-932: 0 for a normal employee, the chosen dealer for
    // a common employee.
    await provider.search(query, dealerId: _isCommonEmployee ? _dealerId : 0);
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _appBar(t),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Teal gradient banner ──────────────────────────────────────
              _headerChip(t),
              const SizedBox(height: 14),
              // ── D-B6: Dealer dropdown (common employees only, above the
              //    search options like Android's search_new_digi.xml) ──────
              // D4 / Android cust_search: while a search runs, the dealer,
              // criteria, CRF prefix, text field and Search button ignore taps
              // (dimmed), so a criteria change or second search can't mix
              // results. The inline spinner below is kept.
              Selector<SearchProvider, bool>(
                selector: (_, p) => p.isLoading,
                builder: (context, busy, child) => AbsorbPointer(
                  absorbing: busy,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: busy ? 0.5 : 1.0,
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isCommonEmployee) ...[
                      _dealerDropdown(),
                      const SizedBox(height: 10),
                    ],
                    // ── Dropdown ───────────────────────────────────────────
                    _dropdown(t),
                    const SizedBox(height: 10),
                    // ── Search field ───────────────────────────────────────
                    _searchField(t),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ── Results ──────────────────────────────────────────────────
              // Android parity: the search controls stay fixed and the results
              // render in a lazy list (RecyclerView equivalent). Android does NOT
              // paginate — the full result set is shown, lazily recycled.
              Expanded(
                child: Consumer<SearchProvider>(
                  builder: (context, p, _) {
                    if (p.isLoading) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: CircularProgressIndicator(color: t.accent),
                        ),
                      );
                    }
                    if (p.error != null) {
                      return _empty(p.error!, Iconsax.warning_2, t);
                    }
                    if (!p.hasSearched) return _initialState(t);
                    // Offline results
                    if (p.offlineResults.isNotEmpty) {
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 32),
                        itemCount: p.offlineResults.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _offlineResultBanner(p, t),
                            );
                          }
                          final c = p.offlineResults[i - 1];
                          return _OfflineSearchCard(
                            customer: c,
                            t: t,
                            onTap: () =>
                                openOfflinePaymentFlowForOfflineCustomer(
                                  context,
                                  c,
                                ),
                          );
                        },
                      );
                    }
                    if (p.results.isEmpty) {
                      return _empty(
                        'No customers found',
                        Iconsax.user_search,
                        t,
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: p.results.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _resultBanner(p, t),
                          );
                        }
                        return SearchCustomerCard(
                          customer: p.results[i - 1],
                          t: t,
                          // D-B6: the detail fetch uses the same dealer.
                          dealerId: _isCommonEmployee ? _dealerId : 0,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(AppThemeConst t) => AppBar(
    backgroundColor: t.appBarBg,
    foregroundColor: t.appBarFg,
    elevation: 0,
    shape: Border(bottom: BorderSide(color: t.appBarBorderColor, width: 1)),
    centerTitle: true,
    automaticallyImplyLeading: false,
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
      'SEARCH CUSTOMER',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: t.appBarFg,
      ),
    ),
  );

  // ── Teal gradient banner chip ─────────────────────────────────────────────
  Widget _headerChip(AppThemeConst t) => Consumer<SearchProvider>(
    builder: (context, p, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: t.headerGradient,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.search_normal, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search by ${p.criteria}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── D-B6: Dealer dropdown (common employees) ──────────────────────────────
  // Android searchcustomer_searchoptions_spdealer: "----Select Dealer----" (0)
  // + the mapped dealers; the choice is sent as custInfo.dealer_id.
  Widget _dealerDropdown() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _dealers.any((d) => d.id == _dealerId) ? _dealerId : 0,
        isExpanded: true,
        menuMaxHeight: 300,
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        icon: const Padding(
          padding: EdgeInsets.only(right: 14),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 24,
            color: Colors.black54,
          ),
        ),
        items: _dealers
            .map(
              (d) => DropdownMenuItem<int>(
                value: d.id,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    d.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D1B4B),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _dealerId = v);
        },
      ),
    ),
  );

  // ── Criteria dropdown ─────────────────────────────────────────────────────
  Widget _dropdown(AppThemeConst t) => Consumer<SearchProvider>(
    builder: (context, p, _) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: p.criteria,
          isExpanded: true,
          // Presentation-only polish: shorter, rounded, softer dropdown menu.
          menuMaxHeight: 200,
          borderRadius: BorderRadius.circular(12),
          elevation: 3,
          icon: const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 24,
              color: Colors.black54,
            ),
          ),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0D1B4B),
            fontSize: 15,
          ),
          items: p.criteriaItems
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B4B),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            context.read<SearchProvider>().setCriteria(v);
            _searchController.clear();
          },
        ),
      ),
    ),
  );

  // ── Search field ──────────────────────────────────────────────────────────
  Widget _searchField(AppThemeConst t) => Consumer<SearchProvider>(
    builder: (context, p, _) {
      // CRF search (Android): a prefix dropdown (userCode) + a ≤4-digit field.
      // Only when the dealer has CRF prefixes — else the single field stays.
      final prefixes = SessionService.instance.crfPrefixes;
      final showPrefix = p.criteria.contains('CRF') && prefixes.isNotEmpty;
      final prefixValue = (_crfPrefix != null && prefixes.contains(_crfPrefix))
          ? _crfPrefix
          : (prefixes.isNotEmpty ? prefixes.first : null);
      return AnimatedBuilder(
        animation: _sweepCtrl,
        builder: (context, child) => Container(
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15.6),
            gradient: SweepGradient(
              transform: GradientRotation(_sweepCtrl.value * 2 * math.pi),
              colors: const [
                Color(0xFF0D47A1),
                Color(0xFF0D47A1),
                Colors.white,
                Color(0xFF0D47A1),
                Color(0xFF0D47A1),
              ],
              stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
            ),
          ),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (showPrefix) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: prefixValue,
                      isDense: true,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D1B4B),
                      ),
                      items: prefixes
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _crfPrefix = v),
                    ),
                  ),
                ),
                Container(width: 1, height: 26, color: Colors.black12),
              ],
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _performSearch(),
                  keyboardType: (showPrefix || p.isMobileSearch)
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: showPrefix
                      ? [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ]
                      // D-B4 / Android :282-298: mobile = digits only, max 10.
                      : p.isMobileSearch
                          ? [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ]
                          // D-B5 / Android :476-492: letters, digits, space
                          // and _ / - . only, max 50 (customnumber varchar 50).
                          : p.isAccountNumberSearch
                              ? [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z0-9 _/\-.]')),
                                  LengthLimitingTextInputFormatter(50),
                                ]
                              : null,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D1B4B),
                  ),
                  decoration: InputDecoration(
                    hintText: showPrefix ? 'Last 4 digits' : p.hintText,
                    hintStyle: const TextStyle(
                      color: Colors.black38,
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: GestureDetector(
                  onTap: _performSearch,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Iconsax.search_normal,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ── Results count banner ──────────────────────────────────────────────────
  Widget _resultBanner(SearchProvider p, AppThemeConst t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: t.headerGradient,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Text(
          'RESULTS BY ${p.criteria}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${p.results.length} found',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Offline results count banner ────────────────────────────────────────────
  Widget _offlineResultBanner(SearchProvider p, AppThemeConst t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF00796B), Color(0xFF26A69A)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Text(
          'OFFLINE: ${p.criteria}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${p.offlineResults.length} found',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Empty state ───────────────────────────────────────────────────────────
  // Scrolls instead of overflowing when the list area is short (small phone,
  // keyboard open, MainFrame bars) — looks the same when it fits.
  Widget _empty(String msg, IconData icon, AppThemeConst t) =>
      SingleChildScrollView(child: Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      children: [
        Icon(icon, size: 52, color: t.emptyStateIconColor),
        const SizedBox(height: 12),
        Text(
          msg,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.bodyText,
          ),
        ),
      ],
    ),
  ));

  // Initial state — shown ONLY before the first search (State 1: !hasSearched).
  // Kept deliberately separate from _empty() so "haven't searched yet" stays
  // visually distinct from errors / zero-results. Presentation only.
  Widget _initialState(AppThemeConst t) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.search_normal, size: 64, color: t.emptyStateIconColor),
            const SizedBox(height: 16),
            Text(
              'Search for a customer',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.bodyText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a search type, enter the details and tap search.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.bodyText.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SearchCustomerCard — matches reference photo exactly
//   • Light blue-grey card bg (#F0F4FF)
//   • Blue rounded-square avatar
//   • Outlined STB badge
//   • Icon info rows (Pending, Last Paid, Address)
//   • Dark navy "View Details" button + red map pin
// ─────────────────────────────────────────────────────────────────────────────
class SearchCustomerCard extends StatelessWidget {
  final Customer customer;
  final AppThemeConst t;
  final int dealerId; // D-B6: dealer_id for the enriched detail fetch
  const SearchCustomerCard(
      {super.key, required this.customer, required this.t, this.dealerId = 0});

  /// Issue 5 / Android SearchCustomer_Rec_Adapter :67-78: the card's "Pending
  /// Amount" is the server's `pending` (the payable amount), not
  /// `total_amount`, with the dealer's amount_round applied: ACTUAL → the
  /// server text as-is · ROUND → whole number · CEIL → ceiling ("2399.0"),
  /// like Java's String.valueOf(Math.round / Math.ceil). Empty or unreadable →
  /// "₹0" (the card's existing fallback).
  static String _pendingText(String raw) {
    final s = raw.replaceAll('₹', '').trim();
    final v = double.tryParse(s);
    if (v == null) return '₹0';
    final session = SessionService.instance;
    if (session.amountRound == 'ACTUAL') return '₹$s';
    final r = session.applyAmountRound(v);
    if (session.amountRound == 'ROUND') return '₹${r.toInt()}';
    return '₹$r';
  }

  @override
  Widget build(BuildContext context) {
    final hasLoc = customer.latitude != null && customer.longitude != null;
    final pendingValue = double.tryParse(
            customer.amountPayable.replaceAll('₹', '').trim()) ??
        0;
    final hasPending = pendingValue != 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white, // Bottom part is white
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row (Light Blue-Grey Background) ──────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: const BoxDecoration(
              color: Color(
                0xFFE2E9F4,
              ), // visible light-blue header (was near-white)
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFD5DFF0), width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Blue gradient rounded-square avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: t.headerGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + sub-id
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D1B4B),
                        ),
                      ),
                      if (customer.altCustomerId.isNotEmpty)
                        Text(
                          customer.altCustomerId,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                // STB softly colored badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6), // Soft indigo/grey tint
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFC5CAE9),
                    ), // Subtle border
                  ),
                  child: Text(
                    customer.customerTypeLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F51B5),
                    ),
                  ), // Indigo text
                ),
              ],
            ),
          ),

          // ── Info & Buttons Section (Pure White Background) ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info rows
                _row(
                  Iconsax.timer_1,
                  'Pending Amount',
                  _pendingText(customer.amountPayable),
                  valueColor: hasPending
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF1AA95A),
                ),
                const SizedBox(height: 8),
                _row(
                  Iconsax.calendar_tick,
                  'Last Paid Date',
                  customer.lastPaidDate.isEmpty ? '—' : customer.lastPaidDate,
                ),
                const SizedBox(height: 8),
                _row(
                  Iconsax.home,
                  'Address',
                  customer.address.isEmpty ? '—' : customer.address,
                ),
                // Android parity (SearchCustomer_Rec_Adapter:134): the CRF row is
                // shown only when the dealer uses CRF (use_caf == 1). "NA" mirrors
                // Android's empty-CRF placeholder.
                if (SessionService.instance.useCaf == 1) ...[
                  const SizedBox(height: 8),
                  _row(
                    Iconsax.document_text,
                    'CRF Number',
                    customer.crfNumber.isEmpty ? 'NA' : customer.crfNumber,
                  ),
                ],
                // Android parity (SearchCustomer_Rec_Adapter:120-132): the
                // Broadband User ID row is shown only for BroadBand (type 1) and
                // STB & BroadBand (type 2) customers. Null-safe fallback.
                if (customer.customerType.trim() == '1' ||
                    customer.customerType.trim() == '2') ...[
                  const SizedBox(height: 8),
                  _row(
                    Icons.wifi,
                    'Broadband User ID',
                    customer.broadbandUserId.isEmpty
                        ? 'N/A'
                        : customer.broadbandUserId,
                  ),
                ],

                const SizedBox(height: 14),

                // Buttons
                Row(
                  children: [
                    // Dark navy "View Details" button
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openDetail(context, customer),
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1A3A8C,
                            ), // dark navy — reference photo
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Iconsax.user_tag,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'View Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Red/pink map pin — only if GPS saved
                    if (hasLoc) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerMapScreen(
                              customer: customer,
                              currentLocation: LatLng(
                                customer.latitude!,
                                customer.longitude!,
                              ),
                            ),
                          ),
                        ),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE4E4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Iconsax.location,
                            color: Color(0xFFD32F2F),
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF5B7BCC)),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? const Color(0xFF0D1B4B),
            ),
          ),
        ),
      ],
    );
  }

  /// Android two-step (SearchCustomer_Fragment_Newdesign:644-647): on selecting a
  /// customer, fetch the enriched detail (is_list=1) so is_show / tmp_activation
  /// are populated for the operations grid. Falls back to the list customer if
  /// the detail fetch yields nothing — never blocks navigation.
  Future<void> _openDetail(BuildContext context, Customer c) async {
    // D7 / Android cust_search :908: non-cancellable "Searching...,   Please
    // wait..." (Back ignored). The navigator is captured first so the loader
    // is closed even if this card is rebuilt while waiting.
    final nav = Navigator.of(context, rootNavigator: true);
    showPremiumLoading(context,
        message: 'Searching...,   Please wait...', canPop: false);
    final enriched = await SearchRepository.instance.fetchCustomerDetail(
      c.lcoCustomerId,
      dealerId: dealerId, // D-B6
    );
    nav.pop(); // dismiss loading (fetchCustomerDetail never throws)
    if (!context.mounted) return;
    // Android parity: CRF is carried from the LIST result into the details/
    // payment screen via the bundle (CustomerMgmt_MakePayment_Fragment:263,
    // 1213-1216), NOT re-read from the enriched is_list=1 detail (whose response
    // omits `crf`). So keep the list CRF when the enriched detail lacks it, else
    // the CRF row shows "NA" for CRF dealers.
    final customer = enriched == null
        ? c
        : (enriched.crfNumber.isEmpty && c.crfNumber.isNotEmpty
              ? enriched.copyWith(crfNumber: c.crfNumber)
              : enriched);
    final provider = context.read<SearchProvider>(); // app-wide provider
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(customer: customer),
      ),
    );
    // Android: coming back from Customer Operations rebuilds the search screen
    // with the result list hidden, so the user searches again and sees current
    // amounts — never the old list. The typed text and option stay.
    provider.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OfflineSearchCard — simple card for offline customer search results
// ─────────────────────────────────────────────────────────────────────────────
class _OfflineSearchCard extends StatelessWidget {
  final OfflineCustomer customer;
  final AppThemeConst t;
  final VoidCallback onTap;
  const _OfflineSearchCard({
    required this.customer,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D1B4B),
                ),
              ),
              const SizedBox(height: 6),
              _infoRow('CRF', customer.crfNumber),
              _infoRow('LCO ID', customer.lcoCustId),
              _infoRow('Mobile', customer.mobileNum),
              _infoRow('Total Due', '₹${customer.totalAmount}'),
              _infoRow(
                'Status',
                customer.flag == 0
                    ? 'Unpaid'
                    : customer.flag == 1
                    ? 'Paid (pending sync)'
                    : 'Synced',
              ),
              const SizedBox(height: 8),
              if (customer.flag == 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onTap,
                    child: const Text(
                      'Pay Now',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D1B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
