import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/customer.dart';
import '../../core/utils/share_origin.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/settings_store.dart';
import '../customer/data/act_deact_repository.dart';
import '../customer/data/onetime_charges_repository.dart';
import '../payment/printer_launcher.dart';

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
  Widget build(BuildContext context) {
    final customer = widget.customer;
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _appBar(context, 'ACT-DEACT REPORT'),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No act/deact records found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
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
  DateTime _instrumentDate = DateTime.now();
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
      // Instrument (cheque) leg was used if any bank/cheque detail exists.
      _instrument = e.chequeDdNo.trim().isNotEmpty ||
          e.bankName.trim().isNotEmpty ||
          e.branchName.trim().isNotEmpty;
      _createdDate = _parseDate(e.date, _createdDate);
      _instrumentDate = _parseDate(e.chequeDate, _instrumentDate);
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

  Future<void> _pickDate({required bool instrument}) async {
    final base = instrument ? _instrumentDate : _createdDate;
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
    if (_amountCtrl.text.trim().isEmpty ||
        (double.tryParse(_amountCtrl.text.trim()) ?? 0) <= 0) {
      _snack('Please enter a valid amount');
      return;
    }
    // Android validates ONLY the amount — cheque/bank/branch are optional.
    setState(() => _saving = true);
    final r = await OnetimeChargesRepository.instance.save(
      customerId: widget.customer.lcoCustomerId,
      chargeType: _chargeType!.id,
      amount: _amountCtrl.text.trim(),
      chqDd: _instrument ? _chequeCtrl.text.trim() : '',
      bank: _instrument ? _bankCtrl.text.trim() : '',
      branch: _instrument ? _branchCtrl.text.trim() : '',
      chqDdDate: _instrument ? _ymd(_instrumentDate) : '',
      remarks: _remarksCtrl.text.trim(),
      createdDate: _ymd(_createdDate),
      checkPaidUnpaid: _instrument ? 1 : 2, // Android: 1 cheque · 2 cash
      // Edit mode (Android Editonetime_Frag): real id + receipt_no → ot_type=1.
      onetimeChargeId: widget.editItem?.onetimeChargeId ?? '0',
      receiptNo: widget.editItem?.receiptNo ?? '',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.isSuccess) {
      _snack(r.statusMessage.isEmpty ? 'Saved Successfully' : r.statusMessage,
          error: false);
      Navigator.pop(context);
    } else {
      _snack(r.statusMessage.isEmpty ? 'Save failed' : r.statusMessage);
    }
  }

  String get _fmtDate => _ymd(_createdDate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _appBar(context,
          widget.editItem == null ? 'ONE TIME CHARGES' : 'EDIT ONE TIME CHARGES'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
                            child: Text(_ymd(_instrumentDate),
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
  Widget build(BuildContext context) {
    final cust = widget.customer;
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _appBar(context, 'ONE TIME CHARGES HISTORY'),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              'Total Count - ${_items.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No one time charges found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
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
                const SizedBox(width: 8),
                // Print — thermal (Android igv_print → offline_report=9).
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

PreferredSizeWidget _appBar(BuildContext context, String title) {
  return AppBar(
    backgroundColor: const Color(0xFF0D47A1),
    elevation: 0,
    centerTitle: true,
    leading: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
      ),
    ),
    title: Text(title,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
  );
}

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