import 'package:flutter/material.dart';

import '../../core/data/customer.dart';
import '../../core/database/database_helper.dart';

class PaymentConfirmationDialog extends StatefulWidget {
  final Customer customer;
  final double amount;          // STB / cable leg
  final double broadbandAmount; // broadband leg (0 = none)
  final String paymentMethod;
  final double lastPaidAmount;  // Android last_paid_amount (from GPA) — the REAL
                                // last paid, NOT the pending/bill amount.

  const PaymentConfirmationDialog({
    super.key,
    required this.customer,
    required this.amount,
    this.broadbandAmount = 0,
    required this.paymentMethod,
    this.lastPaidAmount = 0,
  });

  @override
  State<PaymentConfirmationDialog> createState() => _PaymentConfirmationDialogState();
}

class _PaymentConfirmationDialogState extends State<PaymentConfirmationDialog> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  int _currentMonthPayments = 0;
  int _currentMonthAdjustments = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentStats();
  }

  Future<void> _loadPaymentStats() async {
    try {
      final paymentCount = await _dbHelper.getCurrentMonthPaymentCount(widget.customer.lcoCustomerId);
      if (mounted) {
        setState(() {
          _currentMonthPayments = paymentCount;
          _currentMonthAdjustments = 0; // You can implement adjustment logic if needed
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Title ──
            const Text(
              'Payment Confirmation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // ── Info Rows ──
              // Android last_paid_amount (GPA) — NOT the pending/bill amount.
              _infoRow('Last Paid Amount', '₹${widget.lastPaidAmount.toStringAsFixed(2)}'),
              _infoRow('Last Paid Date', widget.customer.lastPaidDate.isEmpty ? 'Code=0' : widget.customer.lastPaidDate),
              _infoRow('Current Month\nPayments Count', _currentMonthPayments.toString()),
              _infoRow('Current Month\nAdjustments Count', _currentMonthAdjustments.toString()),
              
              const SizedBox(height: 20),

              // ── Confirmation Prompt (Android showDialog :2823-2834) ──
              Text(
                _confirmationMessage(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC60000), // Red
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2), // Sharp corners
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('CANCEL',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF333399), // Navy Blue
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2), // Sharp corners
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('CONFIRM',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Mirrors Android `CustomerMgmt_MakePayment_Fragment.showDialog` :2823-2834.
  String _confirmationMessage() {
    final stb = widget.amount;
    final bb = widget.broadbandAmount;
    String money(double v) => '₹${v.toStringAsFixed(1)}';
    if (bb > 0) {
      // BroadBand-only (customer_type == '1') vs combined (STB & BroadBand).
      if (widget.customer.customerType.trim() == '1') {
        return 'Are you sure you want to continue BroadBand Payment ${money(bb)}?';
      }
      return 'Are you sure you want to continue Digital TV Payment ${money(stb)}\n'
          'BroadBand Payment ${money(bb)}\n'
          'Total Paid Amount ${money(stb + bb)}?';
    }
    return 'Are you sure you want to continue Digital TV\nPayment ${money(stb)}?';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
