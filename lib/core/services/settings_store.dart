import 'package:shared_preferences/shared_preferences.dart';

/// Receipt/printer settings — the Flutter twin of Android's `settings_Pref`
/// SharedPreferences (`PrinterSetting_Fragment` / `DisplayPaymentDetails_Fragment`).
///
/// Keys MATCH Android exactly: `header1`, `header2`, `footer1`, `footer2`, and the
/// amount filter (`amt_filter`, Android `AMT_FILTER_PREF`, default 500). Values are
/// cached in memory after [load] so the (synchronous) receipt builder can read them
/// without awaiting. Header/footer feed the thermal receipt; `amtFilter` is persisted
/// for parity (its dashboard/search consumer is a separate, not-yet-wired concern).
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _kHeader1 = 'header1';
  static const _kHeader2 = 'header2';
  static const _kFooter1 = 'footer1';
  static const _kFooter2 = 'footer2';
  static const _kAmtFilter = 'amt_filter';
  // Saved default printer (Flutter "Saved Printer" feature; Android `bledevices`).
  static const _kPrinterMac = 'printer_mac';
  static const _kPrinterName = 'printer_name';

  String header1 = '';
  String header2 = '';
  String footer1 = '';
  String footer2 = '';
  double amtFilter = 500.0;
  String printerMac = '';
  String printerName = '';

  /// Load cached values (defaults: '' and 500.0, matching Android).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    header1 = p.getString(_kHeader1) ?? '';
    header2 = p.getString(_kHeader2) ?? '';
    footer1 = p.getString(_kFooter1) ?? '';
    footer2 = p.getString(_kFooter2) ?? '';
    amtFilter = p.getDouble(_kAmtFilter) ?? 500.0;
    printerMac = p.getString(_kPrinterMac) ?? '';
    printerName = p.getString(_kPrinterName) ?? '';
  }

  /// Persist the default printer (additive — does not touch the existing flow).
  Future<void> savePrinter(String mac, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrinterMac, mac);
    await p.setString(_kPrinterName, name);
    printerMac = mac;
    printerName = name;
  }

  /// Forget the saved printer (reverts to manual "Choose Printer" each time).
  Future<void> clearPrinter() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPrinterMac);
    await p.remove(_kPrinterName);
    printerMac = '';
    printerName = '';
  }

  /// Persist all five (Android saves them together on Submit).
  Future<void> save({
    required String header1,
    required String header2,
    required String footer1,
    required String footer2,
    required double amtFilter,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHeader1, header1);
    await p.setString(_kHeader2, header2);
    await p.setString(_kFooter1, footer1);
    await p.setString(_kFooter2, footer2);
    await p.setDouble(_kAmtFilter, amtFilter);
    this.header1 = header1;
    this.header2 = header2;
    this.footer1 = footer1;
    this.footer2 = footer2;
    this.amtFilter = amtFilter;
  }
}
