import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/settings_store.dart';
import '../../core/data/customer.dart';
import '../../core/data/payment.dart';
import '../../core/utils/share_origin.dart';
import '../../core/theme/theme_constants.dart';
import 'printer_launcher.dart';
import '../search/data/search_repository.dart';
import '../customer/customer_details_screen.dart';
import '../../core/widgets/premium_dialog.dart';

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
  final double billAmount;          // BILL.AMT — from the makePayments response

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
    this.billAmount = 0,
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
  /// Thermal payment receipt — 1:1 with Android BluetoothChatService.write()
  /// (ANTHERMAL branch :1057-1189 / 97BT branch :1216-1350). The only
  /// per-printer differences Android has are the separator ([fmt.sep]) and a
  /// 7-space indent on the date line for 97BT (:1204); label widths (17 + ':'),
  /// field order, title and header/footer blocks are identical in both branches.
  List<String> _buildReceiptLines(ReceiptFormat fmt) {
    final c = widget.customer;
    final p = widget.payment;
    final sep = fmt.sep;

    String fld(String label, String value) {
      final l = label.length >= 17 ? label.substring(0, 17) : label.padRight(17);
      return '$l:$value';
    }
    String money(double v) => v.toStringAsFixed(2);

    final isBroadband = c.broadbandUserId.trim().isNotEmpty;
    final isCombined = isBroadband && c.customerType.trim() == '2';
    final isBroadbandOnly = isBroadband && !isCombined;
    final stbPaid = widget.stbPaidAmount;
    final bbPaid = widget.broadbandPaidAmount;
    // BILL.AMT from the makePayments response (Android parity) — the customer
    // list total is 0 for broadband, so never use c.totalDue here.
    final billAmt = money(widget.billAmount);

    // Date line mirrors Android's Date.toString() reorder: "EEE MMM dd yyyy
    // HH:mm:ss" (BluetoothChatService:1044). 97BT indents the date 7 spaces
    // (:1204); ANTHERMAL has no indent (:1044).
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = p.paymentDate;
    String p2(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${wd[d.weekday - 1]} ${mon[d.month - 1]} ${p2(d.day)} '
        '${d.year} ${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}';
    final date = (fmt.is97bt ? '       ' : '') + dateStr;

    final st = SettingsStore.instance;
    final lines = <String>[];
    // Header block — Android prints it UNCONDITIONALLY: sep, header1, sep,
    // header2, sep (BluetoothChatService:1057-1060). Empty printer-settings
    // headers still emit the separator structure, matching the Android receipt.
    lines.add(sep);
    lines.add(st.header1);
    lines.add(sep);
    lines.add(st.header2);
    lines.add(sep);
    // Title — Android hardcodes 9 leading spaces in both branches (:1059/:1218).
    lines.add('         PAYMENT RECEIPT');
    lines.add(sep);
    lines.add(date);
    lines.add(sep);
    // CRF NUMBER — Android prints only when use_caf == 1 (:1047-1051).
    if (SessionService.instance.useCaf == 1) {
      lines.add(fld('CRF NUMBER', c.crfNumber));
    }
    lines.add(fld('CUSTOMER NAME', c.name));
    // Android parity (BluetoothChatService write): ACCOUNT NUMBER = custId =
    // customer_id (Flutter lcoCustomerId); LCO CUST ID = alt_custom_number
    // (Flutter altCustomNumber). Previously these were swapped/mismapped.
    lines.add(fld('ACCOUNT NUMBER', c.lcoCustomerId));
    lines.add(fld('LCO CUST ID', c.altCustomNumber));
    lines.add(fld('CUSTOMER ADDRESS', c.address)); // Android always prints
    lines.add(fld('RECEIPT NUMBER', p.transactionId));
    lines.add(fld('LAST PAID DATE', c.lastPaidDate)); // Android always prints (:1067)
    lines.add(fld('BILL FOR', c.billMonth)); // Android always prints
    lines.add(fld(isBroadbandOnly ? 'Broadband Amt' : 'PAID.AMT',
        money(isBroadbandOnly ? bbPaid : stbPaid)));
    lines.add(sep);
    lines.add(fld('BILL.AMT', billAmt)); // Android always prints BILL.AMT
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
    // Footer block — Android prints it UNCONDITIONALLY: sep, footer1, sep,
    // footer2, sep (BluetoothChatService:1184-1186).
    lines.add(sep);
    lines.add(st.footer1);
    lines.add(sep);
    lines.add(st.footer2);
    lines.add(sep);
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
    final billAmt = money(widget.billAmount); // from mpay response (Android parity)
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
    lines.add(fld('Lco Customer Id', c.altCustomNumber)); // alt_custom_number
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
    lines.add(fld('Bill Amount', billAmt));
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

  // Shared thermal-printer pipeline (printer picker + connect + ESC/POS write +
  // 40s timeout + success/error SnackBars). Receipt output is unchanged — it
  // still prints `_buildReceiptLines()`.
  Future<void> _openPrinterSheet() => launchThermalPrint(
        context: context,
        printerService: _printerService,
        buildLines: _buildReceiptLines,
      );

  // Offline receipt only. Android's offline PREV/NEXT (prevbtn2/nextbtn2) navigate
  // saved offline records; Flutter returns to the offline collection list. The
  // ONLINE receipt uses prenext prev/next customer instead (see _prevNextCustomer).
  void _finishToNextCustomer() {
    _printerService.disconnectPrinter().whenComplete(() {
      if (!mounted) return;
      Navigator.of(context).pop(); // back to the offline collection list
    });
  }

  // ── Prev/Next customer (Android DisplayPaymentDetails, offline_mode != 1) ─
  // Online receipt: ◄ prevbtn1 = next_cust_search(2), ► nextbtn1 = (1) → SOAP
  // `prenext` → status 0 reopens Customer Details for the adjacent customer.
  // status 1 = "No Records Found!" · 2 = snackbar + "Contact Support" · 3 =
  // "Server is busy or Un reachable!". Android does NOT disconnect the printer
  // here; dispose() releases it when the receipt is finally popped.
  Future<void> _prevNextCustomer(int flag) async {
    final id = int.tryParse(widget.customer.lcoCustomerId.trim());
    if (id == null) {
      showPremiumSnackBar(context, 'Error, Please try again later.',
          isError: true);
      return;
    }
    showPremiumLoading(context, message: 'Searching...   Please wait...');
    final r = await SearchRepository.instance
        .prevNextCustomer(customerId: id, flag: flag);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    if (r.statusCode == 0 && r.customer != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailsScreen(customer: r.customer!),
        ),
      );
    } else if (r.statusCode == 1) {
      await _showInfoDialog('No Records Found!', r.statusMessage);
    } else if (r.statusCode == 2) {
      showPremiumSnackBar(
        context,
        r.statusMessage.isEmpty
            ? 'Contact Support'
            : '${r.statusMessage}: Contact Support',
        isError: true,
      );
    } else {
      await _showInfoDialog(
        'Server is busy or Un reachable!',
        r.statusMessage.isEmpty
            ? 'Please try again after sometime'
            : r.statusMessage,
      );
    }
  }

  Future<void> _showInfoDialog(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body.isEmpty ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
                  ('Account No',      c.lcoCustomerId), // customer_id (Android custId)
                  ('Customer Type',   c.customerTypeLabel),
                  ('Customer Name',   c.name),
                  ('NickName',        c.nickName.isEmpty ? 'NA' : c.nickName),
                  ('Mobile No',       c.primaryMobileNumber),
                  ('LCO Customer Id', c.altCustomNumber), // alt_custom_number
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
                  // Android parity: Bill Amount from the mpay response; Total Due
                  // and Out Amount from the GPA-derived values (same as the printed
                  // receipt). The customer-list totals are 0 for broadband, so they
                  // must NOT be used here.
                  ('Bill Amount',   '₹${widget.billAmount.toStringAsFixed(2)}'),
                  ('Total Due',     '₹${widget.dueAmount.toStringAsFixed(2)}'),
                  ('Out Amount',    '₹${widget.outAmount.toStringAsFixed(2)}'),
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
      // Visible back button (same pill style used across the app). Navigator.pop
      // only closes this screen (online = pushReplacement already removed the
      // payment screen; offline = push). Print/Share/Prev-Next unchanged.
      leading: IconButton(
        tooltip: 'Back',
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: t.backBtnBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      // Print/Share live on the receipt header card (labeled buttons) — no
      // duplicate icons in the app bar.
    );
  }

  Widget _receiptHeaderCard(Payment p, String dateStr, AppThemeConst t) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: t.isLight ? Border.all(color: t.dividerColor) : null,
        boxShadow: [
          // Match the info-card elevation (16 / (0,4)) for consistent card depth.
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
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
                          fontSize: 24,
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
                        Row(
                          children: [
                            Icon(Icons.event_outlined,
                                size: 14, color: t.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: t.cardHeadingText,
                                ),
                              ),
                            ),
                          ],
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
        border: t.isLight ? Border.all(color: t.dividerColor) : null,
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
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 0.6, color: t.dividerColor),
                  _ReceiptRow(
                    label: rows[i].$1,
                    value: rows[i].$2,
                    t: t,
                    accentRight: accentRight,
                  ),
                ],
              ],
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
                // Online: ◄ prev customer (prenext flag 2). Offline: disconnect +
                // back to the offline list (Android's offline prevbtn2 nav).
                onPressed: widget.fromOfflineCollection
                    ? () {
                        _printerService.disconnectPrinter();
                        Navigator.of(context).pop();
                      }
                    : () => _prevNextCustomer(2),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.appBarFg,
                  side: BorderSide(color: t.appBarFg.withValues(alpha: 0.5), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('PREV',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                // Online: ► next customer (prenext flag 1). Offline: back to list.
                onPressed: widget.fromOfflineCollection
                    ? _finishToNextCustomer
                    : () => _prevNextCustomer(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.backBtnBg,
                  foregroundColor: t.appBarFg,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('NEXT CUSTOMER',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Share Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _ShareSheet extends StatelessWidget {
  final String filePath;
  final String transactionId;
  const _ShareSheet({required this.filePath, required this.transactionId});

  @override
  Widget build(BuildContext context) {
    // iOS needs a non-empty anchor rect or share_plus rejects the share before
    // presenting anything. Capture it — and the messenger — from the live sheet
    // context BEFORE popping, since the context is dead afterwards. Android
    // ignores sharePositionOrigin entirely.
    Future<void> shareReceipt({String? subject}) async {
      final origin = shareOriginFrom(context);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      try {
        await Share.shareXFiles([XFile(filePath)],
            subject: subject,
            text: 'Receipt $transactionId',
            sharePositionOrigin: origin);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }

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
            onTap: () => shareReceipt(subject: 'Payment Receipt'),
          ),
          _ShareTile(
            icon: Icons.chat_rounded,
            color: const Color(0xFF25D366),
            label: 'WhatsApp',
            onTap: () => shareReceipt(),
          ),
          _ShareTile(
            icon: Icons.business_center_rounded,
            color: Colors.teal,
            label: 'WhatsApp Business',
            onTap: () => shareReceipt(),
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

// Decorative row icon chosen by the LABEL only — presentation metadata that does
// NOT touch the row's value/data/condition. Unknown/new labels fall back to a
// neutral icon so nothing can break.
IconData _rowIcon(String label) {
  switch (label) {
    case 'Account No':
      return Icons.badge_outlined;
    case 'Customer Type':
      return Icons.category_outlined;
    case 'Customer Name':
      return Icons.person_outline;
    case 'NickName':
      return Icons.sentiment_satisfied_outlined;
    case 'Mobile No':
      return Icons.phone_outlined;
    case 'LCO Customer Id':
      return Icons.apartment_outlined;
    case 'Address':
      return Icons.location_on_outlined;
    case 'Last Paid Date':
      return Icons.event_outlined;
    case 'Bill For':
      return Icons.description_outlined;
    case 'Bill Amount':
      return Icons.receipt_long_outlined;
    case 'Total Due':
      return Icons.account_balance_wallet_outlined;
    case 'Out Amount':
      return Icons.file_download_outlined;
    case 'Discount Amount':
      return Icons.local_offer_outlined;
    case 'Broadband User Id':
    case 'Broadband Paid':
      return Icons.wifi_outlined;
    case 'STB Paid':
      return Icons.tv_outlined;
    case 'Total Paid':
      return Icons.payments_outlined;
    case 'Bank Name':
      return Icons.account_balance_outlined;
    case 'Cheque/DD':
      return Icons.receipt_outlined;
    case 'Branch':
      return Icons.location_city_outlined;
    case 'Instr. Date':
      return Icons.event_outlined;
    default:
      return Icons.info_outline;
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Decorative icon container — presentation only (no onTap, no data).
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_rowIcon(label), size: 15, color: t.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.cardSubtitleText)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accentRight ? t.accent : t.cardBodyText)),
          ),
        ],
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 20),
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