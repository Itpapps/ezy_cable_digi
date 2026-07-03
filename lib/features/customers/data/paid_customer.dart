/// One `Paid_customer_details` row — Android parity (`getPaidCustomer_Detail` /
/// `gpcd`, `PaidlistFragment`): a customer who paid in the selected month.
/// Defensive — missing fields stay ''.
class PaidCustomer {
  final String name;
  final String crfNo; // crfno
  final String altCustomNumber; // customnumber (Android shows as LCO Customer id)
  final String thisMonthPending; // thism_pending
  final String lastPaidDate; // last_paid_date
  final String lastPaidAmount; // last_paid_amount
  final String customerId; // customer_id
  final String altCustId; // alt_cust_id
  final String address; // address1
  final String mobileNo; // mobile_no
  final String boxNumber; // box_number
  final String vcNumber; // vc_number
  final String billMonth; // bill_month

  const PaidCustomer({
    this.name = '',
    this.crfNo = '',
    this.altCustomNumber = '',
    this.thisMonthPending = '',
    this.lastPaidDate = '',
    this.lastPaidAmount = '',
    this.customerId = '',
    this.altCustId = '',
    this.address = '',
    this.mobileNo = '',
    this.boxNumber = '',
    this.vcNumber = '',
    this.billMonth = '',
  });

  factory PaidCustomer.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return PaidCustomer(
      name: s('name'),
      crfNo: s('crfno'),
      altCustomNumber: s('customnumber'),
      thisMonthPending: s('thism_pending'),
      lastPaidDate: s('last_paid_date'),
      lastPaidAmount: s('last_paid_amount'),
      customerId: s('customer_id'),
      altCustId: s('alt_cust_id'),
      address: s('address1'),
      mobileNo: s('mobile_no'),
      boxNumber: s('box_number'),
      vcNumber: s('vc_number'),
      billMonth: s('bill_month'),
    );
  }
}
