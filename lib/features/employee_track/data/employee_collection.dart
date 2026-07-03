// Employee Track (employee collection report) — Android parity
// (EmployeeTrackFragment, SOAP `empCollection`). NOT GPS/live tracking.

/// One `collectionResult` row. Dealer/Admin responses carry dealer_name/dealer_id;
/// Employee responses omit them. Defensive — missing fields stay ''.
class EmployeeCollection {
  final String employeeId;
  final String name;
  final String dealerName;
  final String dealerId;
  final String amount; // "Amt"

  const EmployeeCollection({
    this.employeeId = '',
    this.name = '',
    this.dealerName = '',
    this.dealerId = '',
    this.amount = '',
  });
}

/// One `collectionCustomerResult` row — Android parity (empCustomerCollectionDetails
/// / `eccd`): a single customer payment collected by an employee. Defensive —
/// missing fields stay ''.
class EmployeeCustomerCollection {
  final String customerId;
  final String customerName;
  final String customNumber; // customnumber
  final String altCustId; // alt_cust_id  → Android "Acc. No."
  final String altCustomNumber; // alt_custom_number → Android "LCO Customer ID"
  final String crfNo; // crfno
  final String employeeId;
  final String employeeName; // "name" in the response
  final String nickname;
  final String paidAmount; // paid_amount
  final String paidOn; // paid_on
  final String paymentMode; // payment_mode
  final String address;

  const EmployeeCustomerCollection({
    this.customerId = '',
    this.customerName = '',
    this.customNumber = '',
    this.altCustId = '',
    this.altCustomNumber = '',
    this.crfNo = '',
    this.employeeId = '',
    this.employeeName = '',
    this.nickname = '',
    this.paidAmount = '',
    this.paidOn = '',
    this.paymentMode = '',
    this.address = '',
  });

  factory EmployeeCustomerCollection.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return EmployeeCustomerCollection(
      customerId: s('customer_id'),
      customerName: s('customer_name'),
      customNumber: s('customnumber'),
      altCustId: s('alt_cust_id'),
      altCustomNumber: s('alt_custom_number'),
      crfNo: s('crfno'),
      employeeId: s('employee_id'),
      employeeName: s('name'),
      nickname: s('nickname'),
      paidAmount: s('paid_amount'),
      paidOn: s('paid_on'),
      paymentMode: s('payment_mode'),
      address: s('address'),
    );
  }
}

/// One `employeeTrackInfoList` row — Android parity (`getEmployeeTrackInfo`/`geti`,
/// `EmployeeTrackAdapter` → `MapsActivityEmp`): a GPS point where an employee
/// performed a given operation. Defensive — missing fields stay ''.
class EmployeeTrackPoint {
  final String operationTypeId;
  final String lat;
  final String lang;
  final String createdDate;
  final String displayName;

  const EmployeeTrackPoint({
    this.operationTypeId = '',
    this.lat = '',
    this.lang = '',
    this.createdDate = '',
    this.displayName = '',
  });

  factory EmployeeTrackPoint.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return EmployeeTrackPoint(
      operationTypeId: s('operation_type_id'),
      lat: s('lat'),
      lang: s('lang'),
      createdDate: s('created_date'),
      displayName: s('display_name'),
    );
  }

  /// Parsed coordinate, or null when the point has no usable lat/lang.
  double? get latitude => double.tryParse(lat);
  double? get longitude => double.tryParse(lang);
  bool get hasLocation =>
      latitude != null && longitude != null && !(latitude == 0 && longitude == 0);
}
