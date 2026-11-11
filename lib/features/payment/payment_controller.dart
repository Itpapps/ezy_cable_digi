import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../collections/data/pay_later_repository.dart';
import '../../core/data/customer.dart';
import '../../core/data/payment.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/error_handler_service.dart';
import '../../core/services/session_service.dart';
import 'data/pending_amount_repository.dart';
import 'data/make_payment_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentController — ChangeNotifier for PaymentOptionsScreen
// Owns all mutable state: method, fields, loading flag, date.
// Screens use ListenableBuilder to rebuild when notifyListeners() is called.
// ─────────────────────────────────────────────────────────────────────────────
class PaymentController extends ChangeNotifier {
  final Customer customer;

  PaymentController({required this.customer}) {
    // SMS checkbox default mirrors Android: pre-checked when the dealer's
    // send_sms config == 1 (CustomerMgmt_MakePayment_Fragment :459-461).
    _sendSms = SessionService.instance.sendSms == 1;
  }

  // ── TextEditingControllers ──────────────────────────────────────────────────
  final amountCtrl    = TextEditingController();
  final discountCtrl  = TextEditingController();
  final remarksCtrl   = TextEditingController();
  final mobileCtrl    = TextEditingController();
  final chequeNoCtrl  = TextEditingController();
  final bankNameCtrl  = TextEditingController();
  final branchCtrl    = TextEditingController();
  final broadbandAmountCtrl = TextEditingController(); // broadband leg

  // ── State fields ────────────────────────────────────────────────────────────
  String    _paymentMethod    = 'cash';
  bool      _sendSms          = false;
  DateTime? _instrumentDate;
  bool      _isStoring        = false;
  bool      _isForRenewal     = false; // broadband renewal checkbox

  // Payment GPS — Android parity (GPSTracker last-known + 0.0 fallback). Captured
  // once at screen open, off the pay path; stays '0.0' unless a cached fix is
  // safely obtained. Sent as audit metadata; never gates payment.
  String    _latitude         = '0.0';
  String    _longitude        = '0.0';

  // gpa — live pending amount fetched when the payment screen opens
  double  pendingAmount  = 0;
  bool    pendingLoading = false;
  String? pendingError;
  // A3: last gpa outcome — 0 ok · the server's statusCode · -1 no reply
  // (transport failure, Android's null response).
  int     pendingStatus = 0;
  int     _billingId     = 0; // bill to settle (from gpa) — sent to mpay
  double  _dueAmount     = 0; // due_amount (from gpa) — sent to mpay (= cable leg)
  String? discountError;      // set when discount > due (mirrors Android toast)
  double  cablePending   = 0; // STB/cable leg (from gpa) — the STB amount + due
  double  broadcasterPending = 0; // broadband pending (from gpa; 0 for STB)
  double  lastPaidAmount = 0; // Android last_paid_amount (from gpa) — the REAL
                              // "last paid", NOT the pending/bill amount.
  int     paymentsCount = 0;   // A4: gpa payments_count (current month)
  int     adjustmentCount = 0; // A4: gpa adjustment_count (current month)
  MakePaymentResult? lastResult;  // last successful mpay response (for receipt)

  String    get paymentMethod   => _paymentMethod;
  bool      get sendSms         => _sendSms;
  DateTime? get instrumentDate  => _instrumentDate;
  bool      get isStoring       => _isStoring;

  void setPaymentMethod(String v) {
    if (_paymentMethod == v) return;
    _paymentMethod = v;
    notifyListeners();
  }

  void setSendSms(bool v) {
    _sendSms = v;
    notifyListeners();
  }

  bool get isForRenewal => _isForRenewal;
  void setIsForRenewal(bool v) {
    _isForRenewal = v;
    notifyListeners();
  }

  void setInstrumentDate(DateTime? d) {
    _instrumentDate = d;
    notifyListeners();
  }

  void _setStoring(bool v) {
    _isStoring = v;
    notifyListeners();
  }

