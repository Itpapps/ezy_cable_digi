class Customer {
  final int? id;
  final String altCustomerId;
  final String name;
  final String primaryMobileNumber;
  final String lcoCustomerId;
  final String crfNumber;
  final String serialNumber;
  final String vcNumber;
  final String nickName;
  final String secondaryMobileNumber;
  final String pendingAmount;
  final String lastPaidDate;
  final String customerType;
  final String broadbandUserId; // broadband account id (empty = STB-only)
  // Android per-customer grid-state flags (searchCustomer response). Default 0.
  // is_show → Renew visibility; tmp_activation → Temporary Activation state;
  // unpaid_customer_activation → Unpaid Customer Activation state.
  final int isShow;
  final int tmpActivation;
  final int unpaidAct;
  final String address;
  final String groupName;
  final String areaName;
  final String totalDue;
  final String amountPayable;
  final String billMonth;
  final String boxNumber;
  final double? latitude;
  final double? longitude;

  Customer({
    this.id,
    required this.altCustomerId,
    required this.name,
    required this.primaryMobileNumber,
    required this.lcoCustomerId,
    required this.crfNumber,
    required this.serialNumber,
    required this.vcNumber,
    required this.nickName,
    required this.secondaryMobileNumber,
    required this.pendingAmount,
    required this.lastPaidDate,
    required this.customerType,
    this.broadbandUserId = '',
    this.isShow = 0,
    this.tmpActivation = 0,
    this.unpaidAct = 0,
    required this.address,
    required this.groupName,
    required this.areaName,
    required this.totalDue,
    required this.amountPayable,
    required this.billMonth,
    required this.boxNumber,
    this.latitude,
    this.longitude,
  });

  /// Android-style label for the raw `customer_type` ("0"/"1"/"2").
  /// Matches the existing app: STB / BroadBand / STB & BroadBand.
  String get customerTypeLabel {
    switch (customerType.trim()) {
      case '0':
        return 'STB';
      case '1':
        return 'BroadBand';
      case '2':
        return 'STB & BroadBand';
      default:
        return customerType; // already a label, or unknown — show as-is
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'altCustomerId': altCustomerId,
      'name': name,
      'primaryMobileNumber': primaryMobileNumber,
      'lcoCustomerId': lcoCustomerId,
      'crfNumber': crfNumber,
      'serialNumber': serialNumber,
      'vcNumber': vcNumber,
      'nickName': nickName,
      'secondaryMobileNumber': secondaryMobileNumber,
      'pendingAmount': pendingAmount,
      'lastPaidDate': lastPaidDate,
      'customerType': customerType,
      'broadbandUserId': broadbandUserId,
      'isShow': isShow,
      'tmpActivation': tmpActivation,
      'unpaidAct': unpaidAct,
      'address': address,
      'groupName': groupName,
      'areaName': areaName,
      'totalDue': totalDue,
      'amountPayable': amountPayable,
      'billMonth': billMonth,
      'boxNumber': boxNumber,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      altCustomerId: map['altCustomerId'] ?? '',
      name: map['name'] ?? '',
      primaryMobileNumber: map['primaryMobileNumber'] ?? '',
      lcoCustomerId: map['lcoCustomerId'] ?? '',
      crfNumber: map['crfNumber'] ?? '',
      serialNumber: map['serialNumber'] ?? '',
      vcNumber: map['vcNumber'] ?? '',
      nickName: map['nickName'] ?? '',
      secondaryMobileNumber: map['secondaryMobileNumber'] ?? '',
      pendingAmount: map['pendingAmount'] ?? '₹0',
      lastPaidDate: map['lastPaidDate'] ?? '',
      customerType: map['customerType'] ?? '',
      broadbandUserId: map['broadbandUserId'] ?? '',
      isShow: (map['isShow'] as num?)?.toInt() ?? 0,
      tmpActivation: (map['tmpActivation'] as num?)?.toInt() ?? 0,
      unpaidAct: (map['unpaidAct'] as num?)?.toInt() ?? 0,
      address: map['address'] ?? '',
      groupName: map['groupName'] ?? '',
      areaName: map['areaName'] ?? '',
      totalDue: map['totalDue'] ?? '₹0',
      amountPayable: map['amountPayable'] ?? '₹0',
      billMonth: map['billMonth'] ?? '',
      boxNumber: map['boxNumber'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  /// From the `unpaidCustomers` (uc) API response item.
  /// Field names per MagikDigi Android (Unpaid_Fragment / UnpaidCustomerResult).
  factory Customer.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    final fullName =
        [s('first_name'), s('last_name')].where((p) => p.isNotEmpty).join(' ');
    final amount = s('amount');
    final total = s('total');
    return Customer(
      altCustomerId: s('alt_cust_id'),
      name: fullName,
      primaryMobileNumber: s('mobile_no'),
      lcoCustomerId: s('customer_id'),
      crfNumber: s('crfno'),
      serialNumber: '',
      vcNumber: s('vc_number'),
      nickName: s('nickname'),
      secondaryMobileNumber: '',
      pendingAmount: total.isEmpty ? '₹0' : '₹$total',
      lastPaidDate: s('paid_on'),
      customerType: s('customer_type'),
      broadbandUserId: s('broadband_user_id'),
      isShow: int.tryParse(s('is_show')) ?? 0,
      tmpActivation: int.tryParse(s('tmp_activation')) ?? 0,
      unpaidAct: int.tryParse(s('unpaid_customer_activation')) ?? 0,
      address: s('address1'),
      groupName: '',
      areaName: '',
      totalDue: total.isEmpty ? '₹0' : '₹$total',
      amountPayable: amount.isEmpty ? '₹0' : '₹$amount',
      billMonth: s('bill_month'),
      boxNumber: s('box_number'),
    );
  }

  Customer copyWith({
    int? id,
    String? altCustomerId,
    String? name,
    String? primaryMobileNumber,
    String? lcoCustomerId,
    String? crfNumber,
    String? serialNumber,
    String? vcNumber,
    String? nickName,
    String? secondaryMobileNumber,
    String? pendingAmount,
    String? lastPaidDate,
    String? customerType,
    String? broadbandUserId,
    int? isShow,
    int? tmpActivation,
    int? unpaidAct,
    String? address,
    String? groupName,
    String? areaName,
    String? totalDue,
    String? amountPayable,
    String? billMonth,
    String? boxNumber,
    double? latitude,
    double? longitude,
  }) {
    return Customer(
      id: id ?? this.id,
      altCustomerId: altCustomerId ?? this.altCustomerId,
      name: name ?? this.name,
      primaryMobileNumber: primaryMobileNumber ?? this.primaryMobileNumber,
      lcoCustomerId: lcoCustomerId ?? this.lcoCustomerId,
      crfNumber: crfNumber ?? this.crfNumber,
      serialNumber: serialNumber ?? this.serialNumber,
      vcNumber: vcNumber ?? this.vcNumber,
      nickName: nickName ?? this.nickName,
      secondaryMobileNumber: secondaryMobileNumber ?? this.secondaryMobileNumber,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      lastPaidDate: lastPaidDate ?? this.lastPaidDate,
      customerType: customerType ?? this.customerType,
      broadbandUserId: broadbandUserId ?? this.broadbandUserId,
      isShow: isShow ?? this.isShow,
      tmpActivation: tmpActivation ?? this.tmpActivation,
      unpaidAct: unpaidAct ?? this.unpaidAct,
      address: address ?? this.address,
      groupName: groupName ?? this.groupName,
      areaName: areaName ?? this.areaName,
      totalDue: totalDue ?? this.totalDue,
      amountPayable: amountPayable ?? this.amountPayable,
      billMonth: billMonth ?? this.billMonth,
      boxNumber: boxNumber ?? this.boxNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
