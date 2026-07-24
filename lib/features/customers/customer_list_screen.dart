import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/data/customer.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../customer/customer_map_screen.dart';
import '../payment/payment_options_screen.dart';
import 'customer_list_provider.dart';
import 'paid_customers_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomerListScreen — reads from CustomerListProvider (ChangeNotifier).
// No local data state — all list, pagination, filters owned by the provider.
// Navigating back and returning does NOT re-fetch — the data stays in memory.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  // Android tv_advsearch: bill-month / customer-status / STB-status hidden until
  // "Advanced Search" is tapped.
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Kick off initial fetch (no-op if already loaded)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<CustomerListProvider>();
      p.initialLoad();
      p.loadGroups(); // dealer groups (dg) → Group filter dropdown
    });

    // Pagination — load more when user scrolls to the bottom
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        context.read<CustomerListProvider>().fetch();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
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
        shape: Border(bottom: BorderSide(color: t.appBarBorderColor, width: 1)),
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
          'CUSTOMER LIST',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              letterSpacing: 1.2, color: t.appBarFg),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: t.tabBarActiveColor,
          labelColor: t.tabBarActiveColor,
          unselectedLabelColor: t.subtitleText,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'UNPAID LIST'),
            Tab(text: 'PAID LIST'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              _buildFilters(t),
              Expanded(child: _buildCustomerList(t)),
            ],
          ),
          // Real Paid list (Android CustomerPay_Tab_Fragment "Paid List" tab) —
          // reuses PaidCustomersScreen (gpcd, month picker) in embedded mode.
          const PaidCustomersScreen(embedded: true),
        ],
      ),
    );
  }

  // ── Filter row ──────────────────────────────────────────────────────────────
  Widget _buildFilters(AppThemeConst t) {
    return Consumer<CustomerListProvider>(
      builder: (context, provider, _) {
        return Container(
          margin: const EdgeInsets.fromLTRB(
              AppSizes.paddingM, AppSizes.paddingM, AppSizes.paddingM, 0),
          padding: const EdgeInsets.all(AppSizes.paddingM),
          decoration: BoxDecoration(
            color: t.cardBg,
            borderRadius: t.cardBorderRadius,
            boxShadow: [
              BoxShadow(color: t.cardShadowColor, blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FILTERS', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w900,
                color: t.accent, letterSpacing: 0.8,
              )),
              const SizedBox(height: 10),
              // Row 1 — always visible (Android sp_paidunpaid + sp_group).
              Row(children: [
                Expanded(child: _FilterDrop(
                  label: 'Paid / Unpaid',
                  value: provider.paidUnpaid,
                  items: CustomerListProvider.paidUnpaidOptions,
                  accent: t.accent,
                  onChanged: (v) =>
                      context.read<CustomerListProvider>().setPaidUnpaid(v),
                )),
                const SizedBox(width: 12),
                Expanded(child: _FilterDrop(
                  label: 'Group',
                  value: provider.group,
                  items: provider.groupNames,
                  accent: t.accent,
                  onChanged: (v) =>
                      context.read<CustomerListProvider>().setGroup(v),
                )),
              ]),
              const SizedBox(height: 8),
              // Advanced Search toggle (Android tv_advsearch / tv_advsearch1).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: t.accent),
                      const SizedBox(width: 4),
                      Text(
                        _advancedOpen ? 'Hide Advanced Search' : 'Advanced Search',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.accent),
                      ),
                    ],
                  ),
                ),
              ),
              if (_advancedOpen) ...[
                const SizedBox(height: 8),
                // Bill month (Android ll_seldat) — reuses the month-picker pattern.
                Text('Bill Month', style: TextStyle(
                    fontSize: 11, color: t.subtitleText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: provider.billMonth,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      helpText: 'Select bill month',
                    );
                    if (picked != null && context.mounted) {
                      context.read<CustomerListProvider>().setBillMonth(picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.inputBorderColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_month, size: 18, color: t.accent),
                      const SizedBox(width: 8),
                      Text('${provider.billMonth.month}-${provider.billMonth.year}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: t.bodyText)),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _FilterDrop(
                    label: 'Customer Status',
                    value: provider.customerStatus,
                    items: CustomerListProvider.customerStatusOptions,
                    accent: t.accent,
                    onChanged: (v) =>
                        context.read<CustomerListProvider>().setCustomerStatus(v),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _FilterDrop(
                    label: 'STB Status',
                    value: provider.stbStatus,
                    items: CustomerListProvider.stbStatusOptions,
                    accent: t.accent,
                    onChanged: (v) =>
                        context.read<CustomerListProvider>().setStbStatus(v),
                  )),
                ]),
                const SizedBox(height: 12),
                // Search — applies the advanced filters (Android tv_search).
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        context.read<CustomerListProvider>().applySearch(),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Customer List ────────────────────────────────────────────────────────────
  Widget _buildCustomerList(AppThemeConst t) {
    return Consumer<CustomerListProvider>(
      builder: (context, provider, _) {
        // Loading — initial load OR any dropdown/advanced-search apply. Mirrors
        // Android's getunpaiddata ProgressDialog: a clear loader on every fetch.
        // Crash-safe: fetch() try/catches → statusCode 3 → the error state below.
        if (provider.isLoading) {
          return Center(child: CircularProgressIndicator(color: t.accent));
        }

        // Empty / error — mirrors Android Unpaid_Fragment titles:
        //   statusCode==1 → "No Records Found!"   statusCode==3 → "Data Loading Failed!"
        if (provider.customers.isEmpty && !provider.isLoading) {
          final isError = provider.statusCode == 3;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isError ? Icons.error_outline : Iconsax.user_search,
                    size: 52, color: t.emptyStateIconColor),
                const SizedBox(height: 12),
                Text(isError ? 'Data Loading Failed!' : 'No Records Found!',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: t.bodyText)),
                if (provider.statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(provider.statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: t.bodyText)),
                  ),
                ],
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () =>
                      context.read<CustomerListProvider>().refresh(),
                  child: Text('Retry', style: TextStyle(color: t.accent)),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingM, AppSizes.paddingS, AppSizes.paddingM, 24),
          // index 0 = "Total Count" header; then the customers; then bottom loader.
          itemCount: provider.customers.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              // Android parity (Unpaid_Fragment: tv_total = "Total Count  N",
              // N = the full unpaid list size).
              return Padding(
                padding: const EdgeInsets.only(left: 4, top: 2, bottom: 8),
                child: Text(
                  'Total Count  ${provider.customers.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.bodyText,
                  ),
                ),
              );
            }
            final custIndex = index - 1;
            if (custIndex < provider.customers.length) {
              return _CustomerTile(
                  customer: provider.customers[custIndex], t: t);
            }
            return provider.isLoading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: t.loadingColor)),
                  )
                : const SizedBox.shrink();
          },
        );
      },
    );
  }
}

