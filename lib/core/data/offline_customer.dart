/// Offline customer model — mirrors Android's Offline_Data_Model (offline_data_4 table).
/// Each field is stored as TEXT (matching Android SQLite) except id and flag (INTEGER).
class OfflineCustomer {
  final int? id;
  final String lcoCrfNo;
  final String accountNum;
  final String name;
  final String address;
  final String billAmount;
  final String taxAmount;
  final String pendingAmount;
  final String totalAmount;
  final String amount; // paid amount ("0.00" if unpaid)
  final String month;
  final String mobileNum;
  final String lastPaidAmount;
  final String lastPaidDate;
  final String businessName;
  final String customerId;
  final String crfNumber;
  final String lcoCustId;
  final String paymentFlag; // "000" = current month
  final int flag; // 0=downloaded, 1=paid, 2=synced
  final String paymentDate;
  final String syncPaymentDate;
  final String chequeNumber;
  final String bankName;
  final String branchName;
  final String insDate;
  final String sendSms; // "005"=no SMS, "015"=with SMS
  final String payMode; // "R"=cash, "B"=bank
  final String discountAmount;
  final String totalAfterDiscount;
  final String discountStartDate;
  final String discountEndDate;
  final String penaltyAmount;
  final String totalAfterPenalty;
  final String penaltyStartDate;
  final String penaltyEndDate;
  final String discountPenaltyFlag; // 4-char: "DM00","00PM","0000","DA00","00PA"

  OfflineCustomer({
    this.id,
    this.lcoCrfNo = '',
    this.accountNum = '',
    this.name = '',
    this.address = '',
    this.billAmount = '0.00',
    this.taxAmount = '0.00',
    this.pendingAmount = '0.00',
    this.totalAmount = '0.00',
    this.amount = '0.00',
    this.month = '',
    this.mobileNum = '',
    this.lastPaidAmount = '0.00',
    this.lastPaidDate = '',
    this.businessName = '',
    this.customerId = '',
    this.crfNumber = '',
    this.lcoCustId = '',
    this.paymentFlag = '',
    this.flag = 0,
    this.paymentDate = '',
    this.syncPaymentDate = '',
    this.chequeNumber = '',
    this.bankName = '',
    this.branchName = '',
    this.insDate = '',
    this.sendSms = '',
    this.payMode = '',
    this.discountAmount = '0.00',
    this.totalAfterDiscount = '0.00',
    this.discountStartDate = '',
    this.discountEndDate = '',
    this.penaltyAmount = '0.00',
    this.totalAfterPenalty = '0.00',
    this.penaltyStartDate = '',
    this.penaltyEndDate = '',
    this.discountPenaltyFlag = '0000',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'lcoCrfNo': lcoCrfNo,
      'accountNum': accountNum,
      'name': name,
      'address': address,
      'billAmount': billAmount,
      'taxAmount': taxAmount,
      'pendingAmount': pendingAmount,
      'totalAmount': totalAmount,
      'amount': amount,
      'month': month,
      'mobileNum': mobileNum,
      'lastPaidAmount': lastPaidAmount,
      'lastPaidDate': lastPaidDate,
      'businessName': businessName,
      'customerId': customerId,
      'crfNumber': crfNumber,
      'lcoCustId': lcoCustId,
      'paymentFlag': paymentFlag,
      'flag': flag,
      'paymentDate': paymentDate,
      'syncPaymentDate': syncPaymentDate,
      'chequeNumber': chequeNumber,
      'bankName': bankName,
      'branchName': branchName,
      'insDate': insDate,
      'sendSms': sendSms,
      'payMode': payMode,
      'discountAmount': discountAmount,
      'totalAfterDiscount': totalAfterDiscount,
      'discountStartDate': discountStartDate,
      'discountEndDate': discountEndDate,
      'penaltyAmount': penaltyAmount,
      'totalAfterPenalty': totalAfterPenalty,
      'penaltyStartDate': penaltyStartDate,
      'penaltyEndDate': penaltyEndDate,
      'discountPenaltyFlag': discountPenaltyFlag,
    };
  }

