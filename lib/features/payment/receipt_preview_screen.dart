import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/settings_store.dart';
import '../../core/data/customer.dart';
import '../../core/data/payment.dart';
import '../../core/theme/theme_constants.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  final Customer customer;
  final Payment payment;
  final bool fromOfflineCollection;
  final double broadbandPaidAmount; // broadband leg paid (0 for STB-only)
  final double stbPaidAmount;       // STB leg paid (used in the combined breakdown)
  final double discountAmount;      // discount applied (0 if none)
  final String dealerBusinessName;  // from the server response (receipt header)
  final double dueAmount;           // TOT.DUE.AMT — GPA pending of the primary leg
  final double outAmount;           // OUT.AMT — outstanding after this payment

  const ReceiptPreviewScreen({
    super.key,
    required this.customer,
    required this.payment,
    this.fromOfflineCollection = false,
    this.broadbandPaidAmount = 0,
    this.stbPaidAmount = 0,
    this.discountAmount = 0,
    this.dealerBusinessName = '',
    this.dueAmount = 0,
    this.outAmount = 0,
  });

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen>
    with SingleTickerProviderStateMixin {
  final RealBluetoothService _printerService = RealBluetoothService();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    // Load receipt header/footer (printer settings) so the thermal lines can
    // include them — matches Android DisplayPaymentDetails reading settings_Pref.
    SettingsStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _printerService.disconnectPrinter();
    super.dispose();
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  /// Builds the receipt as ordered 32-col text lines — the existing app's MOBILE
  /// thermal layout, populated with available (Group A) data. Optional (Group B:
  /// dealer header/footer, taxes, due/out amounts, last-paid date, CRF) is omitted
  /// until sourced from the backend. No ₹ (matches the existing thermal print,
  /// which prints plain numbers). Both the printer and the PDF render these lines,
  /// so they stay identical. (This is the mobile copy only — NOT the CAF/offline copy.)
  List<String> _buildReceiptLines() {
    final c = widget.customer;
    final p = widget.payment;
    const sep = '................................'; // 32 dots

    String fld(String label, String value) {
      final l = label.length >= 17 ? label.substring(0, 17) : label.padRight(17);
      return '$l:$value';
    }
    String ctr(String s) =>
        s.length >= 32 ? s.substring(0, 32) : ' ' * ((32 - s.length) ~/ 2) + s;
    String money(double v) => v.toStringAsFixed(2);

    final isBroadband = c.broadbandUserId.trim().isNotEmpty;
    final isCombined = isBroadband && c.customerType.trim() == '2';
    final isBroadbandOnly = isBroadband && !isCombined;
    final stbPaid = widget.stbPaidAmount;
    final bbPaid = widget.broadbandPaidAmount;
    final billAmt = c.totalDue.replaceAll('₹', '').trim();

    final d = p.paymentDate;
    final date = '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    final st = SettingsStore.instance;
    final lines = <String>[];
    // Printer-settings header1/header2 (Android DisplayPaymentDetails:662-670):
    // leading separator, then each header (raw/left, only when set) followed by a
    // separator, then the title. Blank default → receipt unchanged. It does NOT
    // print the dealer business name here (matches Android).
    if (st.header1.isNotEmpty || st.header2.isNotEmpty) {
      lines.add(sep);
      if (st.header1.isNotEmpty) {
        lines.add(st.header1);
        lines.add(sep);
      }
      if (st.header2.isNotEmpty) {
        lines.add(st.header2);
        lines.add(sep);
      }
    }
    lines.add(ctr('PAYMENT RECEIPT'));
    lines.add(sep);
    lines.add(date);
    lines.add(sep);
    lines.add(fld('CUSTOMER NAME', c.name));
    lines.add(fld('ACCOUNT NUMBER', c.altCustomerId));
    lines.add(fld('LCO CUST ID', c.lcoCustomerId));
    if (c.address.trim().isNotEmpty) lines.add(fld('CUSTOMER ADDRESS', c.address));
    lines.add(fld('RECEIPT NUMBER', p.transactionId));
    if (c.billMonth.trim().isNotEmpty) lines.add(fld('BILL FOR', c.billMonth));
    lines.add(fld(isBroadbandOnly ? 'Broadband Amt' : 'PAID.AMT',
        money(isBroadbandOnly ? bbPaid : stbPaid)));
    lines.add(sep);
    if (billAmt.isNotEmpty) lines.add(fld('BILL.AMT', billAmt));
    if (isBroadband) {
      lines.add(fld('BROADBAND ID', c.broadbandUserId));
      if (isCombined) {
        lines.add(fld('BROADBAND Amt', money(bbPaid)));
        lines.add(fld('TOTAL PAID AMT', money(stbPaid + bbPaid)));
      }
    }
    // Android always prints TOT.DUE.AMT then OUT.AMT (BluetoothChatService :1171-1173).
    // dueAmt = GPA pending; outAmt = pending − paid − discount (post-payment outstanding).
    lines.add(fld('TOT.DUE.AMT', money(widget.dueAmount)));
    lines.add(fld('OUT.AMT', money(widget.outAmount)));
    if (widget.discountAmount > 0) {
      lines.add(fld('DISCOUNT.AMT', money(widget.discountAmount)));
    }
    lines.add(sep);
    // Printer-settings footer1/footer2 (Android DisplayPaymentDetails:728-735):
    // each footer (raw, only when set) followed by a separator. Remaining Group B
    // (CRF, LAST PAID DATE, taxes) stays backend-sourced — see RECEIPT_LAYOUT.md.
    if (st.footer1.isNotEmpty) {
      lines.add(st.footer1);
      lines.add(sep);
    }
    if (st.footer2.isNotEmpty) {
      lines.add(st.footer2);
      lines.add(sep);
    }
    return lines;
  }

  /// Builds the SHARE PDF text — mirrors the existing app's share layout
  /// (`savePdf`), which is DIFFERENT from the thermal print: dashed separators,
  /// Title-case 15-char labels, "Mobile No." instead of "Account Number", the
  /// broadband block directly under the customer name, no "Total Paid" line, and
  /// "Due Amount"/"Out Amount" always present. Group B (printer header1/header2 +
  /// footer1/footer2, CRF/CAF, taxes) is omitted until sourced from the backend.
  /// See server docs/RECEIPT_SHARE_FLOW.md.
  List<String> _buildSharePdfLines() {
    final c = widget.customer;
    final p = widget.payment;
    const line = '--------------------------------'; // 32 dashes (Android savePdf)

    String fld(String label, String value) => '${label.padRight(15)}:$value';
    String money(double v) => v.toStringAsFixed(2);

    final isBroadband = c.broadbandUserId.trim().isNotEmpty;
    final isCombined = isBroadband && c.customerType.trim() == '2';
    final isBroadbandOnly = isBroadband && !isCombined;
    final stbPaid = widget.stbPaidAmount;
    final bbPaid = widget.broadbandPaidAmount;
    final billAmt = c.totalDue.replaceAll('₹', '').trim();
    final addr = c.address.replaceAll('\n', ' ');

    // Date mirrors Android's Date.toString() reorder: "EEE MMM dd yyyy HH:mm:ss".
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = p.paymentDate;
    String p2(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${wd[d.weekday - 1]} ${mon[d.month - 1]} ${p2(d.day)} '
        '${d.year} ${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';

    final lines = <String>[];
    lines.add(line);
    lines.add(' PAYMENT RECEIPT ');
    lines.add(line);
    lines.add(dateStr);
    lines.add(line);
    lines.add(fld('Customer Name', c.name));
    if (isBroadband) {
      lines.add(fld('BroadBand ID', c.broadbandUserId));
      if (!isBroadbandOnly) {
        lines.add(fld('BroadBand Amt', money(bbPaid)));
      }
    }
    lines.add(fld('Lco Customer Id', c.lcoCustomerId));
    if (addr.isNotEmpty) lines.add(fld('Address', addr));
    lines.add(fld('Mobile No.', c.primaryMobileNumber));
    lines.add(fld('Receipt No.', p.transactionId));
    if (c.lastPaidDate.trim().isNotEmpty) {
      lines.add(fld('Last Paid Date', c.lastPaidDate));
    }
    if (c.billMonth.trim().isNotEmpty) lines.add(fld('Bill For', c.billMonth));
    lines.add(fld(isBroadbandOnly ? 'Broadband Amt' : 'Paid Amount',
        money(isBroadbandOnly ? bbPaid : stbPaid)));
    lines.add(line);
    if (billAmt.isNotEmpty) lines.add(fld('Bill Amount', billAmt));
    lines.add(fld('Due Amount', money(widget.dueAmount)));
    lines.add(fld('Out Amount', money(widget.outAmount)));
    if (widget.discountAmount > 0) {
      lines.add(fld('Discount Amount', money(widget.discountAmount)));
    }
    lines.add(line);
    return lines;
  }

  Future<Uint8List> _buildPdfBytes() async {
    final pdf = pw.Document();
    final mono = pw.Font.courier();
    final lines = _buildSharePdfLines();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5, // Android share PDF uses A5
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              pw.Text(l, style: pw.TextStyle(font: mono, fontSize: 10)),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  /// Filesystem-safe base name for the shared PDF (mirrors Android's
  /// `customerName.pdf`). Falls back to "receipt" when empty.
  String _safeFileName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  Future<void> _showShareSheet() async {
    try {
      final bytes = await _buildPdfBytes();
      final dir   = await getTemporaryDirectory();
      // Android names the shared file "<customerName>.pdf". Strip filesystem-
      // unsafe characters — the server receipt number contains "/" (e.g.
      // CR1103/.../38751) which would otherwise create bogus subdirectories and
      // crash the file write.
      final path  = '${dir.path}/${_safeFileName(widget.customer.name)}.pdf';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _ShareSheet(
          filePath:      path,
          transactionId: widget.payment.transactionId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  // ── Print: open bottom sheet, auto-scan devices ────────────────────────

  Future<void> _openPrinterSheet() async {
    try {
      await _printerService.disconnectPrinter();
    } catch (_) {}

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AutoScanPrinterSheet(
        printerService: _printerService,
        onPrint: _doPrint,
      ),
    );

    try {
      await _printerService.disconnectPrinter();
    } catch (_) {}
  }

  Future<void> _doPrint(String mac) async {
    try {
      await _printerService.printReceipt(
        mac: mac,
        lines: _buildReceiptLines(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Printed Successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // close sheet
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _finishToNextCustomer() {
    _printerService.disconnectPrinter().whenComplete(() {
      if (!mounted) return;
      if (widget.fromOfflineCollection) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    final p     = widget.payment;
    final c     = widget.customer;
    final title = widget.fromOfflineCollection
        ? 'OFFLINE REPORT'
        : 'PAYMENT DETAILS';

    final dateStr =
        '${p.paymentDate.day.toString().padLeft(2, '0')}-'
        '${p.paymentDate.month.toString().padLeft(2, '0')}-'
        '${p.paymentDate.year}';

    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _buildAppBar(title, t),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.paddingM, AppSizes.paddingM,
              AppSizes.paddingM, 100),
          child: Column(
            children: [
              _receiptHeaderCard(p, dateStr, t),
              const SizedBox(height: AppSizes.paddingM),
              _infoCard(
                title: 'CUSTOMER INFO',
                rows: [
                  ('Account No',      c.altCustomerId),
                  ('Customer Type',   c.customerTypeLabel),
                  ('Customer Name',   c.name),
                  ('NickName',        c.nickName.isEmpty ? 'NA' : c.nickName),
                  ('Mobile No',       c.primaryMobileNumber),
                  ('LCO Customer Id', c.lcoCustomerId),
                  ('Address',         c.address),
                  ('Last Paid Date',  c.lastPaidDate),
                  ('Bill For',        c.billMonth),
                ],
                t: t,
              ),
              const SizedBox(height: AppSizes.paddingM),
              _infoCard(
                title: 'PAYMENT INFO',
                rows: [
                  ('Bill Amount',                          c.totalDue),
                  ('Total Due(billamt+prev pending)',       c.pendingAmount),
                  ('Out Amount',                           c.amountPayable),
                  ('Discount Amount',                      '₹${widget.discountAmount.toStringAsFixed(2)}'),
                  // Broadband leg (broadband customers) — mirrors the existing
                  // app's payment-details layout: BB user id + BB paid, and for a
                  // combined (STB & Broadband) customer also STB paid + Total paid.
                  if (c.broadbandUserId.trim().isNotEmpty) ...[
                    ('Broadband User Id', c.broadbandUserId),
                    ('Broadband Paid',
                        '₹${widget.broadbandPaidAmount.toStringAsFixed(2)}'),
                    if (c.customerType.trim() == '2') ...[
                      ('STB Paid', '₹${widget.stbPaidAmount.toStringAsFixed(2)}'),
                      ('Total Paid',
                          '₹${(widget.stbPaidAmount + widget.broadbandPaidAmount).toStringAsFixed(2)}'),
                    ],
                  ],
                  if (p.paymentMethod == 'bank') ...{
                    ('Bank Name',   p.bankName),
                    ('Cheque/DD',   p.chequeNo),
                    ('Branch',      p.branch),
                    ('Instr. Date', p.instrumentDate),
                  },
                ],
                t: t,
                accentRight: true,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomBar(t),
    );
  }

  PreferredSizeWidget _buildAppBar(String title, AppThemeConst t) {
    return AppBar(
      backgroundColor: t.appBarBg,
      foregroundColor: t.appBarFg,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      actions: [
        _AppBarAction(
          icon: Iconsax.printer,
          color: Colors.redAccent,
          onTap: _openPrinterSheet,
          t: t,
        ),
        _AppBarAction(
          icon: Iconsax.share,
          color: t.appBarFg,
          onTap: _showShareSheet,
          t: t,
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _receiptHeaderCard(Payment p, String dateStr, AppThemeConst t) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  'Receipt No',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.cardSubtitleText,
                  ),
                ),
                const Spacer(),
                _ReceiptIconBtn(
                  icon: Iconsax.printer,
                  color: Colors.red,
                  label: 'Print',
                  onTap: _openPrinterSheet,
                  t: t,
                ),
                const SizedBox(width: 10),
                _ReceiptIconBtn(
                  icon: Iconsax.share,
                  color: t.accent,
                  label: 'Share',
                  onTap: _showShareSheet,
                  t: t,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                p.transactionId,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: t.accent,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: t.dividerColor),
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paid Amount',
                        style: TextStyle(
                          fontSize: 12,
                          color: t.cardSubtitleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${p.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: t.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: t.dividerColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment Date',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.cardSubtitleText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: t.cardHeadingText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required List<(String, String)> rows,
    required AppThemeConst t,
    bool accentRight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: t.headerGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSizes.radiusM)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: rows
                  .map((r) => _ReceiptRow(
                label: r.$1,
                value: r.$2,
                t: t,
                accentRight: accentRight,
              ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(AppThemeConst t) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: t.appBarBg,
          boxShadow: [
            BoxShadow(
              color: t.cardShadowColor,
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _printerService.disconnectPrinter();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.appBarFg,
                  side: BorderSide(color: t.appBarFg.withValues(alpha: 0.5), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                ),
                child: const Text('PREV',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _finishToNextCustomer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.backBtnBg,
                  foregroundColor: t.appBarFg,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                ),
                child: const Text('NEXT CUSTOMER',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-Scan Printer Bottom Sheet
// Opens, immediately scans for paired devices, shows list.
// Connect → Print button appears.
// ─────────────────────────────────────────────────────────────────────────────

class _AutoScanPrinterSheet extends StatefulWidget {
  final RealBluetoothService printerService;
  final Future<void> Function(String mac) onPrint;

  const _AutoScanPrinterSheet({
    required this.printerService,
    required this.onPrint,
  });

  @override
  State<_AutoScanPrinterSheet> createState() =>
      _AutoScanPrinterSheetState();
}

class _AutoScanPrinterSheetState extends State<_AutoScanPrinterSheet> {
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selected;
  bool _isScanning   = true;
  bool _isConnecting = false;
  bool _connected    = false;
  bool _isPrinting   = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _devices    = [];
    });
    try {
      final devices = await widget.printerService.getDevices();
      setState(() {
        _devices    = devices;
        _isScanning = false;
      });
    } catch (_) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connect(BluetoothInfo device) async {
    setState(() {
      _isConnecting = true;
      _selected     = device;
      _connected    = false;
    });
    final ok = await widget.printerService.connectPrinter(device.macAdress);
    if (ok) {
      final ensured =
      await widget.printerService.ensureConnected(device.macAdress);
      setState(() {
        _connected    = ensured;
        _isConnecting = false;
      });
    } else {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✗ Connection Failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _print() async {
    if (_selected == null) return;
    setState(() => _isPrinting = true);
    await widget.onPrint(_selected!.macAdress);
    if (mounted) setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0277BD), Color(0xFF26C6DA)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Iconsax.printer,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Select Printer',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // Rescan button
              GestureDetector(
                onTap: _isScanning ? null : _scan,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Rescan',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
              if (_connected) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth_connected,
                          size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Connected',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.green)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Device list or scanning indicator
          if (_isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Scanning for devices...',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else if (_devices.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No paired devices found.\nPair your printer in Bluetooth settings first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: _devices.map((d) {
                  final isSel = _selected?.macAdress == d.macAdress;
                  return GestureDetector(
                    onTap: _isConnecting ? null : () => _connect(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : const Color(0xFFF4F7FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel
                              ? AppColors.primary.withValues(alpha: 0.35)
                              : const Color(0xFFCBD5F5),
                          width: isSel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth,
                              size: 18,
                              color: isSel
                                  ? AppColors.primary
                                  : AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name.isEmpty ? 'Unknown Device' : d.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isSel
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  d.macAdress,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isConnecting &&
                              isSel)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary),
                            )
                          else if (isSel && _connected)
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 18)
                          else if (isSel)
                              const Icon(Icons.check_circle_outline,
                                  color: AppColors.primary, size: 18),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 14),

          // Print button — visible only after connected
          if (_connected)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isPrinting ? null : _print,
                icon: _isPrinting
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
                    : const Icon(Iconsax.printer, size: 18),
                label: Text(_isPrinting ? 'Printing...' : 'Print'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(AppSizes.radiusM),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Share Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _ShareSheet extends StatelessWidget {
  final String filePath;
  final String transactionId;
  const _ShareSheet({required this.filePath, required this.transactionId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Share Receipt',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          _ShareTile(
            icon: Icons.email_rounded,
            color: Colors.red,
            label: 'Gmail',
            onTap: () async {
              Navigator.pop(context);
              await Share.shareXFiles([XFile(filePath)],
                  subject: 'Payment Receipt',
                  text: 'Receipt $transactionId');
            },
          ),
          _ShareTile(
            icon: Icons.chat_rounded,
            color: const Color(0xFF25D366),
            label: 'WhatsApp',
            onTap: () async {
              Navigator.pop(context);
              await Share.shareXFiles([XFile(filePath)],
                  text: 'Receipt $transactionId');
            },
          ),
          _ShareTile(
            icon: Icons.business_center_rounded,
            color: Colors.teal,
            label: 'WhatsApp Business',
            onTap: () async {
              Navigator.pop(context);
              await Share.shareXFiles([XFile(filePath)],
                  text: 'Receipt $transactionId');
            },
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ShareTile(
      {required this.icon,
        required this.color,
        required this.label,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final AppThemeConst t;
  final bool accentRight;
  const _ReceiptRow(
      {required this.label,
        required this.value,
        required this.t,
        this.accentRight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.cardSubtitleText)),
          ),
          Expanded(
            flex: 5,
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentRight
                        ? t.accent
                        : t.cardBodyText)),
          ),
        ],
      ),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final AppThemeConst t;
  const _AppBarAction(
      {required this.icon, required this.color, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: t.backBtnBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _ReceiptIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final AppThemeConst t;
  const _ReceiptIconBtn(
      {required this.icon,
        required this.color,
        required this.label,
        required this.onTap,
        required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: t.cardSubtitleText)),
        ],
      ),
    );
  }
}