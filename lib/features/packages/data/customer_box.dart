/// One customer STB/box from `getCustomerBoxes` (key `gcb`).
///
/// State rule (LIVE-VERIFIED & frozen in PACKAGE_OPERATIONS_COMPLETE.md §7):
/// `box_status == "1"` → **Active**; anything else → **DeActive**.
/// Every field is parsed defensively (missing → ''), never throws.
class CustomerBox {
  final String boxId;
  final String boxNumber;
  final String vcNumber;
  final String customerId;
  final String casServerId;
  final String status;
  final String boxStatus;

  const CustomerBox({
    this.boxId = '',
    this.boxNumber = '',
    this.vcNumber = '',
    this.customerId = '',
    this.casServerId = '',
    this.status = '',
    this.boxStatus = '',
  });

  /// Frozen rule: box_status "1" = Active, else DeActive.
  bool get isActive => boxStatus.trim() == '1';
  String get stateLabel => isActive ? 'Active' : 'DeActive';

  factory CustomerBox.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return CustomerBox(
      boxId: s('box_id'),
      boxNumber: s('box_number'),
      vcNumber: s('vc_number'),
      customerId: s('customer_id'),
      casServerId: s('cas_server_id'),
      status: s('status'),
      boxStatus: s('box_status'),
    );
  }
}