  factory OfflineCustomer.fromMap(Map<String, dynamic> m) {
    return OfflineCustomer(
      id: m['id'] as int?,
      lcoCrfNo: m['lcoCrfNo'] ?? '',
      accountNum: m['accountNum'] ?? '',
      name: m['name'] ?? '',
      address: m['address'] ?? '',
      billAmount: m['billAmount'] ?? '0.00',
      taxAmount: m['taxAmount'] ?? '0.00',
      pendingAmount: m['pendingAmount'] ?? '0.00',
      totalAmount: m['totalAmount'] ?? '0.00',
      amount: m['amount'] ?? '0.00',
      month: m['month'] ?? '',
      mobileNum: m['mobileNum'] ?? '',
      lastPaidAmount: m['lastPaidAmount'] ?? '0.00',
      lastPaidDate: m['lastPaidDate'] ?? '',
      businessName: m['businessName'] ?? '',
      customerId: m['customerId'] ?? '',
      crfNumber: m['crfNumber'] ?? '',
      lcoCustId: m['lcoCustId'] ?? '',
      paymentFlag: m['paymentFlag'] ?? '',
      flag: m['flag'] ?? 0,
      paymentDate: m['paymentDate'] ?? '',
      syncPaymentDate: m['syncPaymentDate'] ?? '',
      chequeNumber: m['chequeNumber'] ?? '',
      bankName: m['bankName'] ?? '',
      branchName: m['branchName'] ?? '',
      insDate: m['insDate'] ?? '',
      sendSms: m['sendSms'] ?? '',
      payMode: m['payMode'] ?? '',
      discountAmount: m['discountAmount'] ?? '0.00',
      totalAfterDiscount: m['totalAfterDiscount'] ?? '0.00',
      discountStartDate: m['discountStartDate'] ?? '',
      discountEndDate: m['discountEndDate'] ?? '',
      penaltyAmount: m['penaltyAmount'] ?? '0.00',
      totalAfterPenalty: m['totalAfterPenalty'] ?? '0.00',
      penaltyStartDate: m['penaltyStartDate'] ?? '',
      penaltyEndDate: m['penaltyEndDate'] ?? '',
      discountPenaltyFlag: m['discountPenaltyFlag'] ?? '0000',
    );
  }

  OfflineCustomer copyWith({
    int? id,
    String? lcoCrfNo,
    String? accountNum,
    String? name,
    String? address,
    String? billAmount,
    String? taxAmount,
    String? pendingAmount,
    String? totalAmount,
    String? amount,
    String? month,
    String? mobileNum,
    String? lastPaidAmount,
    String? lastPaidDate,
    String? businessName,
    String? customerId,
    String? crfNumber,
    String? lcoCustId,
    String? paymentFlag,
    int? flag,
    String? paymentDate,
    String? syncPaymentDate,
    String? chequeNumber,
    String? bankName,
    String? branchName,
    String? insDate,
    String? sendSms,
    String? payMode,
    String? discountAmount,
    String? totalAfterDiscount,
    String? discountStartDate,
    String? discountEndDate,
    String? penaltyAmount,
    String? totalAfterPenalty,
    String? penaltyStartDate,
    String? penaltyEndDate,
    String? discountPenaltyFlag,
  }) {
    return OfflineCustomer(
      id: id ?? this.id,
      lcoCrfNo: lcoCrfNo ?? this.lcoCrfNo,
      accountNum: accountNum ?? this.accountNum,
      name: name ?? this.name,
      address: address ?? this.address,
      billAmount: billAmount ?? this.billAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      amount: amount ?? this.amount,
      month: month ?? this.month,
      mobileNum: mobileNum ?? this.mobileNum,
      lastPaidAmount: lastPaidAmount ?? this.lastPaidAmount,
      lastPaidDate: lastPaidDate ?? this.lastPaidDate,
      businessName: businessName ?? this.businessName,
      customerId: customerId ?? this.customerId,
      crfNumber: crfNumber ?? this.crfNumber,
      lcoCustId: lcoCustId ?? this.lcoCustId,
      paymentFlag: paymentFlag ?? this.paymentFlag,
      flag: flag ?? this.flag,
      paymentDate: paymentDate ?? this.paymentDate,
      syncPaymentDate: syncPaymentDate ?? this.syncPaymentDate,
      chequeNumber: chequeNumber ?? this.chequeNumber,
      bankName: bankName ?? this.bankName,
      branchName: branchName ?? this.branchName,
      insDate: insDate ?? this.insDate,
      sendSms: sendSms ?? this.sendSms,
      payMode: payMode ?? this.payMode,
      discountAmount: discountAmount ?? this.discountAmount,
      totalAfterDiscount: totalAfterDiscount ?? this.totalAfterDiscount,
      discountStartDate: discountStartDate ?? this.discountStartDate,
      discountEndDate: discountEndDate ?? this.discountEndDate,
      penaltyAmount: penaltyAmount ?? this.penaltyAmount,
      totalAfterPenalty: totalAfterPenalty ?? this.totalAfterPenalty,
      penaltyStartDate: penaltyStartDate ?? this.penaltyStartDate,
      penaltyEndDate: penaltyEndDate ?? this.penaltyEndDate,
      discountPenaltyFlag: discountPenaltyFlag ?? this.discountPenaltyFlag,
    );
  }
}
