/// One broadband plan/expiry row — Android parity (`BroadBandListModel`,
/// from `broadband_expiry_list`: `broadband_renewedlist_data` + `expiry_list`).
class BroadBandPlan {
  final String broadbandUserId;
  final String subscriberName;
  final String subscriberStatus;
  final String lastPurchasedPlanName;
  final String mrp;
  final String dateOfPurchase;
  final String modeOfPurchase;
  final String finalExpiryDate;
  final String extendedDate;

  const BroadBandPlan({
    this.broadbandUserId = '',
    this.subscriberName = '',
    this.subscriberStatus = '',
    this.lastPurchasedPlanName = '',
    this.mrp = '',
    this.dateOfPurchase = '',
    this.modeOfPurchase = '',
    this.finalExpiryDate = '',
    this.extendedDate = '',
  });

  factory BroadBandPlan.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return BroadBandPlan(
      broadbandUserId: s('broadband_user_id'),
      subscriberName: s('subscriber_name'),
      subscriberStatus: s('subscriber_status'),
      lastPurchasedPlanName: s('last_purchased_plan_name'),
      mrp: s('mrp'),
      dateOfPurchase: s('date_of_purchase'),
      modeOfPurchase: s('mode_of_purchase'),
      finalExpiryDate: s('final_expiry_date'),
      extendedDate: s('extended_date'),
    );
  }

  /// Android trims dates to yyyy-MM-dd (`.substring(0,10)`) for display.
  String get startDate =>
      dateOfPurchase.length >= 10 ? dateOfPurchase.substring(0, 10) : dateOfPurchase;
  String get endDate =>
      finalExpiryDate.length >= 10 ? finalExpiryDate.substring(0, 10) : finalExpiryDate;
}
