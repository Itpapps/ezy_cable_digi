import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/config/app_config.dart';
import '../../core/data/customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/network/server_url_resolver.dart';
import '../../core/network/soap_client.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import 'customer_operations.dart';
import '../../core/widgets/premium_dialog.dart';
import '../payment/payment_options_screen.dart';
import 'customer_map_screen.dart';
import 'location_preview_screen.dart';
import 'payment_history_screen.dart';
import '../complaints/complaints_landing_screen.dart';
import '../complaints/complaints_history_screen.dart';
import '../billing/invoice_history_screen.dart';
import '../complaints/package_operations_screen.dart';
import '../complaints/deactivate_stb_screen.dart';
import '../complaints/other_screens.dart';
import '../packages/broadband_list_screen.dart';
import '../packages/custom_packages_home_screen.dart';
import '../packages/ott_screen.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package_operations_repository.dart';
import '../collections/pay_later_dialog.dart';
import '../search/data/search_repository.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Customer customer;
  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper();
  late Customer _customer;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // OTT boxes (Android: getCustomerBoxes `ott_boxes_list`, fetched on load for
  // non-broadband customers). Drives the OTT tile; empty = tile hidden.
  List<CustomerBox> _ottBoxes = const [];

  // Displayed/editable LCO id (Android `lco_cust_no`). The edit updates ONLY this
  // for display; the stable key `_customer.lcoCustomerId` (== customersidd) is
  // kept untouched so every operation keeps using the correct customer id.
  late String _lcoId;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    // "LCO Customer id" shows Android's alt_custom_number (customer-facing LCO id),
    // NOT lcoCustomerId (== customer_id, the internal operation key).
    _lcoId = _customer.altCustomNumber;
    _loadOttBoxes();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  /// Android parity: `CustomerOperations` calls `packageoperations(0)` →
  /// `getCustomerBoxes` on load for non-broadband customers, which supplies
  /// `ott_boxes_list` → the OTT tile. Fire-and-forget; the grid rebuilds when it
  /// returns. Broadband customers use the Renew BroadBand branch instead.
  Future<void> _loadOttBoxes() async {
    if (_customer.broadbandUserId.trim().isNotEmpty) return;
    try {
      final r = await PackageOperationsRepository.instance
          .getCustomerBoxes(_customer.lcoCustomerId);
      if (!mounted || r.ottBoxes.isEmpty) return;
      setState(() => _ottBoxes = r.ottBoxes);
    } catch (_) {
      // Non-fatal — the OTT tile simply won't show.
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _buildAppBar(t),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _buildPrevNextStrip(t),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCustomerInfoCard(t),
                    const SizedBox(height: 12),
                    _buildLocationCard(t),
                    const SizedBox(height: 12),
                    _buildOperationsCard(t),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Prev/Next customer strip (below the AppBar) ─────────────────────────
  // Presentation only: the Prev/Next controls live here instead of the AppBar,
  // so the AppBar shows a standard back button. Taps call the SAME
  // _prevNextCustomer(flag) — no logic/routing change. Expanded halves +
  // Flexible/ellipsis keep it overflow-safe.
  Widget _buildPrevNextStrip(AppThemeConst t) {
    return Material(
      color: t.appBarBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(child: _prevNextChip(t, isPrev: true)),
            const SizedBox(width: 8),
            Expanded(child: _prevNextChip(t, isPrev: false)),
          ],
        ),
      ),
    );
  }

  Widget _prevNextChip(AppThemeConst t, {required bool isPrev}) {
    final row = <Widget>[
      Icon(isPrev ? Icons.chevron_left : Icons.chevron_right,
          size: 20, color: t.backBtnIcon),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          isPrev ? 'Previous Customer' : 'Next Customer',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: t.backBtnIcon, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _prevNextCustomer(isPrev ? 2 : 1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.backBtnBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: isPrev ? row : row.reversed.toList(),
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(AppThemeConst t) {
    return AppBar(
      backgroundColor: t.appBarBg,
      foregroundColor: t.appBarFg,
      elevation: 0,
      centerTitle: true,
      // Standard back button. Prev/Next customer controls moved to a strip below
      // the AppBar (see _buildPrevNextStrip); _prevNextCustomer logic unchanged —
      // only the widgets were relocated.
      leading: IconButton(
        tooltip: 'Back',
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
        'CUSTOMER DETAILS',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: t.appBarFg,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: _openCustomerMap,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.location_on,
                  color: Colors.redAccent, size: 20),
            ),
          ),
        ),
        // Next-customer control moved to the Prev/Next strip below the AppBar.
      ],
    );
  }

  // ── Prev/Next customer navigation (Android CustomerOperations_Fragment) ──
  // ◄ = prev (flag 2) · ► = next (flag 1) → SOAP `prenext` → reopen this screen
  // for the returned customer. Parity: status 0 navigates · 1 = "No Data Found!"
  // dialog · 2 = snackbar + "Contact Support" · 3/transport = "Server is busy…".
  Future<void> _prevNextCustomer(int flag) async {
    final id = int.tryParse(_customer.lcoCustomerId.trim());
    if (id == null) {
      showPremiumSnackBar(context, 'Error, Please try again later.',
          isError: true);
      return;
    }
    // Android ProgressDialog: "Searching...,   Please wait...".
    showPremiumLoading(context, message: 'Searching...   Please wait...');
    final r = await SearchRepository.instance
        .prevNextCustomer(customerId: id, flag: flag);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    if (r.statusCode == 0 && r.customer != null) {
      // Android reopens CustomerOperations_Fragment for the adjacent customer.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailsScreen(customer: r.customer!),
        ),
      );
    } else if (r.statusCode == 1) {
      await _showInfoDialog('No Data Found!', r.statusMessage);
    } else if (r.statusCode == 2) {
      showPremiumSnackBar(
        context,
        r.statusMessage.isEmpty
            ? 'Contact Support'
            : '${r.statusMessage}: Contact Support',
        isError: true,
      );
    } else {
      // status 3 / transport failure.
      await _showInfoDialog(
        'Server is busy or Un reachable!',
        r.statusMessage.isEmpty
            ? 'Please try again after sometime'
            : r.statusMessage,
      );
    }
  }

  Future<void> _showInfoDialog(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body.isEmpty ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Customer Info Card ──────────────────────────────────────────────────
  Widget _buildCustomerInfoCard(AppThemeConst t) {
    return _WhiteCard(
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Customer Name', _customer.name, t),
          _infoRow('Nick Name',
              _customer.nickName.isEmpty ? 'N/A' : _customer.nickName, t),
          _infoRow('Mobile Number', _customer.primaryMobileNumber, t,
              copyable: true, hasCallIcon: true),
          _infoRow('Total Due', _customer.totalDue, t,
              valueColor: AppColors.textPrimary, valueBold: true),
          _infoRow('Amount Payable', _customer.amountPayable, t,
              valueColor: t.accent, valueBold: true),
          _infoRow('Customer Type', _customer.customerTypeLabel, t),
          // Android parity (CustomerMgmt_MakePayment_Fragment:275): CRF shown only
          // when the dealer uses CRF (use_caf == 1).
          if (SessionService.instance.useCaf == 1)
            _infoRow('CRF Number',
                _customer.crfNumber.isEmpty ? 'NA' : _customer.crfNumber, t),
          _infoRow('Group Name',
              _customer.groupName.isEmpty ? 'N/A' : _customer.groupName, t),
          _infoRow('Area Name',
              _customer.areaName.isEmpty ? 'N/A' : _customer.areaName, t),
          _infoRow(
              'Address',
              _customer.address.isEmpty ? 'N/A' : _customer.address, t,
              isLast: true,
              hasMoreIcon: true,
              onMoreTap: _showAddressDialog),
        ],
      ),
    );
  }

  // Decorative leading icon chosen by the row's LABEL only — presentation
  // metadata; does NOT touch the label, value, condition, or callback. Unknown
  // labels fall back to a neutral icon so nothing can break.
  IconData _custRowIcon(String label) {
    switch (label) {
      case 'Customer Name':
        return Icons.person_outline;
      case 'Nick Name':
        return Icons.sentiment_satisfied_outlined;
      case 'Mobile Number':
        return Icons.phone_outlined;
      case 'Total Due':
        return Icons.account_balance_wallet_outlined;
      case 'Amount Payable':
        return Icons.payments_outlined;
      case 'Customer Type':
        return Icons.category_outlined;
      case 'CRF Number':
        return Icons.badge_outlined;
      case 'Group Name':
        return Icons.groups_outlined;
      case 'Area Name':
        return Icons.map_outlined;
      case 'Address':
        return Icons.location_on_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Widget _infoRow(
    String label,
    String value,
    AppThemeConst t, {
    Color? valueColor,
    bool valueBold = false,
    bool copyable = false,
    bool hasCallIcon = false,
    bool hasMoreIcon = false,
    VoidCallback? onMoreTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Decorative leading icon (presentation only — no onTap, no data).
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_custRowIcon(label), size: 15, color: t.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.cardSubtitleText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onMoreTap,
                        child: Text(
                          value,
                          // Android parity: the address is shown truncated with a
                          // "more" affordance; the full text opens in a popup.
                          maxLines: hasMoreIcon ? 1 : null,
                          overflow:
                              hasMoreIcon ? TextOverflow.ellipsis : TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: valueBold ? FontWeight.w800 : FontWeight.w700,
                            color: valueColor ?? t.cardBodyText,
                          ),
                        ),
                      ),
                    ),
                    if (hasCallIcon)
                      GestureDetector(
                        onTap: () => _confirmAndCall(value),
                        child: const Icon(Icons.call, size: 15, color: Colors.green),
                      ),
                    if (hasCallIcon) const SizedBox(width: 6),
                    if (copyable)
                      GestureDetector(
                        onTap: () => _showUpdateMobileDialog(value),
                        child: const Icon(Icons.edit, size: 15, color: Color(0xFF9CA3AF)),
                      ),
                    if (hasMoreIcon)
                      GestureDetector(
                        onTap: onMoreTap,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(Icons.more_vert, size: 15, color: t.accent),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, thickness: 0.5, color: t.dividerColor),
      ],
    );
  }

  // ── Location Card ────────────────────────────────────────────────────────
  Widget _buildLocationCard(AppThemeConst t) {
    return _WhiteCard(
      t: t,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 6),
              Text(
                'LOCATION',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: t.accent,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          Divider(color: t.accent, thickness: 1.2),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _locCell(
                  _customer.lastPaidDate.trim().isEmpty
                      ? 'N/A'
                      : _customer.lastPaidDate,
                  'Last Paid Date',
                  t: t,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _locCell(
                  _customer.billMonth.trim().isEmpty ? 'NA' : _customer.billMonth,
                  'Bill Month',
                  t: t,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _locCell(
                  _lcoId,
                  'LCO Customer id',
                  t: t,
                  hasEditIcon: true,
                  onEditTap: _showUpdateLcoDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _locCell(
                  _customer.boxNumber.trim().isEmpty ? 'NA' : _customer.boxNumber,
                  'Box Number',
                  t: t,
                  valueColor: Colors.green.shade600,
                  copyable: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _locCell(
                  _customer.vcNumber.trim().isEmpty ? 'NA' : _customer.vcNumber,
                  'VC Number',
                  t: t,
                  valueColor: Colors.green.shade600,
                  copyable: true,
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // Copy a value to the clipboard and confirm with a brief snackbar. Clipboard
  // is a safe Flutter API (no permissions); guarded so it never throws.
  void _copyValue(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Widget _locCell(
    String value,
    String label, {
    Color? valueColor,
    bool hasEditIcon = false,
    bool copyable = false,
    VoidCallback? onEditTap,
    required AppThemeConst t,
  }) {
    final canCopy =
        copyable && value.trim().isNotEmpty && value.trim() != 'N/A';
    final valueRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
            // Flexible + ellipsis so long values (VC/Box numbers, dates) never
            // overflow the column on narrow screens — responsive on all sizes.
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? t.accent,
                ),
              ),
            ),
            if (hasEditIcon) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: Color(0xFF9CA3AF)),
            ],
            if (canCopy) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _copyValue(value.trim(), label),
                behavior: HitTestBehavior.opaque,
                child: Icon(Icons.copy_rounded, size: 14, color: t.accent),
              ),
            ],
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Android parity: the LCO id value is itself tappable to open the edit
          // dialog (tv_lcocustomerno.setOnClickListener). Cells without onEditTap
          // stay non-interactive.
          onEditTap != null
              ? GestureDetector(
                  onTap: onEditTap,
                  behavior: HitTestBehavior.opaque,
                  child: valueRow,
                )
              : valueRow,
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: t.cardSubtitleText,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Operations Card ────────────────────────────────────────────────────
  Widget _buildOperationsCard(AppThemeConst t) {
    // Android parity: computed once from the current customer + session flags
    // (CustomerOperations_Fragment). Entry-driven — rebuilds on next open, not
    // in place (Android navigates away after state-changing operations).
    final ops = buildCustomerOperations(_customer, SessionService.instance,
        hasOttBoxes: _ottBoxes.isNotEmpty);

    return _WhiteCard(
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUSTOMER OPERATIONS',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: t.accent, letterSpacing: 0.4),
          ),
          Divider(color: t.accent, thickness: 1.2),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.88,
              mainAxisSpacing: 10,
              crossAxisSpacing: 6,
            ),
            itemCount: ops.length,
            itemBuilder: (_, i) => _OpItem(
              icon: ops[i].icon,
              label: ops[i].label,
              gradientColors: ops[i].gradientColors,
              t: t,
              onTap: () => _handleOp(ops[i].label),
            ),
          ),
        ],
      ),
    );
  }

  void _handleOp(String label) {
    switch (label) {
      case 'Make Payments':
        // Android payment-permission guard (CustomerOperations_Fragment:1707-1742):
        // SERVICE user or make_payment=="0" → access denied. Centralized in
        // SessionService.canMakePayment (reused at any future payment entry).
        if (!SessionService.instance.canMakePayment) {
          showPremiumConfirm(
            context: context,
            title: 'Access denied!',
            body: 'You have no access to do payments.',
            confirmLabel: 'OK',
            cancelLabel: 'Close',
          );
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentOptionsScreen(customer: _customer)));
        }
        break;
      case 'Update Location':
        _showUpdateLocationDialog();
        break;
      case 'Payment History':
        Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentHistoryScreen(customer: _customer)));
        break;
      case 'Create Complaints':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ComplaintsLandingScreen(customer: _customer)));
        break;
      case 'Complaint History':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ComplaintHistoryScreen(customer: _customer)));
        break;
      case 'Invoice History':
        Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceHistoryScreen(customer: _customer)));
        break;
      case 'Package Operations':
        Navigator.push(context, MaterialPageRoute(builder: (_) => PackageOperationsScreen(customer: _customer)));
        break;
      case 'Deactivate STB':
        Navigator.push(context, MaterialPageRoute(builder: (_) => DeactivateStbScreen(customer: _customer)));
        break;
      case 'Temporary Activation':
        _handleTemporaryActivation();
        break;
      case 'Renew Services':
        _handleRenewServices();
        break;
      case 'Unpaid Customer Activation':
        _handleUnpaidActivation();
        break;
      case 'Renew BroadBand':
        Navigator.push(context, MaterialPageRoute(builder: (_) => BroadBandListScreen(customer: _customer)));
        break;
      case 'OTT':
        Navigator.push(context, MaterialPageRoute(builder: (_) => OttScreen(customer: _customer, ottBoxes: _ottBoxes)));
        break;
      case 'Custom Packages':
        // Android guard (CustomerOperations_Fragment:886): SERVICE or BroadBand-only.
        if (SessionService.instance.userType.toUpperCase() == 'SERVICE' ||
            _customer.customerType.trim() == '1') {
          showPremiumConfirm(
            context: context,
            title: 'Access denied!',
            body: 'You have no access ',
            confirmLabel: 'OK',
            cancelLabel: 'Close',
          );
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomPackagesHomeScreen(customer: _customer)));
        }
        break;
      case 'Act-Deact Report':
        Navigator.push(context, MaterialPageRoute(builder: (_) => ActDeactReportScreen(customer: _customer)));
        break;
      case 'One Time Charges':
        Navigator.push(context, MaterialPageRoute(builder: (_) => OneTimeChargesScreen(customer: _customer)));
        break;
      case 'One Time History':
        Navigator.push(context, MaterialPageRoute(builder: (_) => OneTimeHistoryScreen(customer: _customer)));
        break;
      case 'Pay Later':
        // Android parity: the per-customer Pay Later is a dialog (gethitapipaylater),
        // not a screen. Shared with the payment screen; reuses PayLaterRepository.
        showPayLaterScheduleDialog(context, _customer);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label coming soon')));
    }
  }

  /// Temporary Activation — Android parity (CustomerOperations_Fragment
  /// :1210-1261 + TemporaryActivation_stb :3326-3427). Access guard → confirm →
  /// POST stbTemporaryActivation → result dialog. Android popBackStacks on BOTH
  /// success and a status_code==1 rejection; only a transport error stays (Toast).
  Future<void> _handleTemporaryActivation() async {
    final s = SessionService.instance;
    // Guard (:1213): SERVICE user or BroadBand-only (customer_type == "1").
    if (s.userType.toUpperCase() == 'SERVICE' ||
        _customer.customerType.trim() == '1') {
      await showPremiumConfirm(
        context: context,
        title: 'Access denied!',
        body: 'You have no access .',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
      return;
    }
    // Confirm (:1232).
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Temporary Activation',
      body: 'Are you sure you want to Activate?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
    );
    if (ok != true || !mounted) return;

    final result = await PackageOperationsRepository.instance
        .stbTemporaryActivation(customerId: _customer.lcoCustomerId);
    if (!mounted) return;

    // Transport failure → Android Toast "Failed.", stays on screen.
    if (result.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    // status 0 (Success!) and status 1 (Temporary Activation Failed!) both show a
    // dialog then popBackStack — mirror by popping the details screen after OK.
    await showPremiumConfirm(
      context: context,
      title: result.isSuccess ? 'Success!' : 'Temporary Activation Failed!',
      body: result.statusMessage.trim().isEmpty
          ? (result.isSuccess ? 'Success' : 'Failed')
          : result.statusMessage,
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Renew Services (STB) — Android parity (CustomerOperations_Fragment
  /// :1262-1312 + renewal() :2870-2968). Access guard → confirm → POST
  /// packageRenew → result dialog. Android navigates to the Dashboard on BOTH
  /// success and a status_code==1 rejection; only a transport error stays.
  Future<void> _handleRenewServices() async {
    final s = SessionService.instance;
    // Guard (:1265): SERVICE user or BroadBand-only (customer_type == "1").
    if (s.userType.toUpperCase() == 'SERVICE' ||
        _customer.customerType.trim() == '1') {
      await showPremiumConfirm(
        context: context,
        title: 'Access denied!',
        body: 'You have no access .',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
      return;
    }
    // Confirm (:1284).
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Renew Packages',
      body: 'Are you sure you want to renew your package?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
    );
    if (ok != true || !mounted) return;

    final result = await PackageOperationsRepository.instance
        .packageRenew(customerId: _customer.lcoCustomerId);
    if (!mounted) return;

    // Transport failure → Android Toast "Failed.", stays on screen.
    if (result.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    // status 0 (Success!) and status 1 (Failed!) both show a dialog then
    // startActivity(MainActivity) → Dashboard. Mirror by returning to the root
    // (Dashboard is the root route — login pushReplaces it).
    await showPremiumConfirm(
      context: context,
      title: result.isSuccess ? 'Success!' : 'Failed!',
      body: result.statusMessage.trim().isEmpty
          ? (result.isSuccess ? 'Success' : 'Failed')
          : result.statusMessage,
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Unpaid Customer Activation — Android parity (CustomerOperations_Fragment
  /// :1159-1208 + UnpaidActivation_stb_CUstomer :3225-3320). Access guard →
  /// confirm → POST unpaidCustomerActivation → result dialog → popBackStack on
  /// BOTH success and status_code==1 ("No Details Found!"); transport error stays.
  Future<void> _handleUnpaidActivation() async {
    final s = SessionService.instance;
    // Guard (:1162): SERVICE user or BroadBand-only (customer_type == "1").
    if (s.userType.toUpperCase() == 'SERVICE' ||
        _customer.customerType.trim() == '1') {
      await showPremiumConfirm(
        context: context,
        title: 'Access denied!',
        body: 'You have no access .',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
      return;
    }
    // Confirm (:1181).
    final ok = await showPremiumConfirm(
      context: context,
      title: 'Unpaid Customer Activation',
      body: 'Are you sure you want to activate?',
      confirmLabel: 'Yes',
      cancelLabel: 'No',
    );
    if (ok != true || !mounted) return;

    final result = await PackageOperationsRepository.instance
        .unpaidCustomerActivation(customerId: _customer.lcoCustomerId);
    if (!mounted) return;

    // Transport failure → Android Toast "Failed.", stays on screen.
    if (result.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
      return;
    }
    // status 0 (Success!) and status 1 (No Details Found!) both show a dialog
    // then popBackStack — mirror by popping the details screen after OK.
    await showPremiumConfirm(
      context: context,
      title: result.isSuccess ? 'Success!' : 'No Details Found!',
      body: result.statusMessage.trim().isEmpty
          ? (result.isSuccess ? 'Success' : 'No Details Found')
          : result.statusMessage,
      confirmLabel: 'OK',
      cancelLabel: 'Close',
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showUpdateMobileDialog(String currentMobile) async {
    final controller = TextEditingController(text: currentMobile);
    final result = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Update Mobile', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              Text('Current: $currentMobile', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'New mobile number',
                  hintStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('UPDATE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true) return;
    final newMobile = controller.text.trim();
    if (newMobile.isEmpty || newMobile == currentMobile) return;
    setState(() { _customer = _customer.copyWith(primaryMobileNumber: newMobile); });
    // NOTE: do NOT dispose `controller` here. The dialog has a 260ms exit
    // animation, so the TextField using this controller is still mounted when
    // this line runs. Disposing now makes the TextField's later teardown call
    // removeListener() on a disposed controller → "used after being disposed"
    // crash. The TextField removes its own listener on teardown and the local
    // controller is then garbage-collected.
  }

  // ── Update LCO Customer id ────────────────────────────────────────────────
  // Android parity (CustomerOperations_Fragment: tap LCO id → row_updatelcoidview
  // → update_Lco_or_mobile(newLco,"") → POST updateMobileAndLCOCustID). The API
  // keys on the STABLE customerId (== _customer.lcoCustomerId / customersidd),
  // which we never mutate; only the on-screen value (_lcoId) changes on success.
  Future<void> _showUpdateLcoDialog() async {
    final controller = TextEditingController(text: _lcoId);
    final result = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Update LCO id',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              Text('Present Lco Id: $_lcoId',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'New LCO id',
                  hintStyle: const TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('CANCEL',
                          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('UPDATE',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true) return;
    final newLco = controller.text.trim();
    // Android validation (row_updatelcoidview): LCO id must be >= 5 chars.
    if (newLco.length < 5) {
      if (mounted) showPremiumSnackBar(context, 'Please enter valid Lco Id', isError: true);
      return;
    }
    if (newLco == _lcoId) return;
    if (!mounted) return;

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showPremiumLoading(context, message: 'Updating...');
    final res = await PackageOperationsRepository.instance.updateLcoCustomerId(
      customerId: _customer.lcoCustomerId, // stable key — never the edited value
      newLcoId: newLco,
    );
    if (!mounted) return;
    nav.pop(); // dismiss loader
    if (res.isSuccess) {
      setState(() => _lcoId = newLco);
    }
    messenger.showSnackBar(SnackBar(
      content: Text(res.isSuccess
          ? (res.statusMessage.isEmpty ? 'LCO id updated successfully' : res.statusMessage)
          : (res.statusMessage.isEmpty ? 'Update failed' : res.statusMessage)),
      backgroundColor: res.isSuccess ? Colors.green.shade600 : Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
    // Do NOT dispose `controller` — the dialog's exit animation keeps the
    // TextField mounted briefly (same reasoning as _showUpdateMobileDialog).
  }

  Future<void> _confirmAndCall(String mobile) async {
    if (mobile.isEmpty) return;
    final shouldCall = await showPremiumConfirm(
      context: context,
      title: 'Make a Call',
      body: 'Call $mobile?',
      confirmLabel: 'CALL',
      cancelLabel: 'CANCEL',
    );
    if (!shouldCall) return;
    final uri = Uri(scheme: 'tel', path: mobile);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      showPremiumSnackBar(context, 'Unable to open dialer', isError: true);
    }
  }

  // Android parity (custoper_tv_address click): show the full address in a popup
  // titled "Address of {name}" with a single OK button.
  Future<void> _showAddressDialog() async {
    final addr = _customer.address.trim();
    await showPremiumDialog<void>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Address of ${_customer.name}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(addr.isEmpty ? 'N/A' : addr,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUpdateLocationDialog() async {
    final controller = TextEditingController(text: _customer.areaName);
    final confirmed = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Iconsax.location, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Update Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Enter area name',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Iconsax.location, size: 18),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('PROCEED', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final areaName = controller.text.trim();
    if (areaName.isEmpty) return;
    controller.dispose();

    // ── GPS fetch ────────────────────────────────────────────────────────
    // mounted is guaranteed here — no await has occurred in this code path yet.
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final nav       = Navigator.of(context);
    // ignore: use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    // ignore: use_build_context_synchronously
    showPremiumLoading(context, message: 'Getting GPS location...');
    late double lat, lng;
    try {
      final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      lat = position.latitude;
      lng = position.longitude;
      if (!mounted) return;
      nav.pop(); // dismiss loading
    } catch (e) {
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text('Location failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
      return;
    }

    // ── Location preview push ─────────────────────────────────────────────
    if (!mounted) return;
    final previewAccepted = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => LocationPreviewScreen(
          customerName: _customer.name,
          areaName: areaName,
          location: LatLng(lat, lng),
        ),
      ),
    );
    if (previewAccepted != true || !mounted) return;

    // ── Save confirm ──────────────────────────────────────────────────────
    final shouldSave = await showPremiumConfirm(
      context: context,
      title: 'Save Location',
      body: 'Save GPS location for ${_customer.name}?',
      confirmLabel: 'SAVE',
    );
    if (!shouldSave || !mounted) return;

    // ── Save to DB ────────────────────────────────────────────────────────
    // Re-capture nav (may still be same, but safe after another async gap)
    final nav2       = Navigator.of(context);
    final messenger2 = ScaffoldMessenger.of(context);
    showPremiumLoading(context, message: 'Saving location...');
    try {
      // ── Local DB ──
      await _db.updateCustomerLocation(
        lcoCustomerId: _customer.lcoCustomerId,
        areaName: areaName,
        latitude: lat,
        longitude: lng,
      );

      // ── Server SOAP (Android: updateCustomerlocation via wsController) ──
      // Android sends customerid as int (altCustId = getCustomerId()).
      // Flutter lcoCustomerId holds the same numeric value as a String.
      bool soapFailed = false;
      try {
        final ns = ServerUrlResolver.instance.namespace;
        await SoapClient.instance.call(
          url: ServerUrlResolver.instance.loginServerUrl,
          namespace: ns,
          soapAction: '$ns/updateCustomerlocation',
          methodName: 'updateCustomerlocation',
          wrapper: 'updateCustomerlocationInfo',
          wrapperType: 'updateCustomerlocationInfo',
          fields: {
            'authToken': SessionService.instance.authToken,
            'imei': AppConfig.deviceImei,
            'customerid': int.tryParse(_customer.lcoCustomerId) ?? 0,
            'lat': lat.toString(),
            'lang': lng.toString(),
          },
        );
      } catch (_) {
        // Server sync failed — local save is still good.
        soapFailed = true;
      }

      if (!mounted) return;
      nav2.pop();
      messenger2.showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            soapFailed ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            color: Colors.white, size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            soapFailed
                ? 'Location saved locally (server sync failed)'
                : 'Location saved successfully',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ]),
        backgroundColor: soapFailed ? Colors.orange.shade700 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      setState(() {
        _customer = _customer.copyWith(areaName: areaName, latitude: lat, longitude: lng);
      });
    } catch (e) {
      if (mounted) {
        nav2.pop();
        messenger2.showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  Future<void> _openCustomerMap() async {
    if (_customer.latitude == null || _customer.longitude == null) {
      showPremiumSnackBar(context, 'Update customer location first', isError: true);
      return;
    }
    // Capture navigator before async gap
    final nav = Navigator.of(context);
    showPremiumLoading(context, message: 'Getting your location...');
    try {
      final current = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => CustomerMapScreen(
            customer: _customer,
            currentLocation: LatLng(current.latitude, current.longitude),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        nav.pop();
        showPremiumSnackBar(context, 'Location error: $e', isError: true);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WhiteCard extends StatelessWidget {
  final Widget child;
  final AppThemeConst t;
  const _WhiteCard({required this.child, required this.t});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: t.cardBorderRadius,
          boxShadow: [
            BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}

class _OpItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final AppThemeConst t;
  final VoidCallback onTap;

  const _OpItem({
    required this.icon,
    required this.label,
    required this.gradientColors,
    required this.t,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Presentation-only overflow guard: the grid cell has a fixed height
      // (childAspectRatio), so under large accessibility fonts / very narrow
      // phones the icon + 2-line label can exceed the cell and throw a
      // RenderFlex overflow. FittedBox(scaleDown) shrinks the whole tile to fit
      // when needed and is a no-op at normal sizes (identical look). The inner
      // SizedBox keeps the label's 2-line wrap — FittedBox alone would give the
      // Text unbounded width and collapse it to a single line.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.last.withValues(alpha: 0.30),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: gradientColors.first,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}