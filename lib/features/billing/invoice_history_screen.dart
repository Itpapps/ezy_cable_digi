import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/data/customer.dart';
import '../../core/utils/share_origin.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/settings_store.dart';
import '../payment/printer_launcher.dart';
import 'data/invoice_history_repository.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Invoice History — real `InvoiceService` SOAP (Android `InvoiceHistory`).
/// Sends the system customer id (`altCustomerId`, = Android `custId`/`altCustId`).
class InvoiceHistoryScreen extends StatefulWidget {
  final Customer customer;
  const InvoiceHistoryScreen({super.key, required this.customer});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  bool _loading = true;
  String _message = '';
  List<InvoiceRecord> _invoices = const [];

  final RealBluetoothService _printerService = RealBluetoothService();

  @override
  void initState() {
    super.initState();
    _load();
    SettingsStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  static const _sep = '--------------------------------';

  String _timestamp() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wd[n.weekday - 1]} ${mo[n.month - 1]} ${two(n.day)} ${n.year} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  /// Thermal print — 1:1 with BluetoothChatService "INVOICE HISTORY"
  /// (offline_report=8, :1678-1693). CRF line omitted (no CRF in the model).
  List<String> _buildPrintLines(InvoiceRecord inv, ReceiptFormat fmt) {
    final c = widget.customer;
    final s = SettingsStore.instance;
    final sep = fmt.sep;
    return [
      sep, s.header1, sep, s.header2,
      sep, '        INVOICE HISTORY         ',
      sep, _timestamp(), sep,
      'CUSTOMER NAME    :${c.name}',
      'LCO CUST ID      :${c.lcoCustomerId}',
      'INVOICE NO.      :${inv.billingId}',
      'INVOICE DATE     :${inv.billDate}',
      'DUE DATE         :${inv.dueDate}',
      'BILL NO.         :${inv.billNo}',
      'BILL AMOUNT      :${inv.billAmount}',
      'TAX AMOUNT       :${inv.taxAmount}',
      'PENDING AMOUNT   :${inv.pendingAmount}',
      'TOTAL AMOUNT     :${inv.totalAmount}',
      'PACKAGE NAME     :${inv.packageName}',
      sep, s.footer1, sep, s.footer2, sep,
    ];
  }

  /// Share PDF — 1:1 with InvoiceHistory.ShareInvoice (:204-253).
  List<String> _buildShareLines(InvoiceRecord inv) {
    final c = widget.customer;
    final s = SettingsStore.instance;
    final lines = <String>[_sep];
    if (s.header1.isNotEmpty) lines..add(s.header1)..add(_sep);
    if (s.header2.isNotEmpty) lines..add(s.header2)..add(_sep);
    lines
      ..add(' INVOICE HISTORY  ')
      ..add(_sep)
      ..add(_timestamp())
      ..add(_sep);
    lines.add('CUSTOMER NAME   :${c.name}');
    lines.add('LCO CUSTOMER ID :${c.lcoCustomerId}');
    lines.add('INVOICE NUMBER  :${inv.billingId}');
    lines.add('INVOICE DATE    :${inv.billDate}');
    lines.add('DUE DATE        :${inv.dueDate}');
    lines.add('BILL NUMBER     :${inv.billNo}');
    lines.add('BILL AMOUNT     :${inv.billAmount}');
    lines.add('TAX AMOUNT      :${inv.taxAmount}');
    lines.add('PENDING AMOUNT  :${inv.pendingAmount}');
    lines.add('TOTAL AMOUNT    :${inv.totalAmount}');
    lines.add('PACKAGE NAME    :${inv.packageName}');
    lines.add(_sep);
    if (s.footer1.isNotEmpty) lines..add(s.footer1)..add(_sep);
    if (s.footer2.isNotEmpty) lines..add(s.footer2)..add(_sep);
    return lines;
  }

