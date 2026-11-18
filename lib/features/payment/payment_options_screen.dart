import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/data/customer.dart';
import '../../core/data/payment.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../dashboard/dashboard_refresh_signal.dart';
import 'payment_confirmation_dialog.dart';
import 'payment_controller.dart';
import 'receipt_preview_screen.dart';
import '../search/data/search_repository.dart';
import '../customer/customer_details_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentOptionsScreen — backed by PaymentController (ChangeNotifier)
// ─────────────────────────────────────────────────────────────────────────────
class PaymentOptionsScreen extends StatefulWidget {
  final Customer customer;
  const PaymentOptionsScreen({super.key, required this.customer});

  @override
  State<PaymentOptionsScreen> createState() => _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends State<PaymentOptionsScreen>
    with SingleTickerProviderStateMixin {
  late final PaymentController _ctrl;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = PaymentController(customer: widget.customer);
    // gpa → prefill the amount with the live due amount. A3: behind Android's
    // blocking loader, then Android's message per status (see _loadPending).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
    _ctrl.captureLocation();   // Android parity: last-known GPS at screen open (0.0 fallback)
    _ctrl.capturePaymentTimeout(); // A1: Android reads the mobile state at open
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Pick date ────────────────────────────────────────────────────────────────
  /// A-B6 / Android CustomerMgmt_MakePayment_Fragment :871-878, :2411-2443:
  /// the picker opens only after a Cheque/DD number is entered (otherwise the
  /// date goes back to "Select"); a date before today shows "Cheque Date
  /// Error!" and resets the date to "Select" (setCurrentDateOnView).
  Future<void> _pickInstrumentDate() async {
    if (_ctrl.chequeNoCtrl.text.isEmpty) {
      _ctrl.setInstrumentDate(null);
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _ctrl.instrumentDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    if (picked.isBefore(DateTime(now.year, now.month, now.day))) {
      _ctrl.setInstrumentDate(null);
      await _showInfoDialog(
          'Cheque Date Error!', 'Cheque date should not be before today.');
      return;
    }
    _ctrl.setInstrumentDate(picked);
  }

  // ── Pending amount (gpa) ─────────────────────────────────────────────────────
  /// A3 / Android GetPendingAmount (CustomerMgmt_MakePayment_Fragment :1312,
  /// :1396-1418, :1611-1613): non-cancellable "Getting Pending Amount,   Please
  /// wait..." while gpa runs, then: no reply → "Server is busy or Un reachable!"
  /// (OK stays on this screen); status 1 → "{msg}: Enter Valid Details";
  /// status 2 → "{msg}: Contact Support". PAY is not blocked afterwards (Android).
  Future<void> _loadPending() async {
    if (!mounted) return;
    showPremiumLoading(context,
        message: 'Getting Pending Amount,   Please wait...', canPop: false);
    await _ctrl.loadPendingAmount(); // never throws
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    final msg = _ctrl.pendingError ?? '';
    switch (_ctrl.pendingStatus) {
      case 1:
        showPremiumSnackBar(context, '$msg: Enter Valid Details', isError: true);
        break;
      case 2:
        showPremiumSnackBar(context, '$msg: Contact Support', isError: true);
        break;
      case -1:
        showDialog<void>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Server is busy or Un reachable!'),
            content: const Text('Please try again after sometime'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
    }
  }

  // ── Pay Now ──────────────────────────────────────────────────────────────────
  Future<void> _handlePay() async {
    // Dismiss the keyboard before the confirmation/loading/success overlays so it
    // can't pop back up (focus restoration) on each overlay dismissal.
    FocusManager.instance.primaryFocus?.unfocus();

    final error = _ctrl.validate();
    if (error != null) {
      showPremiumSnackBar(context, error, isError: true);
      return;
    }

    // Premium detailed confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentConfirmationDialog(
        customer: widget.customer,
        amount: _ctrl.parsedAmount,
        broadbandAmount:
            _ctrl.isBroadbandCustomer ? _ctrl.parsedBroadbandAmount : 0.0,
        paymentMethod: '',
        lastPaidAmount: _ctrl.lastPaidAmount, // real GPA last_paid_amount
        paymentsCount: _ctrl.paymentsCount,     // A4: GPA payments_count
        adjustmentCount: _ctrl.adjustmentCount, // A4: GPA adjustment_count
      ),
    ) ?? false;
    
    if (!confirmed || !mounted) return;

    // Show loading. A2 / Android MakePayment :1765 (non-cancellable
    // ProgressDialog): Back is ignored, so the pops below always close THIS
    // loader and never the Payment screen. Every path closes it: success,
    // null result and the catch (A1: makePayments times out after 100 s on
    // mobile data, otherwise 200 s — Android's values).
    showPremiumLoading(context, message: 'Processing payment...', canPop: false);

    // R1: only the makePayments call itself maps to Android's failure
    // messages. Anything after a SUCCESSFUL payment (receipt build/navigation)
    // must never be reported as a failure — that would invite a duplicate
    // payment — so it has its own catch below.
    final Payment? payment;
    try {
      payment = await _ctrl.pay();
    } on PaymentRejectedException catch (r) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      await _showPaymentRejected(r);
      return;
    } catch (_) {
      // R1 / Android :1988-2006: no server reply (network / timeout / bad
      // response) → "Server is busy or Un reachable!"; OK stays here.
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      await _showServerBusy();
      return;
    }

    try {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      if (payment == null) {
        showPremiumSnackBar(context, 'Payment could not be saved', isError: true);
        return;
      }
      final paid = payment; // promoted non-null for the closures below

      // A successful payment changes the dashboard totals — flag KPIs stale so
      // the Dashboard force-refreshes them on return (Android parity, where the
      // post-payment fragment rebuild reloads the summary).
      DashboardRefreshSignal.instance.markKpiDirty();
      DashboardRefreshSignal.instance.markPaymentDone(); // Customer Details reload

      // Receipt values captured now, before the controller is reset on return.
      final bbPaid =
          _ctrl.isBroadbandCustomer ? _ctrl.parsedBroadbandAmount : 0.0;
      final stbPaid = _ctrl.parsedAmount;
      final discountPaid = double.tryParse(_ctrl.discountCtrl.text) ?? 0.0;
      final dealerName = _ctrl.lastResult?.dealerBusinessName ?? '';
      // A-B4 / Android DisplayPaymentDetails_Fragment :299-331: the receipt's
      // bill, due and out amounts follow the dealer rounding. Paid amounts stay
      // exactly as collected.
      final round = SessionService.instance.applyAmountRound;
      final dueAmt = round(_ctrl.receiptDueAmount);
      final outAmt = round(_ctrl.receiptOutAmount);
      // Receipt "Bill Amount" from the mpay response (Android parity) — the
      // customer list total is 0 for broadband, so use the server's billAmount.
      final billAmt = round(_ctrl.lastResult?.billAmount ?? 0.0);

      // Success popup before navigating — iOS 26 "liquid glass" card (no ✕; an OK
      // button instead). Self-contained, so it drops PremiumDialogShell. Timing is
      // unchanged: auto-closes after 1.5s (timer in _PaymentSuccessContent) then
      // continues to the receipt.
      await showPremiumDialog<void>(
        context: context,
        barrierDismissible: false,
        child: _PaymentSuccessContent(
          amount: payment.amount,
          customerName: widget.customer.name,
          txnId: payment.transactionId,
          onContinue: () => Navigator.of(context).pop(),
        ),
      );

      if (!mounted) return;
      // Android :2344 changeFragment(displayPaymentDetails, true) keeps Make
      // Payment on the back stack: Back from the receipt returns HERE and
      // GetPendingAmount (:371) shows the updated due. pushReplacement used to
      // remove this screen, so Back showed the old due (stale customer object).
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPreviewScreen(
            customer: widget.customer,
            payment: paid, // non-null copy (closure-safe)
            broadbandPaidAmount: bbPaid,
            stbPaidAmount: stbPaid,
            discountAmount: discountPaid,
            dealerBusinessName: dealerName,
            dueAmount: dueAmt,
            outAmount: outAmt,
            billAmount: billAmt,
            taxes: _ctrl.lastResult?.taxes ?? const [],
          ),
        ),
      );
    } catch (error, stackTrace) {
      // The payment IS saved on the server; only showing the receipt failed.
      // Never say "failed" here (it would invite a second payment).
      ErrorHandlerService.recordError(error, stackTrace,
          reason: 'Payment receipt display');
      if (!mounted || payment == null) return;
      showPremiumSnackBar(
          context, 'Payment done. Receipt No: ${payment.transactionId}',
          isSuccess: true);
    }

    // Back from the receipt (or the receipt could not be shown): the payment
    // is done, so clear the collected amounts and reload the live due — the
    // old amount can't be paid again by mistake (Android :2346 + :371).
    if (!mounted) return;
    _ctrl.resetAfterPayment();
    await _loadPending();
  }

  /// R1 / Android CustomerMgmt_MakePayment_Fragment :2348-2367.
  ///  1 → "Payment Failed!" + server message; OK leaves the payment screen
  ///      (popBackStack). 2 → "{message}: Contact Support"; stays.
  ///  Any other code (no valid status in the reply) → the Server-busy dialog.
  Future<void> _showPaymentRejected(PaymentRejectedException r) async {
    if (r.statusCode == 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Payment Failed!'),
          content: Text(r.statusMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) Navigator.of(context).pop();
    } else if (r.statusCode == 2) {
      showPremiumSnackBar(context, '${r.statusMessage}: Contact Support',
          isError: true);
    } else {
      await _showServerBusy();
    }
  }

  Future<void> _showServerBusy() {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Server is busy or Un reachable!'),
        content: const Text('Please try again after sometime'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Pay Later ────────────────────────────────────────────────────────────────
  Future<void> _handlePayLater() async {
    // Android parity (CustomerMgmt_MakePayment_Fragment): lookup the customer's
    // schedule (gethitapipaylater) → pre-filled dialog with the server status LOV →
    // submit (scheduled_collection_create). Server-side; no local fallback.
    showPremiumLoading(context, message: 'Fetching Details, Please wait');
    final lookup = await _ctrl.lookupPayLater();
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading
    if (lookup.statusCode == 3) {
      showPremiumSnackBar(context, lookup.statusMessage, isError: true);
      return;
    }
    final record = lookup.schedules.isNotEmpty ? lookup.schedules.first : null;
    if (record == null) {
      showPremiumSnackBar(
          context,
          lookup.statusMessage.isEmpty
              ? 'No schedule details found'
              : lookup.statusMessage,
          isError: true);
      return;
    }
    final statuses =
        lookup.statuses.isNotEmpty ? lookup.statuses : const ['Scheduled'];

    final remarksCtrl = TextEditingController(text: record.remarks);
    DateTime scheduleDate = _parseYmd(record.scheduledDate) ?? DateTime.now();
    String status =
        statuses.contains(record.status) ? record.status : statuses.first;

    final ok = await showPremiumDialog<bool>(
      context: context,
      child: PremiumDialogShell(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: StatefulBuilder(
              builder: (ctx, setD) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Iconsax.clock, color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Schedule Collection',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Customer pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Iconsax.user, size: 14, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          widget.customer.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status + Date row
                  Row(
                    children: [
                      Expanded(
                        child: _CompactDropdown<String>(
                          hint: 'Status',
                          value: status,
                          items: statuses,
                          onChanged: (v) { if (v != null) setD(() => status = v); },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            // A-B8 / Android :2753 setMinDate(today): no past
                            // schedule dates. A saved past date opens on today
                            // (initialDate must not be before firstDate).
                            final now = DateTime.now();
                            final today = DateTime(now.year, now.month, now.day);
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: scheduleDate.isBefore(today)
                                  ? today
                                  : scheduleDate,
                              firstDate: today,
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setD(() => scheduleDate = picked);
                          },
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month, size: 15, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '${scheduleDate.day.toString().padLeft(2, '0')}-'
                                  '${scheduleDate.month.toString().padLeft(2, '0')}-'
                                  '${scheduleDate.year}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Remarks
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Remarks (optional)',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.pop(ctx, false);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('CANCEL', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.pop(ctx, true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(record.isEditable == '1' ? 'UPDATE' : 'SUBMIT',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        ),
      ),
    );

    if (ok != true || !mounted) return;

    showPremiumLoading(context, message: 'Scheduling collection...');
    final res = await _ctrl.submitPayLater(
      customerId: record.customerId,
      scheduleDate: scheduleDate,
      status: status,
      remarks: remarksCtrl.text.trim(),
      isEdited: record.isEditable,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading
    // Android shows a "Success" / "Fail!" dialog with the server message.
    await _payLaterResultDialog(res.success, res.message);
  }

  DateTime? _parseYmd(String s) {
    final p = s.split('-');
    if (p.length < 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2].length > 2 ? p[2].substring(0, 2) : p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _payLaterResultDialog(bool success, String message) {
    return showPremiumDialog<void>(
      context: context,
      child: PremiumDialogShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(success ? Icons.check_circle : Icons.error,
                  color: success ? Colors.green : Colors.red, size: 44),
              const SizedBox(height: 12),
              Text(success ? 'Success' : 'Fail!',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(message.isEmpty ? (success ? 'Scheduled' : 'Failed') : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('OK',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _buildAppBar(t),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) {
            return Column(
              children: [
                _buildPrevNextStrip(t),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _CustomerInfoCard(
                    customer: widget.customer,
                    t: t,
                    // Android :1454/:1498: once gpa answers, Total Due and
                    // Payable show the live amounts, not the search values.
                    totalDue: _ctrl.pendingLoaded
                        ? '₹${_ctrl.pendingAmount.toStringAsFixed(2)}'
                        : null,
                    payable: _ctrl.pendingLoaded
                        ? '₹${_ctrl.cablePending.toStringAsFixed(2)}'
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _GlassCard(
                        t: t,
                        child: _buildPaymentForm(t),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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

  PreferredSizeWidget _buildAppBar(AppThemeConst t) {
    return AppBar(
      backgroundColor: t.appBarBg,
      foregroundColor: t.appBarFg,
      elevation: 0,
      centerTitle: true,
      // Standard back button. Prev/Next customer controls moved to the strip
      // below the AppBar (_buildPrevNextStrip); _prevNextCustomer unchanged.
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
        'PAYMENT',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: t.appBarFg,
        ),
      ),
      // Next-customer control moved to the Prev/Next strip below the AppBar.
    );
  }

  // ── Prev/Next customer (Android CustomerMgmt_MakePayment_Fragment) ───────
  // ◄ = prev (flag 2) · ► = next (flag 1) → SOAP `prenext`. Android status 0
  // reopens Customer Details (CustomerOperations) for the adjacent customer —
  // it does NOT return to make-payment. 1 = "No Data Found!" · 2 = snackbar +
  // "Contact Support" · 3/transport = "Server is busy or Un reachable!".
  Future<void> _prevNextCustomer(int flag) async {
    final id = int.tryParse(widget.customer.lcoCustomerId.trim());
    if (id == null) {
      showPremiumSnackBar(context, 'Error, Please try again later.',
          isError: true);
      return;
    }
    // D7 / Android prev/next (CustomerMgmt_MakePayment_Fragment): non-
    // cancellable "Searching...,   Please wait..."; prevNextCustomer never throws.
    showPremiumLoading(context,
        message: 'Searching...,   Please wait...', canPop: false);
    final r = await SearchRepository.instance
        .prevNextCustomer(customerId: id, flag: flag);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    if (r.statusCode == 0 && r.customer != null) {
      // Android reopens CustomerOperations_Fragment for the adjacent customer.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailsScreen(customer: r.customer!),
        ),
      );
      // A5a / Android :371: coming back rebuilds the Pay screen and reloads
      // the pending amount (the customer may have been paid meanwhile).
      if (mounted) await _loadPending();
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

  Widget _buildPaymentForm(AppThemeConst t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'PAYMENT OPTIONS', t: t),
        const SizedBox(height: 10),

        // Payment mode dropdown
        Container(
          decoration: BoxDecoration(
            color: t.inputBg,
            borderRadius: BorderRadius.circular(AppSizes.radiusS),
            border: Border.all(color: t.inputBorderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _ctrl.paymentMethod,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.cardBodyText),
              // Android offers only Cash and Bank (CustomerMgmt_MakePayment_Fragment
              // arrayOfString = {"Cash","Bank"}). No UPI mode exists in Android.
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank / Cheque')),
              ],
              onChanged: (v) { if (v != null) _ctrl.setPaymentMethod(v); },
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Discount — shown only when the tenant enables payment discount
        // (gate on enable_payment_discount; role permission deferred).
        // Auto-recomputes the amount field (= due − discount).
        if (_ctrl.discountEnabled) ...[
          _CompactField(
            controller: _ctrl.discountCtrl,
            hint: 'Discount amount (₹)',
            t: t,
            enabled: !_ctrl.isBroadbandOnly, // Android disables for BroadBand-only
            // A-B7 / Android :552 + layout: digits and one ".", at most 2
            // decimals, max 7 characters.
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              LengthLimitingTextInputFormatter(7),
              TextInputFormatter.withFunction((oldValue, newValue) =>
                  RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
                      ? newValue
                      : oldValue),
            ],
            onChanged: (_) => _ctrl.onDiscountChanged(),
            errorText: _ctrl.discountError,
          ),
          const SizedBox(height: 10),
        ],

        // ── A-B3: billing-scheme discount / penalty (Android disc_pen_chk,
        //    "Due Amount" + "Discount Applied"/"Penalty Applied" rows) ──────
        if (_ctrl.schemeVisible) ...[
          _CheckToggle(
            value: _ctrl.schemeApplied,
            // Automatic schemes are fixed (Android setEnabled(false)).
            onChanged: (v) {
              if (_ctrl.schemeMode == 'M') _ctrl.setSchemeApplied(v);
            },
            label: _ctrl.schemeCheckLabel,
          ),
          if (_ctrl.schemeApplied) ...[
            const SizedBox(height: 6),
            Text('Due Amount :  ₹${_ctrl.cablePending.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, color: t.bodyText)),
            const SizedBox(height: 4),
            Text(
                '${_ctrl.schemeAppliedLabel} :  ₹${_ctrl.schemeAmount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.bodyText)),
          ],
          const SizedBox(height: 10),
        ],
        // Amount (STB / cable leg). Disabled for BroadBand-only customers
        // (Android freezes et_amount when customerType == "BroadBand").
        _CompactField(
          controller: _ctrl.amountCtrl,
          hint: _ctrl.isBroadbandCustomer
              ? 'Amount to Collect (STB) (₹)'
              : 'Amount to collect (₹) *',
          t: t,
          // Android: STB et_amount is disabled for BroadBand-only customers AND
          // for LCO-deposit dealers (useLcoDeposit==1) — pinned to full pending.
          enabled: !_ctrl.isBroadbandOnly && !_ctrl.amountLocked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          highlightColor: _ctrl.paymentMethod == 'bank' ? const Color(0xFFF59E0B) : null,
        ),

        // ── Broadband leg (broadband customers only) ─────────────────────────
        if (_ctrl.isBroadbandCustomer) ...[
          const SizedBox(height: 10),
          _CompactField(
            controller: _ctrl.broadbandAmountCtrl,
            hint: 'Amount to Collect (Broadband) (₹)',
            t: t,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 10),
          _CheckToggle(
            value: _ctrl.isForRenewal,
            onChanged: _ctrl.setIsForRenewal,
            label: 'Renewal',
          ),
        ],

        // ── Bank-only fields ─────────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          child: _ctrl.paymentMethod == 'bank'
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _CompactField(controller: _ctrl.chequeNoCtrl, hint: 'Cheque / DD number *', t: t),
                    const SizedBox(height: 10),
                    _CompactField(controller: _ctrl.bankNameCtrl, hint: 'Bank name *', t: t),
                    const SizedBox(height: 10),
                    _CompactField(controller: _ctrl.branchCtrl, hint: 'Branch *', t: t),
                    const SizedBox(height: 10),
                    _DatePickerField(
                      date: _ctrl.instrumentDate,
                      t: t,
                      onTap: _pickInstrumentDate,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 10),

        // Remarks & Mobile (hint only — no separate label)
        _CompactField(
          controller: _ctrl.remarksCtrl,
          hint: 'Remarks (optional)',
          t: t,
        ),
        const SizedBox(height: 10),
        _CompactField(
          controller: _ctrl.mobileCtrl,
          hint: widget.customer.primaryMobileNumber.isEmpty
              ? 'Alternate mobile (optional)'
              : 'Alt: ${widget.customer.primaryMobileNumber}',
          t: t,
          // A-B7 / Android layout makepayact_et_mobilenum: number, max 10.
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        const SizedBox(height: 12),

        // SMS toggle
        _SmsToggle(
          value: _ctrl.sendSms,
          onChanged: _ctrl.setSendSms,
        ),
        const SizedBox(height: 16),

        // Buttons
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _ctrl.isStoring ? null : _handlePay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                  ),
                  child: const Text('PAY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
            // A-B8 / Android :1500-1511: PAY LATER follows the cable pending
            // (> 0), not the customer type — see PaymentController.showPayLater.
            if (_ctrl.showPayLater) ...[
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _ctrl.isStoring ? null : _handlePayLater,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.backBtnBg,
                      foregroundColor: t.appBarFg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusM)),
                    ),
                    child: Text('PAY LATER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.accent)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment Success Content
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentSuccessContent extends StatefulWidget {
  final double amount;
  final String customerName;
  final String txnId;
  final VoidCallback onContinue;

  const _PaymentSuccessContent({
    required this.amount,
    required this.customerName,
    required this.txnId,
    required this.onContinue,
  });

  @override
  State<_PaymentSuccessContent> createState() => _PaymentSuccessContentState();
}

class _PaymentSuccessContentState extends State<_PaymentSuccessContent> {
  Timer? _autoClose;
  // Single-shot guard: onContinue (a Navigator.pop) must run at most ONCE.
  // Otherwise the OK tap and the 1.5s auto-close timer — or a double-tap —
  // could each fire it, and the second Navigator.pop() would remove the payment
  // screen (not just the dialog), making `mounted` false so the pushReplacement
  // to the receipt is silently skipped. See _handleContinue.
  bool _continued = false;

  @override
  void initState() {
    super.initState();
    // Auto-close the success popup, then proceed to the receipt — no manual
    // "VIEW RECEIPT" tap needed. Cancelled if the dialog is dismissed earlier.
    _autoClose = Timer(const Duration(milliseconds: 1500), _handleContinue);
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  // Dismiss the popup and proceed to the receipt — guaranteed to run exactly
  // once. The first call (OK tap OR the auto-close timer) cancels the timer and
  // invokes onContinue; any later call is a no-op. This makes ONLY ONE
  // Navigator.pop() ever run (closing the dialog), so the payment screen can no
  // longer be popped by a second pop and the receipt is never skipped.
  void _handleContinue() {
    if (_continued) return;
    _continued = true;
    _autoClose?.cancel();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    // iOS 26 "liquid glass" success popup: frosted translucent card, soft green
    // check, amount, and a single iOS-style OK action (replaces the ✕). Stays
    // light — the 1.5s auto-close (initState timer) and receipt flow are unchanged.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              // Light blur (was 30) — cheap even on low-end GPUs; the higher card
              // opacity keeps the frosted look and a near-solid fallback.
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: const BoxDecoration(
                              color: Color(0x2634C759), // iOS green @ 15%
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Color(0xFF34C759), size: 36),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Payment Successful',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₹${widget.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF), // iOS blue
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // iOS-style hairline + single OK action.
                    Container(
                      height: 0.5,
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                    InkWell(
                      onTap: _handleContinue,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(28)),
                      child: const SizedBox(
                        height: 50,
                        child: Center(
                          child: Text(
                            'OK',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer Info Card — compact
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerInfoCard extends StatelessWidget {
  final Customer customer;
  final AppThemeConst t;
  // Live gpa amounts; null → the customer's search values.
  final String? totalDue;
  final String? payable;
  const _CustomerInfoCard({
    required this.customer,
    required this.t,
    this.totalDue,
    this.payable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: t.accent.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: t.cardShadowColor, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      // Clip so the tinted header respects the card's rounded top corners.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted header strip (complaints-card style) — avatar + name/id + type.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            color: t.accent.withValues(alpha: 0.08),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: t.headerGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Iconsax.user, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.cardHeadingText)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(customer.customerTypeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: t.accent)),
                ),
              ],
            ),
          ),
          // Body: the detail grid (Mobile / Total Due / Payable / …).
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: _infoGrid(customer, t),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(Customer c, AppThemeConst t) {
    final items = [
      ('Mobile', c.primaryMobileNumber),
      ('Total Due', totalDue ?? c.totalDue),
      ('Payable (STB)', payable ?? c.amountPayable),
      ('Last Paid', c.lastPaidDate),
      ('Bill Month', c.billMonth),
      ('Type', c.customerTypeLabel),
    ];
    return Column(
      children: items
          .map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Icon(_rowIcon(e.$1), size: 14, color: t.cardSubtitleText),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.$1,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: t.cardSubtitleText),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        e.$2,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.cardBodyText),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // Presentation-only: pick a small leading glyph from the row label. Reads the
  // label text only — never touches the value or any payment logic.
  IconData _rowIcon(String label) {
    if (label.startsWith('Mobile')) return Iconsax.call;
    if (label.startsWith('Total')) return Iconsax.wallet_3;
    if (label.startsWith('Payable')) return Iconsax.money_send;
    if (label.startsWith('Last')) return Iconsax.calendar_tick;
    if (label.startsWith('Bill')) return Iconsax.calendar;
    if (label.startsWith('Type')) return Iconsax.box;
    return Iconsax.document_text;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlassCard
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final AppThemeConst t;
  const _GlassCard({required this.child, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [BoxShadow(color: t.cardShadowColor, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionHeader
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final AppThemeConst t;
  const _SectionHeader({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: t.headerGradient, begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CompactField — hint-only, no label above
// ─────────────────────────────────────────────────────────────────────────────
class _CompactField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final AppThemeConst t;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Color? highlightColor;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool enabled;

  const _CompactField({
    required this.controller,
    required this.hint,
    required this.t,
    this.keyboardType,
    this.inputFormatters,
    this.highlightColor,
    this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = highlightColor ?? t.accent;
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.cardBodyText),
      decoration: InputDecoration(
        // Floating label: the placeholder rests inside the empty field and animates
        // up to a small label on focus/fill (Material default). Presentation-only —
        // the controller/value/callbacks are untouched; outlined field keeps a
        // constant height (label sits on the border, no layout shift).
        labelText: hint,
        errorText: errorText,
        labelStyle: TextStyle(color: t.inputHintColor, fontWeight: FontWeight.w400, fontSize: 13),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.focused) ? borderColor : t.inputHintColor,
            )),
        filled: true,
        fillColor: enabled ? t.inputBg : t.inputBg.withValues(alpha: 0.5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusS),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusS),
          borderSide: BorderSide(color: t.inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusS),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CompactDropdown — simple compact dropdown
// ─────────────────────────────────────────────────────────────────────────────
class _CompactDropdown<T> extends StatelessWidget {
  final String hint;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _CompactDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          items: items.map((e) => DropdownMenuItem<T>(
            value: e,
            child: Text(e.toString()),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DatePickerField
// ─────────────────────────────────────────────────────────────────────────────
class _DatePickerField extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onTap;
  final AppThemeConst t;
  const _DatePickerField({required this.date, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) {
    final label = date != null
        ? '${date!.day.toString().padLeft(2, '0')}-'
          '${date!.month.toString().padLeft(2, '0')}-'
          '${date!.year}'
        : 'Instrument Date *';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(AppSizes.radiusS),
          border: Border.all(color: t.inputBorderColor),
        ),
        child: Row(
          children: [
            Icon(Iconsax.calendar_1, color: t.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: date != null ? t.cardBodyText : t.inputHintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SmsToggle
// ─────────────────────────────────────────────────────────────────────────────
class _SmsToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SmsToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: value ? AppColors.primary : AppColors.textSecondary,
                width: 1.8,
              ),
            ),
            child: value ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
          ),
          const SizedBox(width: 8),
          const Text(
            'Send SMS',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CheckToggle — labelled checkbox (used for the broadband Renewal flag)
// ─────────────────────────────────────────────────────────────────────────────
class _CheckToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const _CheckToggle({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: value ? AppColors.primary : AppColors.textSecondary,
                width: 1.8,
              ),
            ),
            child: value ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}