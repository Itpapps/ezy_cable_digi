import 'package:flutter/material.dart';
import '../../core/data/customer.dart';
import '../customer/data/act_deact_repository.dart';
import '../customer/data/onetime_charges_repository.dart';

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
  const OneTimeChargesScreen({super.key, required this.customer});

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
    _loadChargeTypes();
  }

  Future<void> _loadChargeTypes() async {
    final r = await OnetimeChargesRepository.instance
        .fetchChargeTypes(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _chargeTypes = r.types;
      _chargeType = r.types.isNotEmpty ? r.types.first : null;
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
      appBar: _appBar(context, 'ONE TIME CHARGES'),
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

  @override
  void initState() {
    super.initState();
    _load();
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
      itemBuilder: (_, i) => _OneTimeCard(record: _toCard(_items[i])),
    );
  }
}

class _OneTimeCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const _OneTimeCard({required this.record});

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
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1565C0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long, color: Color(0xFF0D47A1), size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {},
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