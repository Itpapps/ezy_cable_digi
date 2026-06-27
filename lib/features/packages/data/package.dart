/// Category of a per-box customer package (`getCustomerPackages`, key `gcp`).
/// Android groups packages into `is_base` / `is_add_on` / `is_al_a_carte`.
enum PackageCategory { base, addOn, alaCarte }

/// One per-box package from `getCustomerPackages` (gcp).
/// Each item: `package_id, name, price, pricing_structure_type`.
/// Defensive parse — never throws.
class Package {
  final String packageId;
  final String name;
  final String price;
  final String pricingStructureType;
  final PackageCategory category;

  const Package({
    this.packageId = '',
    this.name = '',
    this.price = '',
    this.pricingStructureType = '',
    required this.category,
  });

  /// `pricing_structure_type == "2"` → quantity-selectable package
  /// (Android `ActiveAdapter_listview.java:159`). This is a TYPE, not a status.
  bool get isQuantitySelectable => pricingStructureType.trim() == '2';

  factory Package.fromJson(Map<String, dynamic> j, PackageCategory category) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return Package(
      packageId: s('package_id'),
      name: s('name'),
      price: s('price'),
      pricingStructureType: s('pricing_structure_type'),
      category: category,
    );
  }
}

/// One active package from `getcustomerpackageslist` (key `gcpl`).
/// Has expiry dates: `start_date` / `end_date`. Item fields:
/// `name, start_date, end_date, status, serial_number, mac_vc_number, price`.
class ActivePackage {
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final String serialNumber;
  final String macVcNumber;
  final String price;

  const ActivePackage({
    this.name = '',
    this.startDate = '',
    this.endDate = '',
    this.status = '',
    this.serialNumber = '',
    this.macVcNumber = '',
    this.price = '',
  });

  factory ActivePackage.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return ActivePackage(
      name: s('name'),
      startDate: s('start_date'),
      endDate: s('end_date'),
      status: s('status'),
      serialNumber: s('serial_number'),
      macVcNumber: s('mac_vc_number'),
      price: s('price'),
    );
  }
}