  Future<void> _printInvoice(InvoiceRecord inv) => launchThermalPrint(
        context: context,
        printerService: _printerService,
        buildLines: (fmt) => _buildPrintLines(inv, fmt),
      );

  /// [originContext] is the tapped invoice card's context — iOS needs it to
  /// anchor the share sheet (see [shareOriginFrom]).
  Future<void> _shareInvoice(BuildContext originContext, InvoiceRecord inv) async {
    try {
      // Inside the try: a failure here must surface as "Share failed", not die
      // as an unhandled async error (the callback discards this Future).
      final origin = shareOriginFrom(originContext);
      final lines = _buildShareLines(inv);
      final doc = pw.Document();
      final mono = pw.Font.courier();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final l in lines)
                pw.Text(l, style: pw.TextStyle(font: mono, fontSize: 10)),
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final safe = widget.customer.name
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final path = '${dir.path}/${safe.isEmpty ? 'invoice' : safe}.pdf';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)],
          subject: 'Invoice History of ${widget.customer.name}',
          sharePositionOrigin: origin);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // System customer id = Android `custId`/`altCustId` = JSON `customer_id`
    // (Flutter `lcoCustomerId`). `alt_cust_id` is only a display number.
    final r = await InvoiceHistoryRepository.instance
        .fetch(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _invoices = r.invoices;
      _message = r.statusCode == 0 ? '' : r.statusMessage;
    });
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              'Total Invoices : ${_invoices.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_invoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No invoices found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _invoices.length,
      itemBuilder: (cardCtx, i) {
        final inv = _invoices[i];
        return _InvoiceCard(
          invoice: inv,
          shareVisible: SessionService.instance.shareOption,
          onPrint: () => _printInvoice(inv),
          onShare: (btnCtx) => _shareInvoice(btnCtx, inv),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
        ),
      ),
      title: const Text('INVOICE HISTORY',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final InvoiceRecord invoice;
  final bool shareVisible;   // Android hides Share when share_option == "0"
  final VoidCallback onPrint;
  /// Receives the share button's own context — needed to anchor the iOS sheet.
  final void Function(BuildContext) onShare;
  const _InvoiceCard({
    required this.invoice,
    required this.shareVisible,
    required this.onPrint,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Invoice number header row (grey background)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFE0E0E0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Text('Invoice Number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1))),
                const Spacer(),
                Text(invoice.billingId,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1B3A7A))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('Invoice Date', invoice.billDate),
                _row('Due Date', invoice.dueDate),
                _row('Bill Number', invoice.billNo),
                _row('Bill Amount', '₹${invoice.billAmount}'),
                _row('Tax Amount', '₹${invoice.taxAmount}'),
                _row('Pending Amount', '₹${invoice.pendingAmount}'),
                _row('Package Name', invoice.packageName),
                _row('Total Amount', '₹${invoice.totalAmount}', isTotal: true),
                const SizedBox(height: 8),
                // Print + Share (Android row_invoice: emailInvoice / whatsupInvoice).
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (AppConfig.bluetoothPrintingEnabled)
                      GestureDetector(
                        onTap: onPrint,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: Colors.red.shade50, shape: BoxShape.circle),
                          child: const Icon(Icons.print, color: Colors.red, size: 20),
                        ),
                      ),
                    if (shareVisible) ...[
                      const SizedBox(width: 12),
                      // Builder so the tap handler gets THIS button's context —
                      // a ListView.builder itemBuilder context resolves to the
                      // enclosing sliver, which cannot anchor the iOS share sheet.
                      Builder(
                        builder: (btnCtx) => GestureDetector(
                          onTap: () => onShare(btnCtx),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                                color: Color(0xFF1565C0), shape: BoxShape.circle),
                            child: const Icon(Icons.share,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool isTotal = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: isTotal ? const Color(0xFF0D47A1) : const Color(0xFF5B7BAE),
                        fontWeight: isTotal ? FontWeight.w800 : FontWeight.w400)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}
