import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/session_service.dart';
import 'data/customer_location_repository.dart';
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
import '../dashboard/dashboard_refresh_signal.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

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

  // OTT boxes (Android: getCustomerBoxes `ott_boxes_list`). Drives the OTT tile;
  // empty = tile hidden.
  List<CustomerBox> _ottBoxes = const [];

  // Regular STB boxes from the same getCustomerBoxes call. Each carries
  // `boxStatus`, which drives the per-box Box/VC colouring below (Android
  // CustomerOperations_Fragment:2664-2691). Empty = fall back to the flat
  // `_customer.boxNumber` / `.vcNumber` string in a single colour.
  List<CustomerBox> _boxes = const [];

  int _selectedBoxIndex = 0;
  CustomerBox? get _selectedBox =>
      _boxes.length > 1 ? _boxes[_selectedBoxIndex] : null;

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
    _loadCustomerBoxes();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptLocationIfMissing());
  }

  /// Android parity: `CustomerOperations` calls `packageoperations(0)` →
  /// `getCustomerBoxes` on load, which supplies `ott_boxes_list` (→ the OTT tile)
  /// and the regular box list (→ per-box Box/VC colouring).
  ///
  /// NOT gated on broadband: Android renders the coloured box list for
  /// "STB & BroadBand" customers too (verified against a production device —
  /// a customer with a BroadBand User Id still shows red/green box numbers).
  /// Fire-and-forget; the grid rebuilds when it returns.
  Future<void> _loadCustomerBoxes() async {
    try {
      final r = await PackageOperationsRepository.instance
          .getCustomerBoxes(_customer.lcoCustomerId);
      if (!mounted) return;
      if (r.ottBoxes.isEmpty && r.boxes.isEmpty) return;
      setState(() {
        _ottBoxes = r.ottBoxes;
        _boxes = r.boxes;
        _selectedBoxIndex = 0;
      });
    } catch (_) {
      // Non-fatal — the OTT tile stays hidden and Box/VC fall back to the flat
      // single-colour string.
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
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
                    if (_boxes.length > 1) ...[
                      _buildSelectBoxCard(t),
                      const SizedBox(height: 12),
                    ],
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
    // D7 / Android prev/next (CustomerOperations_Fragment :2087): non-cancellable
    // "Searching...,   Please wait..."; prevNextCustomer never throws.
    showPremiumLoading(context,
        message: 'Searching...,   Please wait...', canPop: false);
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
          Builder(builder: (_) {
            final boxSpans = _boxSpans((b) => b.boxNumber);
            final vcSpans = _boxSpans((b) => b.vcNumber);
            // Generous line budget: the cells below are wide enough that each
            // box/VC number normally occupies ONE line, so this only comes into
            // play if a value is unusually long — in which case it wraps rather
            // than being silently ellipsised. Still bounded.
            final boxCount = _selectedBox != null ? 1 : _boxes.length;
            final lines = _boxes.isEmpty ? 2 : (boxCount * 2).clamp(2, 8);
            // Android keeps Box | VC | CRF on one row, but on a phone-width
            // screen three columns give each cell ~98pt while a 10-digit box
            // number needs 120pt and the CRF needs 132pt — so a third of the row
            // cannot show them without truncating. Box/VC therefore share a
            // 2-column row (~141pt of text each, one line per box, matching
            // Android's stacked red/green look) and CRF takes the full-width row
            // beneath. Field order (Box -> VC -> CRF) and every value are kept.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _locCell(
                        _customer.boxNumber.trim().isEmpty
                            ? 'NA'
                            : _customer.boxNumber,
                        'Box Number',
                        t: t,
                        // Flat fallback stays green until the per-box list arrives.
                        valueColor: Colors.green.shade600,
                        valueSpans: boxSpans,
                        maxLines: lines,
                        copyable: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _locCell(
                        _customer.vcNumber.trim().isEmpty
                            ? 'NA'
                            : _customer.vcNumber,
                        'VC Number',
                        t: t,
                        valueColor: Colors.green.shade600,
                        valueSpans: vcSpans,
                        maxLines: lines,
                        copyable: true,
                      ),
                    ),
                  ],
                ),
                // Android gates CRF on use_caf == 1 (CustomerOperations_Fragment
                // :274-278). On its own row there is no neighbouring column whose
                // width depends on it, so it is omitted entirely when hidden.
                if (SessionService.instance.useCaf == 1) ...[
                  const SizedBox(height: 6),
                  _locCell(
                    _customer.crfNumber.trim().isEmpty
                        ? 'NA'
                        : _customer.crfNumber,
                    'CRF No.',
                    t: t,
                    maxLines: lines,
                    copyable: true,
                  ),
                ],
              ],
            );
          }),
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

  // Exact Android colours (CustomerOperations_Fragment:2673/2680).
  static const Color _boxActive = Color(0xFF76BE2F); // #76be2f
  static const Color _boxInactive = Color(0xFFFF554F); // #ff554f

  /// One span per box, coloured by that box's own `boxStatus` — Android's rule
  /// is `box_status == "1"` → green, anything else → red, and the VC number is
  /// coloured by the SAME box's status (CustomerOperations_Fragment:2669-2684).
  /// When multi-box with a selected box, shows ONLY the selected box's value
  /// (Android parity: updateSelectedBox sets tv_boxnum/tv_vcnum to the single
  /// selected box). When single-box or no selection, shows all boxes
  /// newline-separated so each gets its own line.
  List<TextSpan>? _boxSpans(String Function(CustomerBox) pick) {
    if (_boxes.isEmpty) return null;
    if (_selectedBox != null) {
      final text = pick(_selectedBox!).trim();
      if (text.isEmpty) return null;
      return [
        TextSpan(
          text: text,
          style: TextStyle(
            color: _selectedBox!.isActive ? _boxActive : _boxInactive,
          ),
        ),
      ];
    }
    final spans = <TextSpan>[];
    for (final b in _boxes) {
      final text = pick(b).trim();
      if (text.isEmpty) continue;
      spans.add(TextSpan(
        text: spans.isEmpty ? text : '\n$text',
        style: TextStyle(
          color: b.boxStatus.trim() == '1' ? _boxActive : _boxInactive,
        ),
      ));
    }
    return spans.isEmpty ? null : spans;
  }

  Widget _locCell(
    String value,
    String label, {
    Color? valueColor,
    bool hasEditIcon = false,
    bool copyable = false,
    VoidCallback? onEditTap,
    required AppThemeConst t,
    /// When supplied, the value is rendered as rich text instead of a single
    /// coloured string — used by Box/VC to colour each box by its own status
    /// (Android does the same with `<font>` tags + Html.fromHtml).
    List<TextSpan>? valueSpans,
    /// Line cap before ellipsis. Grows with the number of boxes so 3-4 boxes
    /// still fit, while staying bounded so the row can never overflow.
    int maxLines = 2,
  }) {
    final canCopy =
        copyable && value.trim().isNotEmpty && value.trim() != 'N/A';
    final valueRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
            // Flexible + ellipsis so long values (VC/Box numbers, dates) never
            // overflow the column on narrow screens — responsive on all sizes.
            Flexible(
              child: Text.rich(
                valueSpans == null
                    ? TextSpan(text: value)
                    : TextSpan(children: valueSpans),
                maxLines: maxLines,
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

  // ── Select Box Card (multi-box only) ────────────────────────────────────
  Widget _buildSelectBoxCard(AppThemeConst t) {
    final box = _boxes[_selectedBoxIndex];
    final active = box.isActive;
    final statusColor = active ? const Color(0xFF76BE2F) : const Color(0xFFFF554F);
    return _WhiteCard(
      t: t,
      child: InkWell(
        onTap: () => _showBoxSelectionSheet(t),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Iconsax.box_1, size: 20, color: t.accent),
                const SizedBox(width: 8),
                Text('SELECT BOX',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: t.accent, letterSpacing: 0.4)),
              ],
            ),
            Divider(color: t.accent, thickness: 1.2),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    box.boxNumber.isNotEmpty ? box.boxNumber : box.vcNumber,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: t.cardSubtitleText),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBoxSelectionSheet(AppThemeConst t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Text('Select Box', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.cardHeadingText)),
              const Divider(),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _boxes.length,
                  itemBuilder: (_, i) {
                    final b = _boxes[i];
                    final isSelected = i == _selectedBoxIndex;
                    final active = b.isActive;
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? t.accent : Colors.grey,
                      ),
                      title: Text(
                        b.boxNumber.isNotEmpty ? b.boxNumber : b.vcNumber,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text('VC: ${b.vcNumber}', style: TextStyle(fontSize: 12, color: t.cardSubtitleText)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          b.stateLabel.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          ),
                        ),
                      ),
                      onTap: () {
                        setState(() => _selectedBoxIndex = i);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Operations Card ────────────────────────────────────────────────────
  Widget _buildOperationsCard(AppThemeConst t) {
    // Android parity: computed once from the current customer + session flags
    // (CustomerOperations_Fragment). Entry-driven — rebuilds on next open, not
    // in place (Android navigates away after state-changing operations).
    final ops = buildCustomerOperations(_customer, SessionService.instance,
        hasOttBoxes: _ottBoxes.isNotEmpty,
        selectedBox: _selectedBox);

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

  /// Make Payments → on return, if a payment was made, reload this customer so
  /// Total Due / Amount Payable / Last Paid Date show the new values (they were
  /// the search-time values). Same detail call Search makes when opening a
  /// customer (searchType 100). No payment (plain Back) → no reload.
  Future<void> _openPayment() async {
    final before = DashboardRefreshSignal.instance.paymentCount;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => PaymentOptionsScreen(customer: _customer)));
    if (!mounted || DashboardRefreshSignal.instance.paymentCount == before) return;
    final fresh =
        await SearchRepository.instance.fetchCustomerDetail(_customer.lcoCustomerId);
    if (!mounted || fresh == null) return; // never throws; null → keep current
    setState(() {
      // The detail response omits `crf` — keep the current CRF (as Search does).
      _customer = fresh.crfNumber.isEmpty && _customer.crfNumber.isNotEmpty
          ? fresh.copyWith(crfNumber: _customer.crfNumber)
          : fresh;
    });
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
          _openPayment();
        }
        break;
      case 'Update Location':
        _onUpdateLocationTile();
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
        Navigator.push(context, MaterialPageRoute(builder: (_) => PackageOperationsScreen(customer: _customer, preSelectedBox: _selectedBox)));
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

    // C1 / Android TemporaryActivation_stb :3426: non-cancellable
    // "Loading...Please wait..." while the request runs (Back ignored). The
    // repository never throws (70 s timeout → status 3), so it always closes.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final result = await PackageOperationsRepository.instance
        .stbTemporaryActivation(customerId: _customer.lcoCustomerId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader

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

    // C1 / Android renewal :2967: non-cancellable "Loading...Please wait..."
    // while the request runs (Back ignored). The repository never throws
    // (70 s timeout → status 3), so the loader always closes.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final result = await PackageOperationsRepository.instance
        .packageRenew(customerId: _customer.lcoCustomerId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader

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

    // C1 / Android UnpaidActivation_stb_CUstomer :3325: non-cancellable
    // "Loading...Please wait..." while the request runs (Back ignored). The
    // repository never throws (70 s timeout → status 3), so it always closes.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final result = await PackageOperationsRepository.instance
        .unpaidCustomerActivation(customerId: _customer.lcoCustomerId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader

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

  // Android parity (CustomerOperations_Fragment igv_editmob :658-711): empty
  // number box, digits only, max 10; < 10 → "Please enter 10 digit mobile
  // number"; else POST updateMobileAndLCOCustID (updateType=mobile,
  // updateValue="91"+number) and show "91"+number only after success.
  Future<void> _showUpdateMobileDialog(String currentMobile) async {
    final controller = TextEditingController();
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
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
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
    if (newMobile.length != 10) {
      if (mounted) {
        showPremiumSnackBar(context, 'Please enter 10 digit mobile number', isError: true);
      }
      return;
    }
    if (!mounted) return;

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showPremiumLoading(context, message: 'Updating...');
    final res = await PackageOperationsRepository.instance.updateMobileNumber(
      customerId: _customer.lcoCustomerId, // stable key, same as the LCO-id edit
      newMobile: newMobile,
    );
    if (!mounted) return;
    nav.pop(); // dismiss loader
    if (res.isSuccess) {
      setState(() {
        _customer = _customer.copyWith(primaryMobileNumber: '91$newMobile');
      });
    }
    messenger.showSnackBar(SnackBar(
      content: Text(res.isSuccess
          ? (res.statusMessage.isEmpty ? 'Mobile number updated successfully' : res.statusMessage)
          : (res.statusMessage.isEmpty ? 'Update failed' : res.statusMessage)),
      backgroundColor: res.isSuccess ? Colors.green.shade600 : Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
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

  // ── Update Location — Android parity (CustomerOperations_Fragment +
  // MapsFragmentlocupdate) ──────────────────────────────────────────────────
  // Entry points:
  //  • 'Update Location' tile (custoper_btn_addcustomerlocation :1397):
  //    BroadBand customer → "Access denied!"; otherwise the popup below.
  //  • Location icon with no location (tv_locate :980) and the on-open prompt
  //    (:397, gps_popup_app == 1): straight to the popup (no BroadBand check).
  // Flow: popup (customer details + "Enter Your Area Name", Yes/No, NO
  // validation) → GPS → map (CANCEL/SEND) → SEND: "Do you want to save
  // location for this customer?" (Yes/No) → updateCustomerlocation →
  // status 0: Dashboard + "Location updated successfully…" · 1: "No Records
  // Found!" · 2: "<msg>: Contact Support" · no reply: "Server is busy or Un
  // reachable!" (failures stay on the map, as Android does).

  /// Android `latt == 0.0 || longitudee == 0.0` → the customer has no location.
  bool get _hasLocation {
    final lat = _customer.latitude;
    final lng = _customer.longitude;
    return lat != null && lng != null && lat != 0 && lng != 0;
  }

  /// Android :397-540 — on opening a customer with no location, when the
  /// dealer's gps_popup_app flag is 1.
  Future<void> _promptLocationIfMissing() async {
    if (!mounted || SessionService.instance.gpsPopupApp != 1 || _hasLocation) {
      return;
    }
    final update = await showPremiumConfirm(
      context: context,
      title: 'Location Update!',
      body: 'Customer doesnot have updated location .Please Update the customer Location!',
      confirmLabel: 'Update',
      cancelLabel: 'Cancel',
    );
    if (update && mounted) await _showUpdateLocationDialog();
  }

  /// Android custoper_btn_addcustomerlocation :1397-1418.
  Future<void> _onUpdateLocationTile() async {
    if (_customer.customerType.trim() == '1') {
      await showPremiumConfirm(
        context: context,
        title: 'Access denied!',
        body: 'You have no access ',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
      return;
    }
    await _showUpdateLocationDialog();
  }

  /// Customer block shown in both Android location popups
  /// (addcustlocation_dialolg / adcustdialog_okscreen): Name, LCO Customer Id,
  /// CRF (only when the dealer uses CRF) and Address.
  Widget _locationCustomerInfo() {
    final rows = <(String, String)>[
      ('Customer Name', _customer.name),
      ('Lco Customer Id', _lcoId),
      if (SessionService.instance.useCaf == 1) ('CRF', _customer.crfNumber),
      ('Address', _customer.address),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(r.$1,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(r.$2,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Android-style Yes / No row used by both location popups.
  Widget _yesNoButtons(BuildContext dialogContext) => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('NO',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('YES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
        ],
      );

  /// Android popup header + message used by both location popups.
  Widget _locationPopupHeader(String message) => Column(
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
                child: const Icon(Iconsax.location, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Update Location',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 12),
        ],
      );

  /// Android addcustlocation_dialolg → Yes → MapsFragmentlocupdate.
  Future<void> _showUpdateLocationDialog() async {
    // Android: empty box, hint "Enter Your Area Name", no validation on Yes.
    final controller = TextEditingController();
    final confirmed = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: SingleChildScrollView(
            child: Builder(
              builder: (dialogContext) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _locationPopupHeader(
                      'Are you sure,you want to update location for following customer?'),
                  _locationCustomerInfo(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Enter Your Area Name',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Iconsax.location, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _yesNoButtons(dialogContext),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // Android passes the area name on as "Remarks" (may be empty).
    final areaName = controller.text.trim();

    // ── GPS fetch ────────────────────────────────────────────────────────
    final nav = Navigator.of(context);
    // A6: the GPS wait is bounded (_currentOrLastKnown, max 8 s) and the
    // loader is always closed below, so Back is ignored (Back used to close
    // the loader, and the late nav.pop() then closed this screen instead).
    showPremiumLoading(context,
        message: 'Getting GPS location...', canPop: false);
    double lat, lng;
    try {
      final position = await _currentOrLastKnown();
      lat = position.latitude;
      lng = position.longitude;
    } catch (_) {
      // A6 / Android GPSTracker + MapsFragmentlocupdate :135-145, :493-494:
      // no location → 0.0/0.0 and the flow continues (owner's decision:
      // copy Android).
      lat = 0.0;
      lng = 0.0;
    }
    if (!mounted) return;
    nav.pop(); // dismiss loading

    // ── Map (Android MapsFragmentlocupdate): CANCEL = back, SEND = save ──
    await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => LocationPreviewScreen(
          customerName: _customer.name,
          areaName: areaName,
          location: LatLng(lat, lng),
          onSend: (mapContext) =>
              _confirmAndSaveLocation(mapContext, areaName, lat, lng),
        ),
      ),
    );
  }

  /// Android btn_send_locupdate → adcustdialog_okscreen (Yes/No) →
  /// updatecustomerinfodetails. Runs while the map is still open.
  Future<void> _confirmAndSaveLocation(
      BuildContext mapContext, String areaName, double lat, double lng) async {
    final save = await showPremiumDialog<bool>(
      context: mapContext,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: SingleChildScrollView(
            child: Builder(
              builder: (dialogContext) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _locationPopupHeader('Do you want to save location for this customer?'),
                  _locationCustomerInfo(),
                  const SizedBox(height: 16),
                  _yesNoButtons(dialogContext),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (save != true || !mapContext.mounted) return;

    final nav = Navigator.of(mapContext);
    final messenger = ScaffoldMessenger.of(mapContext);
    showPremiumLoading(mapContext,
        message: 'Sending details, Please wait...', canPop: false);
    final res = await CustomerLocationRepository.instance.update(
      lcoCustomerId: _customer.lcoCustomerId,
      latitude: lat,
      longitude: lng,
    );
    if (!mapContext.mounted) return;
    nav.pop(); // dismiss loader

    if (res.isSuccess) {
      // Keep the phone copy in step — only after the server accepted it.
      try {
        await _db.updateCustomerLocation(
          lcoCustomerId: _customer.lcoCustomerId,
          areaName: areaName,
          latitude: lat,
          longitude: lng,
        );
      } catch (error, stackTrace) {
        debugPrint('Update location: local copy not saved: $error');
        debugPrint(stackTrace.toString());
      }
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Location updated successfully\n'
          'Customername :${_customer.name}\n'
          'LCO Customer Id :$_lcoId\n'
          'Remarks :$areaName',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      // Android: changeFragment(DashboardHomeFragment).
      nav.popUntil((route) => route.isFirst);
      return;
    }

    if (res.statusCode == 1) {
      await showPremiumConfirm(
        context: mapContext,
        title: 'No Records Found!',
        body: res.statusMessage,
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
    } else if (res.statusCode == 2) {
      showPremiumSnackBar(mapContext, '${res.statusMessage}: Contact Support',
          isError: true);
    } else {
      await showPremiumConfirm(
        context: mapContext,
        title: 'Server is busy or Un reachable!',
        body: 'Please try again after sometime',
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
    }
  }

  /// A6: the phone's position without ever waiting forever. Android never
  /// waits (GPSTracker.java:47-104 returns the last known location at once).
  /// Flutter keeps its fresh fix but waits at most 8 s (as Nearest does), then
  /// takes the last known location; with neither it throws.
  Future<Position> _currentOrLastKnown() async {
    try {
      return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8)));
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) rethrow;
      return last;
    }
  }

  Future<void> _openCustomerMap() async {
    // Android tv_locate :980-1060: no location → the Update Location popup.
    if (!_hasLocation) {
      await _showUpdateLocationDialog();
      return;
    }
    // Capture navigator before async gap
    final nav = Navigator.of(context);
    // A6: the in-app map needs a start point (owner kept it); the wait is
    // bounded (max 8 s) and both paths close the loader, so Back is ignored.
    showPremiumLoading(context,
        message: 'Getting your location...', canPop: false);
    try {
      final current = await _currentOrLastKnown();
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