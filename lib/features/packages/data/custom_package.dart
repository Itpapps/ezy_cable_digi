/// One custom (digi dealer) package — Android parity (`GetCustomPackages_ActModel`
/// from `getDigiDealerPackages`/`gddp`, field `digi_dealer_packages`). Android
/// defaults quantity="1" and autoRenewal=0 on load.
class CustomPackage {
  final String packageId;
  final String name;
  final String price;
  final String packageRelatedTo;
  final String startDate;
  final String quantity; // user-editable in the activation cart; default "1"
  final int autoRenewal; // 0/1 toggle in the cart; default 0

  const CustomPackage({
    this.packageId = '',
    this.name = '',
    this.price = '',
    this.packageRelatedTo = '',
    this.startDate = '',
    this.quantity = '1',
    this.autoRenewal = 0,
  });

  factory CustomPackage.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return CustomPackage(
      packageId: s('package_id'),
      name: s('name'),
      price: s('price'),
      packageRelatedTo: s('package_related_to'),
      startDate: s('start_date'),
    );
  }

  CustomPackage copyWith({String? quantity, int? autoRenewal}) => CustomPackage(
        packageId: packageId,
        name: name,
        price: price,
        packageRelatedTo: packageRelatedTo,
        startDate: startDate,
        quantity: quantity ?? this.quantity,
        autoRenewal: autoRenewal ?? this.autoRenewal,
      );
}
