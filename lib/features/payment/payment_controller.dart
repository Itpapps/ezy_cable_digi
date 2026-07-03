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

  PaymentController({required this.customer});

  // ── TextEditingControllers ──────────────────────────────────────────────────
  final amountCtrl    = TextEditingController();
  final discountCtrl  = TextEditingController();
  final remarksCtrl   = TextEditingController();
  final mobileCtrl    = TextEditingController();
  final chequeNoCtrl  = TextEditingController();
  final bankNameCtrl  = TextEditingController();
  final branchCtrl    = TextEditingController();
  final upiIdCtrl     = TextEditingController();
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
  int     _billingId     = 0; // bill to settle (from gpa) — sent to mpay
  double  _dueAmount     = 0; // due_amount (from gpa) — sent to mpay (= cable leg)
  String? discountError;      // set when discount > due (mirrors Android toast)
  double  cablePending   = 0; // STB/cable leg (from gpa) — the STB amount + due
  double  broadcasterPending = 0; // broadband pending (from gpa; 0 for STB)
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
        cablePending = result.cablePendingAmount;
        _dueAmount = cablePending;          // due_amount for mpay (STB leg)
        _billingId = result.billingId;      // billingId for mpay (from gpa)
        broadcasterPending = result.broadcasterPendingAmount; // broadband pending
        amountCtrl.text = cablePending.toStringAsFixed(2);
        // Android prefills the broadband field only when there is a broadband due.
        if (broadcasterPending > 0) {
          broadbandAmountCtrl.text = broadcasterPending.toStringAsFixed(2);
        }
      } else {
        pendingError = result.statusMessage;
      }
    } catch (e, s) {
      pendingError = 'Failed to load pending amount';
      ErrorHandlerService.recordError(e, s,
          reason: 'PaymentController.loadPendingAmount');
    } finally {
      pendingLoading = false;
      notifyListeners();
    }
  }

  /// Whether the discount field is offered. Android gates on
  /// `customer_discount == "1" && enable_payment_discount == 1`. Per the locked
  /// scope, v1 gates on the login flag only (role permission deferred).
  bool get discountEnabled => SessionService.instance.enablePaymentDiscount == 1;

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
  bool get amountLocked => SessionService.instance.useLcoDeposit == 1;

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

    if (_paymentMethod == 'bank') {
      if (chequeNoCtrl.text.trim().isEmpty) return 'Please enter Cheque / DD number';
      if (bankNameCtrl.text.trim().isEmpty) return 'Please enter bank name';
      if (branchCtrl.text.trim().isEmpty)   return 'Please enter branch';
      if (_instrumentDate == null)           return 'Please select instrument date';
    }
    if (_paymentMethod == 'upi') {
      if (upiIdCtrl.text.trim().isEmpty) return 'Please enter UPI Id';
    }
    return null;
  }

  double get parsedAmount => double.tryParse(amountCtrl.text) ?? 0.0;
  double get parsedBroadbandAmount =>
      double.tryParse(broadbandAmountCtrl.text) ?? 0.0;

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
    final discount = double.tryParse(discountCtrl.text) ?? 0.0;
    return _dueAmount - parsedAmount - discount;
  }

  // ── Pay Now (STB online — real makePayments / mpay) ──────────────────────────
  /// Calls the server `makePayments` (STB cash) and returns a receipt [Payment]
  /// built from the SERVER response. Returns null if a duplicate submit is
  /// blocked. Throws on server rejection / network failure (screen shows it).
  ///
  /// SCOPE: STB cash (✅ verified) + broadband leg (🟡 under live verification —
  /// see server docs/BROADBAND_PAYMENT_FLOW.md). bank/card/upi NOT handled.
  Future<Payment?> pay() async {
    if (_isStoring) return null; // double-submit guard
    _setStoring(true);
    try {
      final mobile = mobileCtrl.text.isEmpty
          ? customer.primaryMobileNumber
          : mobileCtrl.text;

      final result = await MakePaymentRepository.instance.pay(
        altCustomerId:   int.tryParse(customer.lcoCustomerId) ?? 0,
        billingId:       _billingId,             // from gpa
        amount:          parsedAmount,           // = due − discount (user-entered)
        dueAmount:       _dueAmount,             // from gpa
        discountApplied: double.tryParse(discountCtrl.text) ?? 0.0,
        modeType:        _paymentMethod,         // "cash" (Phase-1)
        sendSms:         _sendSms,
        remarks:         remarksCtrl.text.trim(),
        mobileNumber:    mobile,
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
      chequeNoCtrl, bankNameCtrl, branchCtrl, upiIdCtrl,
      broadbandAmountCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
