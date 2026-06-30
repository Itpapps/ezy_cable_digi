/// One scheduled-collection (Pay Later) row from `scheduled_collection_data`
/// (Android `PaylaterModel`). Defensive parse — never throws. `customer_id` here is
/// the SERVER's internal id, which the create call (`scheduled_collection_create`)
/// requires (Android passes `paylaterModelArrayList.get(0).getCustomer_id()`).
class PayLaterSchedule {
  final String customerId; // server internal id (used by create)
  final String customerName;
  final String scheduledDate; // yyyy-MM-dd (server returns datetime; first 10)
  final String status;
  final String remarks;
  final String altCustomNumber;
  final String nickname;
  final String altCustId;
  final String customnumber;
  final String customerAccountId;
  final String crfno;
  final String mobileNo;
  final String amount;
  final String isEditable; // "1" → update existing (Android is_edited), else new

  const PayLaterSchedule({
    this.customerId = '',
    this.customerName = '',
    this.scheduledDate = '',
    this.status = '',
    this.remarks = '',
    this.altCustomNumber = '',
    this.nickname = '',
    this.altCustId = '',
    this.customnumber = '',
    this.customerAccountId = '',
    this.crfno = '',
    this.mobileNo = '',
    this.amount = '',
    this.isEditable = '0',
  });

  factory PayLaterSchedule.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    final date = s('scheduled_date');
    return PayLaterSchedule(
      customerId: s('customer_id'),
      customerName: s('customer_name'),
      scheduledDate: date.length >= 10 ? date.substring(0, 10) : date,
      status: s('status'),
      remarks: s('remarks'),
      altCustomNumber: s('alt_custom_number'),
      nickname: s('nickname'),
      altCustId: s('alt_cust_id'),
      customnumber: s('customnumber'),
      customerAccountId: s('customer_account_id'),
      crfno: s('crfno'),
      mobileNo: s('mobile_no'),
      amount: s('amount'),
      isEditable: s('is_editable'),
    );
  }
}

/// Employee LOV item from `emp_details` (`employee_id`, `Name`).
class PayLaterEmployee {
  final String id;
  final String name;
  const PayLaterEmployee(this.id, this.name);

  factory PayLaterEmployee.fromJson(Map<String, dynamic> j) => PayLaterEmployee(
        (j['employee_id'] ?? '').toString().trim(),
        (j['Name'] ?? '').toString().trim(),
      );
}
