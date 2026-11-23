import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/data/customer.dart';
import '../../core/utils/share_origin.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/settings_store.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../customer/data/act_deact_repository.dart';
import '../customer/data/onetime_charges_repository.dart';
import '../payment/printer_launcher.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ACT-DEACT REPORT — real `packageActDeactReport` (Android Act_Deact_Report).
// Sends the system customer_id (lcoCustomerId). 6 fields per row.
// ─────────────────────────────────────────────────────────────────────────────
class ActDeactReportScreen extends StatefulWidget {
  final Customer customer;
  const ActDeactReportScreen({super.key, required this.customer});

  @override
  State<ActDeactReportScreen> createState() => _ActDeactReportScreenState();
}

class _ActDeactReportScreenState extends State<ActDeactReportScreen> {
  bool _loading = true;
  String _message = '';
  List<ActDeactItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r =
        await ActDeactRepository.instance.fetch(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = r.items;
      _message = r.statusCode == 0 ? '' : r.statusMessage;
    });
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware frame (page, title bar, spinner, empty text). Theme 1 keeps
  // exactly the previous blue/white; the white cards are unchanged.
  Widget _buildPage(BuildContext context) {
    final customer = widget.customer;
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _appBar(context, 'ACT-DEACT REPORT'),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Theme 2 only: lift the white card off the light page.
              boxShadow: _lightCardShadow(t),
            ),
            child: Column(
              children: [
                _cRow('Customer Name', customer.name),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _cRow('LCO Customer Id', customer.lcoCustomerId),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _cRow('Serial Number', customer.serialNumber.isEmpty ? customer.boxNumber : customer.serialNumber, isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildBody(AppThemeConst t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No act/deact records found' : _message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: t.isLight ? t.subtitleText : Colors.white70),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final it = _items[i];
        return _SimpleCard(data: {
          'Package Name': it.packageName,
          'Box Number': it.boxNumber,
          'Operation Type': it.operationType,
          'Created Date': it.createdDate,
          'Error Message': it.errorMessage,
          'Created By': it.createdBy,
        });
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONE TIME CHARGES
// ─────────────────────────────────────────────────────────────────────────────
class OneTimeChargesScreen extends StatefulWidget {
  final Customer customer;
  // When non-null, the screen is in EDIT mode (Android Editonetime_Frag): the
  // form is pre-filled and save() reuses the same endpoint with the real id.
  final OnetimeChargeItem? editItem;
  const OneTimeChargesScreen({
    super.key,
    required this.customer,
    this.editItem,
  });

  @override
  State<OneTimeChargesScreen> createState() => _OneTimeChargesScreenState();
}

class _OneTimeChargesScreenState extends State<OneTimeChargesScreen> {
  // Dynamic charge types (Android chargeTypes API).
  List<ChargeType> _chargeTypes = [];
  ChargeType? _chargeType;
  bool _loadingTypes = true;
  bool _saving = false;
  bool _instrument = false; // Android "Instrument Details" checkbox
  DateTime _createdDate = DateTime.now();
  // null = no instrument date yet (EDIT of a charge without a cheque date).
  DateTime? _instrumentDate = DateTime.now();
  final _amountCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _chequeCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.editItem;
    if (e != null) {
      _amountCtrl.text = e.amount;
      _remarksCtrl.text = e.remarks;
      _chequeCtrl.text = e.chequeDdNo;
      _bankCtrl.text = e.bankName;
      _branchCtrl.text = e.branchName;
      // Paid box mirrors the stored paid status (Android Editonetime_Frag
      // :178-182 paidunpaid.equals("1"); same rule as the history list).
      // Cheque/bank/branch text must not decide it: the server stores
      // cheque_dd_no = 0 for cash charges, which pre-ticked unpaid charges.
      _instrument = e.paidUnpaid == '1' || e.paidUnpaid.toLowerCase() == 'paid';
      _createdDate = _parseDate(e.date, _createdDate);
      // Android Editonetime_Frag :168-172: no stored cheque date ("NA" /
      // "0000-00-00") → the instrument date starts EMPTY.
      final cd = e.chequeDate.trim();
      _instrumentDate = (cd.isEmpty || cd == 'NA' || cd == '0000-00-00')
          ? null
          : _parseDate(cd, DateTime.now());
    }
    _loadChargeTypes();
  }

  /// Best-effort parse for a pre-filled date (yyyy-MM-dd or dd/MM/yyyy). The user
  /// reviews the date field before saving, so a fallback is safe.
  DateTime _parseDate(String s, DateTime fallback) {
    final t = s.trim();
    if (t.isEmpty || t == '0000-00-00') return fallback;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final p = t.split(RegExp(r'[/-]'));
    if (p.length == 3) {
      final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
      if (d != null && m != null && y != null && y > 31) {
        return DateTime(y, m, d); // dd/MM/yyyy
      }
    }
    return fallback;
  }

  Future<void> _loadChargeTypes() async {
    final r = await OnetimeChargesRepository.instance
        .fetchChargeTypes(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _chargeTypes = r.types;
      final editName = widget.editItem?.chargeTypeName.trim();
      _chargeType = r.types.isEmpty
          ? null
          : r.types.firstWhere(
              (t) => editName != null && t.name.trim() == editName,
              orElse: () => r.types.first,
            );
      _loadingTypes = false;
    });
    // C8 / Android OneTimeCharges_Frag chargetypes_opr (:296-330) and
    // Editonetime_Frag (:385-419): status 1 → "No Details Found" dialog with
    // the server message (OK closes it; the screen stays); failed call →
    // "Failed." toast. Any other status shows nothing (Android).
    if (r.statusCode == 1) {
      // Edit mode: Editonetime_Frag puts the message in the title (:388-389).
      final isEdit = widget.editItem != null;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isEdit ? '${r.statusMessage}!' : 'No Details Found!'),
          content: Text(isEdit ? 'No Details Found' : r.statusMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (r.statusCode == 3) {
      // Editonetime_Frag :418 shows a mistyped "Faileddcccvcvcccxc.";
      // "Failed." (OneTimeCharges_Frag :329) is used for both screens.
      showPremiumSnackBar(context, 'Failed.', isError: true);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _remarksCtrl.dispose();
    _chequeCtrl.dispose();
    _bankCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Instrument date as sent/printed: '' while no date is set.
  String get _instrumentYmd {
    final d = _instrumentDate;
    return d == null ? '' : _ymd(d);
  }

  Future<void> _pickDate({required bool instrument}) async {
    final base =
        instrument ? (_instrumentDate ?? DateTime.now()) : _createdDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // Android: must not be after today
    );
    if (picked != null) {
      setState(() {
        if (instrument) {
          _instrumentDate = picked;
        } else {
          _createdDate = picked;
        }
      });
    }
  }

  void _snack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_chargeType == null) {
      _snack('Charge type not loaded');
      return;
    }
    // Android OneTimeCharges_Frag / Editonetime_Frag: empty amount →
    // "Amount should not be empty". A 0 / non-number amount stays blocked.
    final amount = _amountCtrl.text.trim();
    if (amount.isEmpty) {
      _snack('Amount should not be empty');
      return;
    }
    if ((double.tryParse(amount) ?? 0) <= 0) {
      _snack('Please enter a valid amount');
      return;
    }
    // NEW charge: Android validates ONLY the amount — cheque/bank/branch are
    // optional (OneTimeCharges_Frag :197-230).
    // C-B5 / Android Editonetime_Frag :264-300: in EDIT mode, with Paid
    // ticked AND an instrument date set, cheque/DD no., bank and branch are
    // required — checked in this order, Android's messages. Paid ticked with
    // no instrument date saves after the amount check only.
    if (widget.editItem != null && _instrument && _instrumentDate != null) {
      if (_chequeCtrl.text.trim().isEmpty) {
        _snack('Enter valid cheque/dd number');
        return;
      }
      if (_bankCtrl.text.trim().isEmpty) {
        _snack('Enter  Bank name');
        return;
      }
      if (_branchCtrl.text.trim().isEmpty) {
        _snack('Enter  Branch name');
        return;
      }
    }
    setState(() => _saving = true);
    // C6 + C12 / Android OneTimeCharges_Frag :356 and Editonetime_Frag :445:
    // non-cancellable "Loading...Please wait..." while saving (Back ignored);
    // save() never throws (70 s → status 3), so the pop below always closes it.
    showPremiumLoading(context,
        message: 'Loading...Please wait...', canPop: false);
    final r = await OnetimeChargesRepository.instance.save(
      customerId: widget.customer.lcoCustomerId,
      chargeType: _chargeType!.id,
      amount: _amountCtrl.text.trim(),
      chqDd: _instrument ? _chequeCtrl.text.trim() : '',
      bank: _instrument ? _bankCtrl.text.trim() : '',
      branch: _instrument ? _branchCtrl.text.trim() : '',
      chqDdDate: _instrument ? _instrumentYmd : '',
      remarks: _remarksCtrl.text.trim(),
      createdDate: _ymd(_createdDate),
      checkPaidUnpaid: _instrument ? 1 : 2, // Android: 1 cheque · 2 cash
      // Edit mode (Android Editonetime_Frag): real id + receipt_no → ot_type=1.
      onetimeChargeId: widget.editItem?.onetimeChargeId ?? '0',
      receiptNo: widget.editItem?.receiptNo ?? '',
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _saving = false);
    if (r.isSuccess) {
      await _showSaved(r.statusMessage);
    } else {
      _snack(r.statusMessage.isEmpty ? 'Save failed' : r.statusMessage);
    }
  }

  /// C-B4 — Android success handling after a save (status 0):
  ///  • EDIT (Editonetime_Frag :462-500): "Success!" + server message, OK
  ///    only → back.
  ///  • NEW (OneTimeCharges_Frag :375-415): "Success!" + server message with
  ///    OK (→ back) and Print (→ the One-Time Charge details page with a print
  ///    button, DisplayOnetimeChrages). Returning from that page re-creates
  ///    Android's form (fresh fields + charge types reloaded) — mirrored by
  ///    [_resetForNewCharge], so the saved values can't be re-submitted.
  /// The popup can't be dismissed by tapping outside; a system Back on it
  /// counts as OK (back), never as "stay on the filled form".
  Future<void> _showSaved(String message) async {
    final isEdit = widget.editItem != null;
    // Capture the saved values now (Android passes them in the bundle).
    final slip = isEdit
        ? null
        : OneTimeChargeSlip(
            chargeType: _chargeType?.name ?? '',
            amount: (double.tryParse(_amountCtrl.text.trim()) ??
                    _amountCtrl.text.trim())
                .toString(), // Android String.valueOf(Double) e.g. "100.0"
            createdDate: _ymd(_createdDate),
            bank: _instrument ? _bankCtrl.text.trim() : '',
            branch: _instrument ? _branchCtrl.text.trim() : '',
            chequeDd: _instrument ? _chequeCtrl.text.trim() : '',
            chequeDate: _instrument ? _instrumentYmd : '',
            remarks: _remarksCtrl.text.trim(),
            paid: _instrument, // Android checked 1 → Paid · 2 → Unpaid
          );
    final print = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Success!'),
        content: message.isEmpty ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('OK'),
          ),
          // Print only for a NEW charge, and only where Bluetooth printing
          // exists (hidden on iOS like every other Print in the app).
          if (slip != null && AppConfig.bluetoothPrintingEnabled)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Print'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (print == true && slip != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OneTimeChargeDetailsScreen(customer: widget.customer, slip: slip),
        ),
      );
      if (mounted) _resetForNewCharge();
      return;
    }
    Navigator.pop(context); // OK / Back → leave the form (Android popBackStack)
  }

  /// C-B4: Android re-creates OneTimeCharges_Frag when the user comes back
  /// from the details page — empty fields, today's dates, charge types
  /// fetched again (first type selected).
  void _resetForNewCharge() {
    setState(() {
      _amountCtrl.clear();
      _remarksCtrl.clear();
      _chequeCtrl.clear();
      _bankCtrl.clear();
      _branchCtrl.clear();
      _instrument = false;
      _createdDate = DateTime.now();
      _instrumentDate = DateTime.now();
      _chargeTypes = [];
      _chargeType = null;
      _loadingTypes = true;
    });
    _loadChargeTypes();
  }

  String get _fmtDate => _ymd(_createdDate);

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware page + title bar. Theme 1 keeps exactly the previous blue;
  // the white form card and everything in it are unchanged.
  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _appBar(context,
          widget.editItem == null ? 'ONE TIME CHARGES' : 'EDIT ONE TIME CHARGES'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            // Theme 2 only: lift the white card off the light page.
            boxShadow: _lightCardShadow(t),
          ),
          child: Column(
            children: [
              // Customer Name
              _FormRow(label: 'Customer Name', child: Text(widget.customer.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1)))),
              const SizedBox(height: 14),

              // Charge Type (dynamically loaded from chargeTypes API)
              _FormRow(
                label: 'Charge Type',
                child: _loadingTypes
                    ? const SizedBox(
                        height: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    : DropdownButtonFormField<ChargeType>(
                        initialValue: _chargeType,
                        isExpanded: true,
                        decoration: _otcField(),
                        // Popup list look only (same as Search Customer).
                        menuMaxHeight: 300,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 3,
                        icon: const Icon(Icons.keyboard_arrow_down),
                        items: _chargeTypes
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _chargeType = v),
                      ),
              ),
              const SizedBox(height: 14),

              // "Paid" checkbox (Android onetime_cb) → reveals optional cheque/
              // bank/branch/instrument-date; sets check_paid_unpaid (1 / 2).
              _FormRow(
                label: 'Paid',
                child: Checkbox(
                  value: _instrument,
                  onChanged: (v) => setState(() => _instrument = v ?? false),
                  activeColor: const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 14),
              if (_instrument) ...[
                _FormRow(
                  label: 'Instrument Date',
                  child: GestureDetector(
                    onTap: () => _pickDate(instrument: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                _instrumentDate == null
                                    ? 'Select date'
                                    : _instrumentYmd,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _instrumentDate == null
                                        ? Colors.grey.shade500
                                        : const Color(0xFF0D47A1))),
                          ),
                          const Icon(Icons.calendar_month, color: Colors.red, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _FormRow(
                  label: 'Cheque / DD No',
                  child: TextField(
                    controller: _chequeCtrl,
                    decoration: _otcField(),
                  ),
                ),
                const SizedBox(height: 14),
                _FormRow(
                  label: 'Bank',
                  child: TextField(
                    controller: _bankCtrl,
                    decoration: _otcField(),
                  ),
                ),
                const SizedBox(height: 14),
                _FormRow(
                  label: 'Branch',
                  child: TextField(
                    controller: _branchCtrl,
                    decoration: _otcField(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Created date
              _FormRow(
                label: 'Created date',
                child: GestureDetector(
                  onTap: () => _pickDate(instrument: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_fmtDate,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
                        ),
                        const Icon(Icons.calendar_month, color: Colors.red, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Amount
              _FormRow(
                label: 'Amount *',
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _otcField(),
                ),
              ),
              const SizedBox(height: 14),

              // Remarks
              _FormRow(
                label: 'Remarks',
                child: TextField(
                  controller: _remarksCtrl,
                  decoration: _otcField(),
                ),
              ),
              const SizedBox(height: 24),

              // Save Payment button
              GestureDetector(
                onTap: _save,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('SAVE PAYMENT',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0D47A1))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// C-B4: DISPLAY ONE TIME CHARGES — Android DisplayOnetimeChrages
// (fragment_display_onetime_chrages.xml), opened by "Print" after a NEW
// one-time charge is saved. Shows the saved values and prints Android's
// "ONETIME CHARGES" slip (BluetoothChatService.Onetimecharge_write).
// ─────────────────────────────────────────────────────────────────────────────

/// The values of a just-saved one-time charge (Android's Print bundle).
class OneTimeChargeSlip {
  final String chargeType;
  final String amount;
  final String createdDate;
  final String bank;
  final String branch;
  final String chequeDd;
  final String chequeDate;
  final String remarks;
  final bool paid;
  const OneTimeChargeSlip({
    required this.chargeType,
    required this.amount,
    required this.createdDate,
    required this.bank,
    required this.branch,
    required this.chequeDd,
    required this.chequeDate,
    required this.remarks,
    required this.paid,
  });
}

class OneTimeChargeDetailsScreen extends StatefulWidget {
  final Customer customer;
  final OneTimeChargeSlip slip;
  const OneTimeChargeDetailsScreen(
      {super.key, required this.customer, required this.slip});

  @override
  State<OneTimeChargeDetailsScreen> createState() =>
      _OneTimeChargeDetailsScreenState();
}

class _OneTimeChargeDetailsScreenState
    extends State<OneTimeChargeDetailsScreen> {
  final RealBluetoothService _printerService = RealBluetoothService();

  @override
  void initState() {
    super.initState();
    // Printer header/footer (Android reads the printer-settings prefs).
    SettingsStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  // Android shows R.string.not_available ("NA") for an empty value.
  String _na(String v) => v.trim().isEmpty ? 'NA' : v.trim();
  String get _chequeDate {
    final t = widget.slip.chequeDate.trim();
    return (t.isEmpty || t == '0000-00-00') ? 'NA' : t;
  }

  String get _paidLabel => widget.slip.paid ? 'Paid' : 'Unpaid';

  /// Android `new Date().toString()` order: "EEE MMM dd yyyy HH:mm:ss".
  String _timestamp() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wd[n.weekday - 1]} ${mo[n.month - 1]} ${two(n.day)} ${n.year} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  /// 1:1 with BluetoothChatService.Onetimecharge_write (offline_report=10).
  /// 97BT has its own title spacing and a 7-space date indent.
  List<String> _printLines(ReceiptFormat fmt) {
    final c = widget.customer;
    final st = SettingsStore.instance;
    final s = widget.slip;
    final sep = fmt.sep;
    return [
      sep, st.header1, sep, st.header2, sep,
      fmt.is97bt
          ? '          ONETIME CHARGES         '
          : '        ONETIME CHARGES        ',
      sep,
      '${fmt.is97bt ? '       ' : ''}${_timestamp()}',
      sep,
      'CUSTOMER NAME    :${c.name}',
      'ADDRESS          :${c.address}',
      'MOBILE           :${c.primaryMobileNumber}',
      'CHARGE TYPE      :${s.chargeType}',
      'AMOUNT           :${s.amount}',
      'CREATED DATE     :${s.createdDate}',
      'BANK             :${_na(s.bank)}',
      'BRANCH           :${_na(s.branch)}',
      'CHEQUE/DD NO.    :${_na(s.chequeDd)}',
      'CHEQUE DATE      :$_chequeDate',
      'REMARKS          :${_na(s.remarks)}',
      'PAID/UNPAID      :$_paidLabel',
      sep, st.footer1, sep, st.footer2, sep,
    ];
  }

  void _print() => launchThermalPrint(
        context: context,
        printerService: _printerService,
        buildLines: _printLines,
      );

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware page + title bar (same as the One Time Charges form it opens
  // from). Theme 1 keeps exactly the previous blue/white.
  Widget _buildPage(BuildContext context) {
    final c = widget.customer;
    final s = widget.slip;
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _appBar(context, 'DISPLAY ONE TIME CHARGES'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                // Theme 2 only: lift the white card off the light page.
                boxShadow: _lightCardShadow(t),
              ),
              child: Column(
                children: [
                  _cRow('Customer Name', c.name),
                  _cRow('Address', c.address),
                  _cRow('Mobile No.', c.primaryMobileNumber),
                  _cRow('Charge Type', s.chargeType),
                  _cRow('Amount', s.amount),
                  _cRow('Created Date', s.createdDate),
                  _cRow('Bank', _na(s.bank)),
                  _cRow('Branch', _na(s.branch)),
                  _cRow('Cheque/DD No', _na(s.chequeDd)),
                  _cRow('Cheque Date', _chequeDate),
                  _cRow('Remarks', _na(s.remarks)),
                  _cRow('Paid/Unpaid', _paidLabel, isLast: true),
                ],
              ),
            ),
            if (AppConfig.bluetoothPrintingEnabled) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.print),
                  label: const Text('Print',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  // On the page itself: Theme 1 keeps the white button;
                  // Theme 2 uses a filled accent button (white would vanish).
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.isLight ? t.accent : Colors.white,
                    foregroundColor:
                        t.isLight ? Colors.white : const Color(0xFF0D47A1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONE TIME HISTORY
// ─────────────────────────────────────────────────────────────────────────────
class OneTimeHistoryScreen extends StatefulWidget {
  final Customer customer;
  const OneTimeHistoryScreen({super.key, required this.customer});

  @override
  State<OneTimeHistoryScreen> createState() => _OneTimeHistoryScreenState();
}

class _OneTimeHistoryScreenState extends State<OneTimeHistoryScreen> {
  bool _loading = true;
  String _message = '';
  List<OnetimeChargeItem> _items = const [];

  // Thermal-print pipeline (same engine the receipt uses).
  final RealBluetoothService _printerService = RealBluetoothService();

  @override
  void initState() {
    super.initState();
    _load();
    // Header/footer for the print + share blocks (Android reads printer settings).
    SettingsStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await OnetimeChargesRepository.instance
        .fetchHistory(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = r.items;
      _message = r.statusCode == 0 ? '' : r.statusMessage;
    });
  }

  Map<String, dynamic> _toCard(OnetimeChargeItem it) => {
        'receiptNo': it.receiptNo.isEmpty ? 'NA' : it.receiptNo,
        'billNo': it.billNo.isEmpty ? 'NA' : it.billNo,
        'chargeType': it.chargeTypeName,
        'amount': it.amount,
        'createdDate': it.date,
        'bank': it.bankName.isEmpty ? 'NA' : it.bankName,
        'branch': it.branchName.isEmpty ? 'NA' : it.branchName,
        'chequeNo': it.chequeDdNo.isEmpty ? '0' : it.chequeDdNo,
        'chequeDate': it.chequeDate.isEmpty ? 'NA' : it.chequeDate,
        'remarks': it.remarks.isEmpty ? 'NA' : it.remarks,
        'paid': it.paidUnpaid == '1' || it.paidUnpaid.toLowerCase() == 'paid',
      };

  // ── Print / Share helpers (Android parity) ───────────────────────────────
  static const _sep = '--------------------------------'; // Android `line` (32)

  String _na(String v) => v.trim().isEmpty ? 'Not Available' : v.trim();
  String _naDate(String v) {
    final t = v.trim();
    return (t.isEmpty || t == '0000-00-00') ? 'Not Available' : t;
  }
  String _paidLabel(OnetimeChargeItem it) =>
      (it.paidUnpaid == '1' || it.paidUnpaid.toLowerCase() == 'paid')
          ? 'Paid'
          : 'UnPaid';

  /// Android's `new Date().toString()` order: "EEE MMM dd yyyy HH:mm:ss"
  /// (Datesttings[0] [1] [2] [5] [3]).
  String _timestamp() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wd[n.weekday - 1]} ${mo[n.month - 1]} ${two(n.day)} ${n.year} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  /// Thermal print lines — 1:1 with BluetoothChatService `offline_report=9`
  /// (ONETIME CHARGES block). Header/footer printed unconditionally (Android).
  List<String> _buildOneTimePrintLines(OnetimeChargeItem it, ReceiptFormat fmt) {
    final c = widget.customer;
    final s = SettingsStore.instance;
    final sep = fmt.sep;
    return [
      sep, s.header1, sep, s.header2,
      sep, '        ONETIME CHARGES        ',
      sep, _timestamp(), sep,
      'CUSTOMER NAME    :${c.name}',
      'ADDRESS          :${c.address}',
      'MOBILE           :${c.primaryMobileNumber}',
      'CHARGE TYPE      :${it.chargeTypeName}',
      'AMOUNT           :${it.amount}',
      'CREATED DATE     :${it.date}',
      'BANK             :${_na(it.bankName)}',
      'BRANCH           :${_na(it.branchName)}',
      'CHEQUE/DD NO.    :${_na(it.chequeDdNo)}',
      'CHEQUE DATE      :${_naDate(it.chequeDate)}',
      'REMARKS          :${_na(it.remarks)}',
      'PAID/UNPAID      :${_paidLabel(it)}',
      sep, s.footer1, sep, s.footer2, sep,
    ];
  }

  /// Share PDF lines — 1:1 with OnetimeHistory_Adapter.ShareOneTimeHistory
  /// (header/footer only when non-empty). NOTE: Android's empty-cheque-date case
  /// mislabels the line "CHEQUE/DD NO."; we use the correct "CHEQUE DATE" label.
  List<String> _buildOneTimeShareLines(OnetimeChargeItem it) {
    final c = widget.customer;
    final s = SettingsStore.instance;
    final lines = <String>[_sep];
    if (s.header1.isNotEmpty) lines..add(s.header1)..add(_sep);
    if (s.header2.isNotEmpty) lines..add(s.header2)..add(_sep);
    lines..add(' ONETIME CHARGES  ')..add(_sep)..add(_timestamp())..add(_sep);
    lines.add('CUSTOMER NAME   :${c.name}');
    lines.add('ADDRESS         :${c.address}');
    lines.add('MOBILE NO.      :${c.primaryMobileNumber}');
    lines.add('RECEIPT NO.     :${_na(it.receiptNo)}');
    lines.add('CHARGE TYPE     :${it.chargeTypeName}');
    lines.add('AMOUNT          :${it.amount}');
    lines.add('CREATED DATE    :${it.date}');
    lines.add('BANK            :${_na(it.bankName)}');
    lines.add('BRANCH          :${_na(it.branchName)}');
    lines.add('CHEQUE/DD NO.   :${_na(it.chequeDdNo)}');
    lines.add('CHEQUE DATE     :${_naDate(it.chequeDate)}');
    lines.add('REMARKS         :${_na(it.remarks)}');
    lines.add('PAID/UNPAID     :${_paidLabel(it)}');
    lines.add(_sep);
    if (s.footer1.isNotEmpty) lines..add(s.footer1)..add(_sep);
    if (s.footer2.isNotEmpty) lines..add(s.footer2)..add(_sep);
    return lines;
  }

  Future<void> _printOneTime(OnetimeChargeItem it) => launchThermalPrint(
        context: context,
        printerService: _printerService,
        buildLines: (fmt) => _buildOneTimePrintLines(it, fmt),
      );

  /// [originContext] is the tapped one-time card's context — iOS needs it to
  /// anchor the share sheet (see [shareOriginFrom]).
  Future<void> _shareOneTime(
      BuildContext originContext, OnetimeChargeItem it) async {
    try {
      // Inside the try: a failure here must surface as "Share failed", not die
      // as an unhandled async error (the callback discards this Future).
      final origin = shareOriginFrom(originContext);
      final lines = _buildOneTimeShareLines(it);
      final doc = pw.Document();
      final mono = pw.Font.courier();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final l in lines)
                pw.Text(l, style: pw.TextStyle(font: mono, fontSize: 10)),
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final safe = widget.customer.name
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final path = '${dir.path}/${safe.isEmpty ? 'onetime' : safe}.pdf';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)],
          subject: 'Onetime History of ${widget.customer.name}',
          sharePositionOrigin: origin);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  /// Edit — REUSES the existing create screen (OneTimeChargesScreen) in edit
  /// mode (Android igv_edit → Editonetime_Frag, same `sotc` endpoint). Refreshes
  /// the list on return so an edit is reflected.
  Future<void> _editOneTime(OnetimeChargeItem it) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OneTimeChargesScreen(customer: widget.customer, editItem: it),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware frame (page, title bar, Total strip, spinner, empty text).
  // Theme 1 keeps exactly the previous blue/white; the white cards are
  // unchanged.
  Widget _buildPage(BuildContext context) {
    final cust = widget.customer;
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _appBar(context, 'ONE TIME CHARGES HISTORY'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: t.appBarBg,
            child: Text(
              'Total Count - ${_items.length}',
              textAlign: TextAlign.right,
              style: TextStyle(color: t.appBarFg, fontSize: 13),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Theme 2 only: lift the white card off the light page.
              boxShadow: _lightCardShadow(t),
            ),
            child: Column(
              children: [
                _cRow('Customer Name', cust.name),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _cRow('Address', cust.address.isEmpty ? 'N/A' : cust.address),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _cRow('Mobile No.', cust.primaryMobileNumber.isEmpty ? 'N/A' : cust.primaryMobileNumber, isLast: true),
              ],
            ),
          ),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildBody(AppThemeConst t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No one time charges found' : _message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: t.isLight ? t.subtitleText : Colors.white70,
                fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _items.length,
      itemBuilder: (cardCtx, i) {
        final item = _items[i];
        return _OneTimeCard(
          record: _toCard(item),
          shareVisible: SessionService.instance.shareOption,
          onShare: (btnCtx) => _shareOneTime(btnCtx, item),
          onEdit: () => _editOneTime(item),
          onPrint: () => _printOneTime(item),
        );
      },
    );
  }
}

class _OneTimeCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool shareVisible;        // Android hides Share when share_option == "0"
  /// Receives the share button's own context — needed to anchor the iOS sheet.
  final void Function(BuildContext) onShare;
  final VoidCallback onEdit;
  final VoidCallback onPrint;
  const _OneTimeCard({
    required this.record,
    required this.shareVisible,
    required this.onShare,
    required this.onEdit,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          _r('Receipt No.', record['receiptNo']),
          _r('Bill No.', record['billNo']),
          _r('Charge Type', record['chargeType']),
          _r('Amount', record['amount']),
          _r('Created Date', record['createdDate']),
          _r('Bank', record['bank']),
          _r('Branch', record['branch']),
          _r('Cheque/DD No', record['chequeNo']),
          _r('Cheque Date', record['chequeDate']),
          _r('Remarks', record['remarks']),
          // Paid/Unpaid
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 130,
                  child: Text('Paid/Unpaid',
                      style: TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
                ),
                Icon(
                  record['paid'] == true ? Icons.check_box : Icons.check_box_outline_blank,
                  color: Colors.grey,
                  size: 22,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // Operations row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 130,
                  child: Text('Operations',
                      style: TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
                ),
                // Share — hidden when share_option == "0" (Android parity).
                if (shareVisible) ...[
                  // Builder so the tap handler gets THIS button's context — a
                  // ListView.builder itemBuilder context resolves to the
                  // enclosing sliver, which cannot anchor the iOS share sheet.
                  Builder(
                    builder: (btnCtx) => GestureDetector(
                      onTap: () => onShare(btnCtx),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1565C0),
                          shape: BoxShape.circle,
                        ),
                        child:
                            const Icon(Icons.share, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Edit — reuses OneTimeChargesScreen in edit mode (Android igv_edit).
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Color(0xFF0D47A1), size: 18),
                  ),
                ),
                // Print — thermal (Android igv_print → offline_report=9).
                // Leading spacer travels inside: Print is the last child, so
                // hiding it alone would leave a trailing 8px gap after Edit.
                if (AppConfig.bluetoothPrintingEnabled) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onPrint,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.print, color: Colors.red, size: 18),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _r(String label, String value) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Form-field decoration with a clearly visible border (the default outline was
/// too faint to see).
InputDecoration _otcField() {
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF6F8FC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: b(Colors.grey.shade500, 1),
    enabledBorder: b(Colors.grey.shade500, 1),
    focusedBorder: b(const Color(0xFF0D47A1), 1.5),
  );
}

/// Shared title bar of this file's screens (Act-Deact Report, One Time
/// Charges, Display One Time Charges, One Time Charges History) — follows
/// Theme 1 / Theme 2. Theme 1 keeps exactly the previous blue/white.
PreferredSizeWidget _appBar(BuildContext context, String title) {
  final t = AppThemeConst.of(context);
  final light = t.isLight;
  return AppBar(
    backgroundColor: light ? t.appBarBg : const Color(0xFF0D47A1),
    elevation: 0,
    centerTitle: true,
    toolbarHeight: 40, // compact, same as Customer / Payment Details
    leading: GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque, // whole leading slot stays tappable
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: light ? t.backBtnBg : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.arrow_back_ios_new,
            size: 16, color: light ? t.backBtnIcon : Colors.white),
      ),
    ),
    title: Text(title,
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: light ? t.appBarFg : Colors.white,
            letterSpacing: 1)),
  );
}

/// Theme 2 only: a soft shadow so a white card stands out on the light page.
/// null in Theme 1 (no change there).
List<BoxShadow>? _lightCardShadow(AppThemeConst t) => t.isLight
    ? [
        BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 14,
            offset: const Offset(0, 6)),
      ]
    : null;

Widget _cRow(String label, String value, {bool isLast = false}) {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
            ),
          ],
        ),
      ),
      if (!isLast) const Divider(height: 1, color: Color(0xFFE5E7EB)),
    ],
  );
}

class _FormRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE), fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

class _SimpleCard extends StatelessWidget {
  final Map<String, String> data;
  const _SimpleCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        // Theme 2 only: lift the white card off the light page.
        boxShadow: _lightCardShadow(AppThemeConst.of(context)),
      ),
      child: Column(
        children: List.generate(entries.length, (i) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(entries[i].key,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF5B7BAE))),
                    ),
                    Expanded(
                      child: Text(entries[i].value,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
                    ),
                  ],
                ),
              ),
              if (i < entries.length - 1)
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
            ],
          );
        }),
      ),
    );
  }
}