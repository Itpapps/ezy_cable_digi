import 'package:flutter/material.dart';

import '../../core/data/customer.dart';
import '../../core/data/offline_customer.dart';
import '../../core/data/payment.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/offline_data_service.dart';
import '../payment/receipt_preview_screen.dart';
import 'widgets/offline_payment_dialog.dart';

/// Legacy flow for old Customer model (search results that are in the old
/// customers table). Keeps backward compat for any screen still using Customer.
Future<void> openOfflinePaymentFlow(
  BuildContext context,
  Customer customer,
) async {
  final db = DatabaseHelper();
  final initial =
      customer.amountPayable.replaceAll(RegExp(r'[^0-9.]'), '');
  final result = await showDialog<OfflinePaymentResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OfflinePaymentDialog(
      customerName: customer.name,
      initialAmount: initial.isEmpty ? '0' : initial,
    ),
  );
  if (result == null || !context.mounted) return;

  final tid = await db.generateTransactionId();
  final payment = Payment(
    customerId: customer.lcoCustomerId,
    customerName: customer.name,
    customerMobile: customer.primaryMobileNumber,
    amount: result.amount,
    paymentMethod: result.method,
    paymentDate: DateTime.now(),
    transactionId: tid,
    status: 'completed',
    smsSent: result.sendSms,
    chequeNo: result.chequeNo,
    bankName: result.bankName,
    branch: result.branch,
    instrumentDate: result.instrumentDate,
    synced: false,
  );

  final id = await db.insertPayment(payment);
  final saved = Payment(
    id: id,
    customerId: payment.customerId,
    customerName: payment.customerName,
    customerMobile: payment.customerMobile,
    amount: payment.amount,
    paymentMethod: payment.paymentMethod,
    paymentDate: payment.paymentDate,
    transactionId: payment.transactionId,
    status: payment.status,
    smsSent: payment.smsSent,
    chequeNo: payment.chequeNo,
    bankName: payment.bankName,
    branch: payment.branch,
    instrumentDate: payment.instrumentDate,
    synced: false,
  );

  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ReceiptPreviewScreen(
        customer: customer,
        payment: saved,
        fromOfflineCollection: true,
      ),
    ),
  );
}

/// New offline payment flow for OfflineCustomer model from the offline_customers table.
Future<void> openOfflinePaymentFlowForOfflineCustomer(
  BuildContext context,
  OfflineCustomer customer,
) async {
  final result = await showDialog<OfflinePaymentResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OfflinePaymentDialog(
      customerName: customer.name,
      initialAmount: customer.totalAmount,
      discountPenaltyFlag: customer.discountPenaltyFlag,
      discountAmount: customer.discountAmount,
      penaltyAmount: customer.penaltyAmount,
      totalAfterDiscount: customer.totalAfterDiscount,
      totalAfterPenalty: customer.totalAfterPenalty,
      discountStartDate: customer.discountStartDate,
      discountEndDate: customer.discountEndDate,
      penaltyStartDate: customer.penaltyStartDate,
      penaltyEndDate: customer.penaltyEndDate,
    ),
  );
  if (result == null || !context.mounted) return;

  try {
    await OfflineDataService.instance.commitPayment(
      customer: customer,
      amount: result.amount,
      payMode: result.method == 'cash' ? 'R' : 'B',
      sendSms: result.sendSms,
      chequeNumber: result.chequeNo,
      bankName: result.bankName,
      branchName: result.branch,
      insDate: result.instrumentDate,
      discountPenaltyFlag: result.discountPenaltyFlag,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Payment of ₹${result.amount.toStringAsFixed(2)} recorded for ${customer.name}'),
        backgroundColor: Colors.green,
      ),
    );
  } on OfflineDataException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
    );
  }
}
