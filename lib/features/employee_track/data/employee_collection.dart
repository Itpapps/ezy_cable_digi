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
