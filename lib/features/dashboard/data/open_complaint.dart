/// One open-complaint row from `getopencomplaintslist` (dashboard Complaints tab).
///
/// Android (`DashboardHomeFragment.getopencomplaintslist`) reads these keys from
/// each object of the `opencomplaintList` JSON array. Every field is parsed
/// defensively (missing → ''), so a malformed item never crashes the feed.
/// `latitude`/`longitude` are optional in the existing app (wrapped in try/catch).
class OpenComplaint {
  final String tktNumber;
  final String complaintId;
  final String description;
  final String status;
  final String name;
  final String des;
  final String altCustomNumber;
  final String groupName;
  final String mobileNo;
  final String address1;
  final String crfno;
  final String date;
  final String altCustId;
  final String customerId;
  final String latitude;
  final String longitude;

  const OpenComplaint({
    this.tktNumber = '',
    this.complaintId = '',
    this.description = '',
    this.status = '',
    this.name = '',
    this.des = '',
    this.altCustomNumber = '',
    this.groupName = '',
    this.mobileNo = '',
    this.address1 = '',
    this.crfno = '',
    this.date = '',
    this.altCustId = '',
    this.customerId = '',
    this.latitude = '',
    this.longitude = '',
  });

  factory OpenComplaint.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return OpenComplaint(
      tktNumber: s('tkt_number'),
      complaintId: s('complaint_id'),
      description: s('description'),
      status: s('status'),
      name: s('name'),
      des: s('des'),
      altCustomNumber: s('alt_custom_number'),
      groupName: s('group_name'),
      mobileNo: s('mobile_no'),
      address1: s('address1'),
      crfno: s('crfno'),
      date: s('date'),
      altCustId: s('alt_cust_id'),
      customerId: s('customer_id'),
      latitude: s('latitude'),
      longitude: s('longitude'),
    );
  }

  /// Android OpenComplaints_RecyclerView_Adapter :97-112 (map icon): Google
  /// Maps directions to the customer — null when the complaint has no
  /// location (Android "Location details not found.").
  Uri? get mapUri {
    final lat = double.tryParse(latitude);
    final lon = double.tryParse(longitude);
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;
    return Uri.parse('http://maps.google.com/maps?daddr=$latitude,$longitude');
  }
}