// ── Customer tile card ──────────────────────────────────────────────────────────
class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final AppThemeConst t;
  const _CustomerTile({required this.customer, required this.t});

  @override
  Widget build(BuildContext context) {
    final hasLoc = customer.latitude != null && customer.longitude != null;
    final hasPending = customer.pendingAmount.isNotEmpty &&
        customer.pendingAmount != '₹0' && customer.pendingAmount != '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white, // Bottom part is white
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header row (Light Blue-Grey Background) ──────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFE2E9F4), // visible light-blue header (was near-white)
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFD5DFF0), width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44, height: 44,
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
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(customer.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700,
                              color: Color(0xFF0D1B4B))),
                      if (customer.altCustomerId.isNotEmpty)
                        Text(customer.altCustomerId,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500,
                                color: Colors.black54)),
                    ],
                  ),
                ),
                // (Removed: raw customer_type badge "0/1/2" — Android's
                // UnpaidFrag_Adapter row does NOT show a customer-type badge; it
                // only uses customer_type internally to pass to Make Payment.)
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
                _row(Iconsax.timer_1, 'Pending Amount',
                    customer.pendingAmount.isEmpty ? '₹0' : customer.pendingAmount,
                    valueColor: hasPending ? const Color(0xFFD32F2F) : const Color(0xFF1AA95A)),
                const SizedBox(height: 8),
                _row(Iconsax.calendar_tick, 'Last Paid Date',
                    customer.lastPaidDate.isEmpty ? '—' : customer.lastPaidDate),
                const SizedBox(height: 8),
                _row(Iconsax.home, 'Address',
                    customer.address.isEmpty ? '—' : customer.address),

                const SizedBox(height: 14),

                // Buttons
                Row(
                  children: [
                    // Pay → Make Payment, gated by make_payment (Android
                    // UnpaidFrag_Adapter tv_pay:131-206). Same guard as the
                    // dashboard Unpaid row.
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!SessionService.instance.canMakePayment) {
                            showPremiumConfirm(
                              context: context,
                              title: 'Access denied!',
                              body: 'You have no access to do payments.',
                              confirmLabel: 'OK',
                              cancelLabel: 'Close',
                            );
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PaymentOptionsScreen(customer: customer)));
                          }
                        },
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32), // green — Pay
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payment, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Pay',
                                  style: TextStyle(color: Colors.white, fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Android's UnpaidFrag_Adapter row has only "Pay" (tv_pay) —
                    // no View Details. Removed for parity. Map kept as a location
                    // shortcut (harmless extra).
                    if (hasLoc) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => CustomerMapScreen(
                                  customer: customer,
                                  currentLocation: LatLng(customer.latitude!, customer.longitude!),
                                ))),
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE4E4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Iconsax.location,
                              color: Color(0xFFD32F2F), size: 22),
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
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF0D1B4B),
              )),
        ),
      ],
    );
  }
}

// ── Filter dropdown ─────────────────────────────────────────────────────────────
class _FilterDrop extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final Color accent;
  final ValueChanged<String> onChanged;

  const _FilterDrop({
    required this.label,
    required this.value,
    required this.items,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: Icon(Iconsax.arrow_down_1, size: 16, color: accent),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => onChanged(v!),
          ),
        ),
      ],
    );
  }
}