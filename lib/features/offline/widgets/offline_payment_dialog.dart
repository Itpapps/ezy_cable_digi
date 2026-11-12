import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/offline_mode_service.dart';

class OfflinePaymentResult {
  final double amount;
  final String method; // 'cash' or 'bank'
  final bool sendSms;
  final String chequeNo;
  final String bankName;
  final String branch;
  final String instrumentDate;
  final String discountPenaltyFlag; // "0000", "DM00", "DA00", "00PM", "00PA"

  OfflinePaymentResult({
    required this.amount,
    required this.method,
    required this.sendSms,
    required this.chequeNo,
    required this.bankName,
    required this.branch,
    required this.instrumentDate,
    this.discountPenaltyFlag = '0000',
  });
}

/// Offline payment dialog — Android parity (alertChangeAmountDialog).
/// Supports cash/bank, SMS toggle, discount/penalty display, partial pay guard.
class OfflinePaymentDialog extends StatefulWidget {
  final String customerName;
  final String initialAmount;
  final bool restrictPartial;
  final String discountPenaltyFlag;
  final String discountAmount;
  final String penaltyAmount;
  final String totalAfterDiscount;
  final String totalAfterPenalty;
  final String discountStartDate;
  final String discountEndDate;
  final String penaltyStartDate;
  final String penaltyEndDate;

  const OfflinePaymentDialog({
    super.key,
    required this.customerName,
    required this.initialAmount,
    this.restrictPartial = false,
    this.discountPenaltyFlag = '0000',
    this.discountAmount = '0.00',
    this.penaltyAmount = '0.00',
    this.totalAfterDiscount = '0.00',
    this.totalAfterPenalty = '0.00',
    this.discountStartDate = '',
    this.discountEndDate = '',
    this.penaltyStartDate = '',
    this.penaltyEndDate = '',
  });

  @override
  State<OfflinePaymentDialog> createState() => _OfflinePaymentDialogState();
}

class _OfflinePaymentDialogState extends State<OfflinePaymentDialog> {
  late final TextEditingController _amountCtrl;
  final _chequeCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  String _method = 'cash';
  bool _sendSms = false;
  DateTime? _instrumentDate;
  bool _discountApplied = false;
  bool _penaltyApplied = false;

  // B-B2: Android Offline_Activity.partial_pay (saved at the last online login).
  late bool _restrictPartial = widget.restrictPartial;

  @override
  void initState() {
    super.initState();
    _resolveDiscountPenalty();
    _amountCtrl = TextEditingController(text: _getDisplayAmount());
    OfflineModeService.instance.partialPay.then((v) {
      if (v == 1) _restrictPartial = true;
    });
  }

  void _resolveDiscountPenalty() {
    final now = DateTime.now();
    final flag = widget.discountPenaltyFlag;

    // Check discount eligibility (first 2 chars "DM" or "DA")
    if (flag.length >= 2 && (flag.substring(0, 2) == 'DM' || flag.substring(0, 2) == 'DA')) {
      if (_isDateInRange(widget.discountStartDate, widget.discountEndDate, now)) {
        _discountApplied = true;
      }
    }
    // Check penalty eligibility (last 2 chars "PM" or "PA")
    if (flag.length >= 4 && (flag.substring(2, 4) == 'PM' || flag.substring(2, 4) == 'PA')) {
      if (_isDateInRange(widget.penaltyStartDate, widget.penaltyEndDate, now)) {
        _penaltyApplied = true;
      }
    }
    // Discount overrides penalty
    if (_discountApplied) _penaltyApplied = false;
  }

  bool _isDateInRange(String start, String end, DateTime now) {
    if (start.isEmpty || end.isEmpty) return false;
    try {
      final fmt = DateFormat('dd-MM-yyyy');
      final s = fmt.parse(start);
      final e = fmt.parse(end);
      return !now.isBefore(s) && !now.isAfter(e);
    } catch (_) {
      return false;
    }
  }

  String _getDisplayAmount() {
    if (_discountApplied) return widget.totalAfterDiscount;
    if (_penaltyApplied) return widget.totalAfterPenalty;
    return widget.initialAmount;
  }

