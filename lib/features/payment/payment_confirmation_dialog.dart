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
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
            const SizedBox(height: 14),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // ── Info Rows ──
              // Android last_paid_amount (GPA) — NOT the pending/bill amount.
              _infoRow('Last Paid Amount', '₹${widget.lastPaidAmount.toStringAsFixed(2)}'),
              _infoRow('Last Paid Date', widget.customer.lastPaidDate.isEmpty ? 'Code=0' : widget.customer.lastPaidDate),
              _infoRow('Current Month\nPayments Count', _currentMonthPayments.toString()),
              _infoRow('Current Month\nAdjustments Count', _currentMonthAdjustments.toString()),
              
              const SizedBox(height: 14),

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

              const SizedBox(height: 12),

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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

  // Decorative row icon chosen by the LABEL only — presentation metadata; does
  // NOT touch the label, value, or any logic. Unknown labels fall back safely.
  IconData _confIcon(String label) {
    if (label.contains('Amount')) return Icons.payments_outlined;
    if (label.contains('Date')) return Icons.event_outlined;
    if (label.contains('Payments')) return Icons.receipt_long_outlined;
    if (label.contains('Adjustments')) return Icons.tune_outlined;
    return Icons.info_outline;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Decorative leading icon chip — presentation only (no onTap, no data).
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF333399).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_confIcon(label), size: 15, color: const Color(0xFF333399)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
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
