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
  final legacyDue =
      double.tryParse(customer.totalDue.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ReceiptPreviewScreen(
        customer: customer,
        payment: saved,
        fromOfflineCollection: true,
        billAmount: legacyDue,
        dueAmount: legacyDue,
        outAmount: legacyDue - result.amount,
        stbPaidAmount: result.amount,
      ),
    ),
  );
}

/// B-B4 / Android Offline_searchItemList_Fragment :137-143 and
/// Offline_unPaidCustomer_Fragment :178-184 & :230-236: the payment popup
/// opens only when the customer's total_amount is above 0.00; otherwise
/// "Due amount is 0.00 or less". An unparsable total does nothing (Android's
/// Double.parseDouble throws into its catch, so no popup opens).
bool offlineDueAllowsPayment(BuildContext context, OfflineCustomer customer) {
  final total = double.tryParse(customer.totalAmount.trim());
  if (total == null) return false;
  if (total <= 0.00) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Due amount is 0.00 or less')),
    );
    return false;
  }
  return true;
}

/// New offline payment flow for OfflineCustomer model from the offline_customers table.
Future<void> openOfflinePaymentFlowForOfflineCustomer(
  BuildContext context,
  OfflineCustomer customer,
) async {
  if (!offlineDueAllowsPayment(context, customer)) return;
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
    final updated = await OfflineDataService.instance.commitPayment(
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
    // Android parity: after an offline payment, show the (printable) receipt.
    await showOfflineReceipt(context, updated,
        paid: result.amount, sendSms: result.sendSms);
  } on OfflineDataException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message), backgroundColor: Colors.red),
    );
  }
}

/// Show the printable offline receipt after a committed offline payment.
/// Shared by BOTH offline entry points (offline search + offline unpaid list)
/// so the receipt + Bluetooth print behave identically (Android parity).
Future<void> showOfflineReceipt(
  BuildContext context,
  OfflineCustomer updated, {
  required double paid,
  required bool sendSms,
}) async {
  final totalDue = _offlineTotalDue(updated);
  final amountPaid = double.tryParse(updated.amount) ?? paid;
  final payment = Payment(
    customerId:
        updated.lcoCustId.isEmpty ? updated.customerId : updated.lcoCustId,
    customerName: updated.name,
    customerMobile: updated.mobileNum,
    amount: amountPaid,
    paymentMethod: updated.payMode == 'B' ? 'bank' : 'cash',
    paymentDate: DateTime.now(),
    transactionId: updated.syncPaymentDate, // offline receipt no (tstamp+custId)
    status: 'completed',
    smsSent: sendSms,
    chequeNo: updated.chequeNumber,
    bankName: updated.bankName,
    branch: updated.branchName,
    instrumentDate: updated.insDate,
    synced: false,
  );
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => ReceiptPreviewScreen(
        customer: _customerFromOffline(updated),
        payment: payment,
        fromOfflineCollection: true,
        billAmount: double.tryParse(updated.billAmount) ?? 0,
        dueAmount: totalDue,
        outAmount: totalDue - amountPaid,
        stbPaidAmount: amountPaid,
      ),
    ),
  );
}

/// Total due for an offline customer — mirrors `_calculateOutstanding`
/// (after-discount / after-penalty / plain total), used for the receipt.
double _offlineTotalDue(OfflineCustomer c) {
  if (c.discountPenaltyFlag.contains('D')) {
    return double.tryParse(c.totalAfterDiscount) ?? 0;
  }
  if (c.discountPenaltyFlag.contains('P')) {
    return double.tryParse(c.totalAfterPenalty) ?? 0;
  }
  return double.tryParse(c.totalAmount) ?? 0;
}

/// Map an [OfflineCustomer] to the [Customer] the receipt screen expects.
Customer _customerFromOffline(OfflineCustomer c) => Customer(
      // Receipt field mapping (receipt_preview_screen after the account-no/LCO
      // fix): ACCOUNT NUMBER reads lcoCustomerId, LCO CUST ID reads
      // altCustomNumber. Offline: account number = accountNum, LCO id = lcoCustId.
      altCustomerId: c.accountNum,
      altCustomNumber: c.lcoCustId.isEmpty ? c.customerId : c.lcoCustId,
      name: c.name,
      primaryMobileNumber: c.mobileNum,
      lcoCustomerId: c.accountNum,
      crfNumber: c.crfNumber,
      serialNumber: '',
      vcNumber: '',
      nickName: '',
      secondaryMobileNumber: '',
      pendingAmount: c.pendingAmount,
      lastPaidDate: c.lastPaidDate,
      customerType: '', // offline = STB
      address: c.address,
      groupName: '',
      areaName: '',
      totalDue: c.totalAmount,
      amountPayable: c.totalAmount,
      billMonth: c.month,
      boxNumber: '',
    );