  /// Payment GPS — Android parity (GPSTracker.getLastKnownLocation + 0.0
  /// fallback, CustomerMgmt_MakePayment_Fragment :339-348). Captured ONCE when
  /// the payment screen opens, fire-and-forget, OFF the pay path. Uses
  /// last-known location only (never waits for a fresh fix, so it cannot hang);
  /// ANY failure/denial/null leaves the Android-default '0.0'/'0.0'. `pay()`
  /// never awaits this → it cannot delay or fail a payment.
  Future<void> captureLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; // Android swallows the SecurityException → 0.0
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        _latitude = pos.latitude.toString();
        _longitude = pos.longitude.toString();
      }
    } catch (e, s) {
      // Android: try/catch → printStackTrace → keeps 0.0. Never throws.
      ErrorHandlerService.recordError(e, s,
          reason: 'PaymentController.captureLocation');
    }
  }

  /// gpa: fetch the live pending amount and prefill the amount field.
  /// altCustomerId = the customer's customer_id (stored in lcoCustomerId).
  Future<void> loadPendingAmount() async {
    pendingLoading = true;
    pendingError = null;
    pendingStatus = 0;
    notifyListeners();
    try {
      final id = int.tryParse(customer.lcoCustomerId) ?? 0;
      final result = await PendingAmountRepository.instance.fetch(id);
      if (result.statusCode == 0) {
        // `pendingAmount` = overall total (cable + broadcaster) — display only.
        pendingAmount = result.pendingAmount;
        // STB/cable leg is what Android prefills into the amount box and sends as
        // due_amount (CustomerMgmt_MakePayment_Fragment :1487/:1829). For STB-only
        // customers cable == overall total, so this is a no-op for them.
        // A-B4 / Android :1485-1497: the dealer's amount rounding is applied
        // to both dues BEFORE prefill, due_amount and every comparison.
        final round = SessionService.instance.applyAmountRound;
        cablePending = round(result.cablePendingAmount);
        _dueAmount = cablePending;          // due_amount for mpay (STB leg)
        _billingId = result.billingId;      // billingId for mpay (from gpa)
        broadcasterPending =
            round(result.broadcasterPendingAmount); // broadband pending
        lastPaidAmount = result.lastPaidAmount; // Android last_paid_amount
        paymentsCount = result.paymentsCount;     // A4: confirm popup
        adjustmentCount = result.adjustmentCount; // A4: confirm popup
        // Android parity (CustomerMgmt_MakePayment_Fragment :1500-1507): prefill the
        // STB amount box with the pending only when it is positive; a zero/negative
        // pending (customer credit/advance) prefills "0", exactly like Android's
        // `if (pendingAmount > 0) et_amount.setText(...) else et_amount.setText("0")`.
        amountCtrl.text = cablePending > 0 ? cablePending.toStringAsFixed(2) : '0';
        // Android prefills the broadband field only when there is a broadband due.
        if (broadcasterPending > 0) {
          broadbandAmountCtrl.text = broadcasterPending.toStringAsFixed(2);
        }
        _applyScheme(result.scheme); // A-B3 (Android viewUpdating)
      } else {
        pendingError = result.statusMessage;
        pendingStatus = result.statusCode; // A3
      }
    } catch (e, s) {
      pendingError = 'Failed to load pending amount';
      pendingStatus = -1; // A3: no server reply
      ErrorHandlerService.recordError(e, s,
          reason: 'PaymentController.loadPendingAmount');
    } finally {
      pendingLoading = false;
      notifyListeners();
    }
  }

  /// Whether the discount field is offered. A-B2 / Android :549-551: role
  /// permission `customer_discount == "1"` AND `enable_payment_discount == 1`.
  bool get discountEnabled =>
      SessionService.instance.enablePaymentDiscount == 1 &&
      SessionService.instance.customerDiscount;

  /// Broadband customer? Android's master switch is "broadband account id
  /// non-empty" (set for customer_type 1 and 2). Empty → STB-only.
  bool get isBroadbandCustomer => customer.broadbandUserId.trim().isNotEmpty;

  /// BroadBand-ONLY (customer_type == 1). Android disables the STB amount +
  /// discount fields for these (CustomerMgmt_MakePayment_Fragment :303-310).
  bool get isBroadbandOnly =>
      isBroadbandCustomer && customer.customerType.trim() == '1';

  /// LCO-deposit dealer → Android freezes ONLY the STB `et_amount` to the full
  /// pending (setEnabled(false), CustomerMgmt_MakePayment_Fragment :1633/1659/
  /// 1704). It does NOT lock the broadband field and adds no submit validation.
  bool get amountLocked =>
      SessionService.instance.useLcoDeposit == 1 || schemeApplied; // + A-B3

  // ── A-B3: billing-scheme discount / penalty (Android viewUpdating) ─────────
  PendingScheme scheme = const PendingScheme();
  String schemeFrom = '0';  // 'D' discount · 'P' penalty · '0' none
  String schemeMode = '0';  // 'A' automatic · 'M' manual (checkbox)
  bool schemeApplied = false; // amount = total after discount/penalty, locked
  String discountPenaltyFlag = '0000'; // sent as discount_penalty_flag

  bool get schemeVisible =>
      (schemeFrom == 'D' || schemeFrom == 'P') &&
      (schemeMode == 'A' || schemeMode == 'M');
  bool get schemeIsDiscount => schemeFrom == 'D';
  double get schemeAmount =>
      schemeIsDiscount ? scheme.discountAmount : scheme.penaltyAmount;
  double get schemeTotal =>
      schemeIsDiscount ? scheme.totalAfterDiscount : scheme.totalAfterPenalty;
  /// Android disc_pen_chk text.
  String get schemeCheckLabel => schemeIsDiscount
      ? (schemeMode == 'A' ? 'Discount Applied' : 'Apply Discount')
      : (schemeMode == 'A' ? 'Penalty Applied' : 'Apply Penalty');
  /// Android dis_pen_tv text (shown with the amount while applied).
  String get schemeAppliedLabel =>
      schemeIsDiscount ? 'Discount Applied' : 'Penalty Applied';

  /// A-B3 / Android :1576-1606: pick the scheme whose dates contain today
  /// (server current_date), discount first, then penalty.
  void _applyScheme(PendingScheme s) {
    scheme = s;
    schemeFrom = '0';
    schemeMode = '0';
    schemeApplied = false;
    discountPenaltyFlag = '0000';
    final today = _schemeToday();
    DateTime? ymd(String v) => v.length >= 10 ? DateTime.tryParse(v.substring(0, 10)) : null;
    bool has(String a, String b) => a.length > 1 && b.length > 1;
    bool inRange(String a, String b) {
      final st = ymd(a), en = ymd(b);
      return st != null && en != null && !today.isBefore(st) && !today.isAfter(en);
    }
    final f = s.flag;
    if (has(s.discountStart, s.discountEnd)) {
      if (inRange(s.discountStart, s.discountEnd)) {
        schemeFrom = f[0].toUpperCase();
        schemeMode = f[1].toUpperCase();
      } else if (has(s.penaltyStart, s.penaltyEnd) &&
          inRange(s.penaltyStart, s.penaltyEnd)) {
        schemeFrom = f[2].toUpperCase();
        schemeMode = f[3].toUpperCase();
      }
    } else if (has(s.penaltyStart, s.penaltyEnd) &&
        inRange(s.penaltyStart, s.penaltyEnd)) {
      schemeFrom = f[2].toUpperCase();
      schemeMode = f[3].toUpperCase();
    }
    if (!schemeVisible) {
      schemeFrom = '0';
      schemeMode = '0';
      return;
    }
    // Automatic: applied at once and the checkbox is fixed (Android "A").
    if (schemeMode == 'A') setSchemeApplied(true);
  }

  /// Android LoginActivity.current_date (dd-MM-yyyy); the device date if absent.
  DateTime _schemeToday() {
    final p = SessionService.instance.serverCurrentDate.trim().split('-');
    if (p.length == 3) {
      final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
      if (d != null && m != null && y != null && y > 31) return DateTime(y, m, d);
    }
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// A-B3 / Android disc_pen_chk: applied → amount = total after the
  /// discount/penalty, locked, flag DA00/DM00/00PA/00PM; not applied → the
  /// pending amount again, editable, flag 0000.
  void setSchemeApplied(bool on) {
    if (!schemeVisible) return;
    schemeApplied = on;
    if (on) {
      amountCtrl.text = schemeTotal.toStringAsFixed(2);
      discountPenaltyFlag = schemeIsDiscount
          ? (schemeMode == 'A' ? 'DA00' : 'DM00')
          : (schemeMode == 'A' ? '00PA' : '00PM');
    } else {
      amountCtrl.text = cablePending > 0 ? cablePending.toStringAsFixed(2) : '0';
      discountPenaltyFlag = '0000';
    }
    notifyListeners();
  }

  /// Mirrors Android's discount TextWatcher (CustomerMgmt_MakePayment_Fragment
  /// afterTextChanged :607–639): the collector types the DISCOUNT and the amount
  /// field auto-updates to `due − discount`.
  /// - Discount > due → clamp amount to full due (Android :622).
  /// - Discount > (due × max% ÷ 100) → warn but still apply (Android :623–630):
  ///   the cap is a warning client-side; the server is the final authority.
  void onDiscountChanged() {
    final due = cablePending; // discount applies to the STB/cable leg (Android)
    final raw = discountCtrl.text.trim();
    final discount =
        (raw.isEmpty || raw == '.') ? 0.0 : (double.tryParse(raw) ?? 0.0);
    if (due < discount) {
      discountError = 'Discount should not exceed amount';
      amountCtrl.text = due.toStringAsFixed(2); // Android :622 — full due
    } else {
      final maxPct = SessionService.instance.maxDiscountPercentAllowed;
      final maxAllowed = due * maxPct / 100.0;
      if (discount > maxAllowed) {
        discountError =
            'Discount cannot exceed $maxPct% (max ₹${maxAllowed.toStringAsFixed(2)})';
      } else {
        discountError = null;
      }
      amountCtrl.text = (due - discount).toStringAsFixed(2); // Android :630/:634
    }
    notifyListeners();
  }

  // ── Validation ──────────────────────────────────────────────────────────────
  String? validate() {
    final stb = double.tryParse(amountCtrl.text) ?? 0.0;
    if (isBroadbandCustomer) {
      // Android skips the STB amount check for broadband customers; instead at
      // least one leg (STB or broadband) must be a valid positive amount.
      if (stb <= 0 && parsedBroadbandAmount <= 0) {
        return 'Please enter a valid amount';
      }
    } else {
      if (amountCtrl.text.isEmpty) return 'Please enter amount';
      if (stb <= 0) return 'Please enter a valid amount';
    }

    // A-B1 / Android CustomerMgmt_MakePayment_Fragment :693: dealer setting
    // "restrict partial payment" — a cable-only customer must pay the full due
    // (amount + discount >= cable pending). Compared in paise to avoid
    // floating-point noise on a prefilled full amount.
    if (!isBroadbandCustomer &&
        SessionService.instance.restrictPartialPayment == 1) {
      final discount =
          discountEnabled ? (double.tryParse(discountCtrl.text) ?? 0.0) : 0.0;
      if (((stb + discount) * 100).round() < (cablePending * 100).round()) {
        return 'Partial payments not allowed. Please pay the full amount';
      }
    }

    if (_paymentMethod == 'bank') {
      if (chequeNoCtrl.text.trim().isEmpty) return 'Please enter Cheque / DD number';
      if (bankNameCtrl.text.trim().isEmpty) return 'Please enter bank name';
      if (branchCtrl.text.trim().isEmpty)   return 'Please enter branch';
      if (_instrumentDate == null)           return 'Please select instrument date';
    }
    return null;
  }

  double get parsedAmount => double.tryParse(amountCtrl.text) ?? 0.0;
  double get parsedBroadbandAmount =>
      double.tryParse(broadbandAmountCtrl.text) ?? 0.0;

  /// Cheque/instrument date in Android's exact wire format: "yyyy-MM-dd", or
  /// "0000-00-00" when no date was picked (CustomerMgmt_MakePayment_Fragment
  /// :1788-1791). `validate()` already requires a date for bank mode, so this is
  /// the defensive fallback only.
  String get _chequeDate {
    final d = _instrumentDate;
    if (d == null) return '0000-00-00';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  bool get _isCombined =>
      isBroadbandCustomer && customer.customerType.trim() == '2';

  /// Android `pendingAmount` for the receipt's TOT.DUE.AMT: the GPA due of the
  /// primary leg — broadband pending for a BroadBand-only customer, else STB
  /// (CustomerMgmt_MakePayment_Fragment :1487 / :2087).
  double get receiptDueAmount =>
      (isBroadbandCustomer && !_isCombined) ? broadcasterPending : _dueAmount;

  /// Android `outstanding` for the receipt's OUT.AMT: remaining after this
  /// payment (CustomerMgmt_MakePayment_Fragment :2088 / :2100-2106).
  /// BroadBand-only: broadcasterPending − bbPaid. Else: due − paid − discount.
  double get receiptOutAmount {
    if (isBroadbandCustomer && !_isCombined) {
      return broadcasterPending - parsedBroadbandAmount;
    }
    // A-B3 / Android :2089-2096: with a scheme applied, outstanding is
    // counted from the total after the discount / penalty.
    if (discountPenaltyFlag.contains('D')) {
      return scheme.totalAfterDiscount - parsedAmount;
    }
    if (discountPenaltyFlag.contains('P')) {
      return scheme.totalAfterPenalty - parsedAmount;
    }
    final discount = double.tryParse(discountCtrl.text) ?? 0.0;
    return _dueAmount - parsedAmount - discount;
  }

  // ── Pay Now (STB online — real makePayments / mpay) ──────────────────────────
  /// Calls the server `makePayments` (STB cash) and returns a receipt [Payment]
  /// built from the SERVER response. Returns null if a duplicate submit is
  /// blocked. Throws on server rejection / network failure (screen shows it).
  ///
  /// SCOPE: STB cash + bank/cheque (Android's only two modes) + broadband leg
  /// (🟡 under live verification — see server docs/BROADBAND_PAYMENT_FLOW.md).
  /// Bank now sends chequeNo/bank/branch/chequeDate (Android :1876-1879).
  Future<Payment?> pay() async {
    if (_isStoring) return null; // double-submit guard
    _setStoring(true);
    try {
      final mobile = mobileCtrl.text.isEmpty
          ? customer.primaryMobileNumber
          : mobileCtrl.text;

      final isBank = _paymentMethod == 'bank';
      final result = await MakePaymentRepository.instance.pay(
        altCustomerId:   int.tryParse(customer.lcoCustomerId) ?? 0,
        billingId:       _billingId,             // from gpa
        amount:          parsedAmount,           // = due − discount (user-entered)
        dueAmount:       _dueAmount,             // from gpa
        // A-B2 / Android :1851-1859: 0 unless the discount is permitted.
        discountApplied: discountEnabled
            ? (double.tryParse(discountCtrl.text) ?? 0.0)
            : 0.0,
        modeType:        _paymentMethod,         // "cash" or "bank"
        sendSms:         _sendSms,
        remarks:         remarksCtrl.text.trim(),
        mobileNumber:    mobile,
        // Bank/Cheque leg — Android populates these only in the "bank" branch
        // (CustomerMgmt_MakePayment_Fragment :1876-1879); cash sends empty.
        chequeNo:        isBank ? chequeNoCtrl.text.trim() : '',
        bank:            isBank ? bankNameCtrl.text.trim() : '',
        branch:          isBank ? branchCtrl.text.trim()   : '',
        chequeDate:      isBank ? _chequeDate              : '',
        discountPenaltyFlag: discountPenaltyFlag, // A-B3
        // Broadband leg — sent only for broadband customers (else 0/empty),
        // mirroring Android. broadband_due = the broadband pending as text.
        broadbandAmount: isBroadbandCustomer ? parsedBroadbandAmount : 0.0,
        broadbandUserId: isBroadbandCustomer ? customer.broadbandUserId : '',
        broadbandDue:    isBroadbandCustomer ? broadcasterPending.toString() : '',
        isForRenewal:    isBroadbandCustomer ? (_isForRenewal ? '1' : '0') : '',
        // Last-known GPS captured at screen open (Android parity; '0.0' fallback).
        latitude:        _latitude,
        longitude:       _longitude,
      );

      if (!result.isSuccess) {
        // Surface the server's message — do NOT build a receipt on failure.
        throw Exception(
          result.statusMessage.isEmpty ? 'Payment failed' : result.statusMessage,
        );
      }
      lastResult = result; // keep for the receipt (dealer name, bill month, …)

      // Build the receipt from the SERVER response — server-issued receipt number.
      final payment = Payment(
        customerId:     customer.lcoCustomerId,
        customerName:   result.customerName.isNotEmpty
            ? result.customerName
            : customer.name,
        customerMobile: mobile,
        amount:         result.amount != 0 ? result.amount : parsedAmount,
        paymentMethod:  _paymentMethod,
        paymentDate:    DateTime.now(),
        transactionId:  result.receiptNumber,    // server receipt no (never fabricated)
        status:         'completed',
        smsSent:        _sendSms,
        synced:         true,
      );

      // Fire notification (non-blocking)
      NotificationService.showPaymentNotification(
        title: 'Payment Successful',
        body: '₹${payment.amount.toStringAsFixed(2)} received from ${customer.name}',
      );

      return payment;
    } catch (e, s) {
      ErrorHandlerService.recordError(e, s, reason: 'PaymentController.pay');
      rethrow;
    } finally {
      _setStoring(false);
    }
  }

  // ── Pay Later (collection schedule) ─────────────────────────────────────────
  // Pay Later — server-side (Android parity: lookup → submit). The legacy local
  // CollectionSchedule path (DatabaseHelper.insert/searchCollectionSchedule) is kept
  // but unused; see OPERATIONAL_MODULES_PARITY.md.
  //
  // Step 1: look up this customer's schedule record (Android gethitapipaylater) —
  // gives the server customer_id, current values, is_editable, and the status LOV.
  Future<PayLaterListResult> lookupPayLater() {
    // System customer id = Android altCustId = JSON customer_id = lcoCustomerId
    // (NOT alt_cust_id, which the server rejects as a non-integer id).
    return PayLaterRepository.instance.getPayLaterList(
      customerId: customer.lcoCustomerId,
      scheduledStartDate: '',
      scheduledEndDate: '',
    );
  }

  // Step 2: create/update (Android gethitapipaylatersubmit → scheduled_collection_create).
  Future<PayLaterWriteResult> submitPayLater({
    required String customerId,
    required DateTime scheduleDate,
    required String status,
    required String remarks,
    required String isEdited,
  }) {
    final d = '${scheduleDate.year}-'
        '${scheduleDate.month.toString().padLeft(2, '0')}-'
        '${scheduleDate.day.toString().padLeft(2, '0')}';
    return PayLaterRepository.instance.submitPayLater(
      customerId: customerId,
      scheduledDate: d,
      status: status,
      remarks: remarks,
      isEdited: isEdited,
    );
  }

  // ── Dispose ─────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    for (final c in [
      amountCtrl, discountCtrl, remarksCtrl, mobileCtrl,
      chequeNoCtrl, bankNameCtrl, branchCtrl,
      broadbandAmountCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
