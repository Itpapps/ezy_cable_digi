/// One row from `getCustomerComplaintList` (a customer's complaint history).
///
/// Android (`Complaints_Fragment`) reads these keys from each repeated
/// `customerComplaintList` element. Every field is parsed defensively (missing
/// → ''), so a malformed item never crashes the history screen.
class CustomerComplaint {
  final String customerId;
  final String altCustomerId;
  final String customNumber;
  final String customerName;
  final String groupName;
  final String complaintId;
  final String ticketNumber;
  final String description;
  final String complaintTime;
  final String status;

  const CustomerComplaint({
    this.customerId = '',
    this.altCustomerId = '',
    this.customNumber = '',
    this.customerName = '',
    this.groupName = '',
    this.complaintId = '',
    this.ticketNumber = '',
    this.description = '',
    this.complaintTime = '',
    this.status = '',
  });
}