  String _computeDpFlag() {
    if (_discountApplied) {
      return '${widget.discountPenaltyFlag.substring(0, 2)}00';
    }
    if (_penaltyApplied) {
      return '00${widget.discountPenaltyFlag.substring(2, 4)}';
    }
    return '0000';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _chequeCtrl.dispose();
    _bankCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  /// A-B6 / Android Offline_searchItemList_Fragment :385-393, :885-925 (same in
  /// Offline_unPaidCustomer_Fragment): the picker opens only after a Cheque/DD
  /// number is entered (otherwise the date goes back to "Select"); a date
  /// before today shows "Cheque Date Error!" and keeps the previous date.
  Future<void> _pickDate() async {
    if (_chequeCtrl.text.isEmpty) {
      setState(() => _instrumentDate = null);
      return;
    }
    final d = await showDatePicker(
      context: context,
      initialDate: _instrumentDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final now = DateTime.now();
    if (d.isBefore(DateTime(now.year, now.month, now.day))) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cheque Date Error!'),
          content: const Text('Cheque date should not be before today.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _instrumentDate = d);
  }

  void _submit() {
    // B-B4 / Android Offline_searchItemList_Fragment :444-447 & :521-523,
    // Offline_unPaidCustomer_Fragment :581-584 & :656-658: empty, "." or an
    // amount below 1 is blocked. Android's text has a full stop for Cash and
    // none for Bank/Cheque.
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_method == 'bank'
              ? 'Amount cannot be 0.00 or empty'
              : 'Amount cannot be 0.00 or empty.'),
        ),
      );
      return;
    }
    // B-B2 / Android Offline_searchItemList_Fragment :451 & :526,
    // Offline_unPaidCustomer_Fragment :586 & :660: with partial_pay == 1 the
    // amount must be >= the customer's total_amount (the downloaded total,
    // not the discounted one — Android compares with getTotal_amount()).
    if (_restrictPartial) {
      final total = double.tryParse(widget.initialAmount) ?? 0;
      if (amt < total) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Invalid Amount!'),
            content: const Text('Entered payable amount should be greater '
                'than or equal to your pending amount'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }
    if (_method == 'bank') {
      if (_chequeCtrl.text.trim().isEmpty ||
          _bankCtrl.text.trim().isEmpty ||
          _branchCtrl.text.trim().isEmpty ||
          _instrumentDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill all bank fields')),
        );
        return;
      }
    }
    Navigator.pop(
      context,
      OfflinePaymentResult(
        amount: amt,
        method: _method,
        sendSms: _sendSms,
        chequeNo: _chequeCtrl.text.trim(),
        bankName: _bankCtrl.text.trim(),
        branch: _branchCtrl.text.trim(),
        instrumentDate: _instrumentDate != null
            ? DateFormat('ddMMyyyy').format(_instrumentDate!)
            : '',
        discountPenaltyFlag: _computeDpFlag(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment: ${widget.customerName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Please select an option and enter amount below',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (_discountApplied) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Discount: ₹${widget.discountAmount} applied\n'
                  'Amount after discount: ₹${widget.totalAfterDiscount}',
                  style: TextStyle(color: Colors.green.shade800, fontSize: 12),
                ),
              ),
            ],
            if (_penaltyApplied) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Penalty: ₹${widget.penaltyAmount} added\n'
                  'Amount after penalty: ₹${widget.totalAfterPenalty}',
                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('CASH'),
                    value: 'cash',
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v ?? 'cash'),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('BANK'),
                    value: 'bank',
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v ?? 'bank'),
                  ),
                ),
              ],
            ),
            const Divider(),
            const Text('Please enter amount below:'),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: UnderlineInputBorder(),
              ),
            ),
            if (_method == 'bank') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _chequeCtrl,
                decoration: const InputDecoration(
                  labelText: '* Cheque/DD No',
                ),
              ),
              TextField(
                controller: _bankCtrl,
                decoration: const InputDecoration(
                  labelText: '* Bank Name',
                ),
              ),
              TextField(
                controller: _branchCtrl,
                decoration: const InputDecoration(
                  labelText: '* Branch',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('* Instrument Date: '),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _instrumentDate != null
                          ? DateFormat('dd-MM-yyyy').format(_instrumentDate!)
                          : 'SELECT',
                    ),
                  ),
                ],
              ),
            ],
            CheckboxListTile(
              value: _sendSms,
              onChanged: (v) => setState(() => _sendSms = v ?? false),
              title: const Text('Send SMS'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text(
                    'DONE AND PAY',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
