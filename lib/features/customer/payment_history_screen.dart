import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/customer.dart';
import '../../core/services/real_bluetooth_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/settings_store.dart';
import '../payment/printer_launcher.dart';
import 'data/payment_history_repository.dart';

/// Payment History — real `getPaymentHistorylist` (Android `getpayhist()`).
/// Sends the system customer id (`altCustomerId`, = Android `altCustId`).
class PaymentHistoryScreen extends StatefulWidget {
  final Customer customer;
  const PaymentHistoryScreen({super.key, required this.customer});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  bool _loading = true;
  String _message = '';
  List<PaymentRecord> _payments = const [];

  // Thermal print for the single top "Print" button (Android viewpayhistory_printbtn).
  final RealBluetoothService _printerService = RealBluetoothService();

  @override
  void initState() {
    super.initState();
    _load();
    SettingsStore.instance.load();
  }

  @override
  void dispose() {
    _printerService.disconnectPrinter();
    super.dispose();
  }

  // ── Whole-history print (Android offline_report=6) ────────────────────────
  String _timestamp() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wd[n.weekday - 1]} ${mo[n.month - 1]} ${two(n.day)} ${n.year} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  String _padR(String s, int w) =>
      s.length >= w ? s.substring(0, w) : s.padRight(w);
  String _padL(String s, int w) =>
      s.length >= w ? s.substring(0, w) : s.padLeft(w);

  /// The whole payment history as one report — 1:1 with BluetoothChatService
  /// "PAYMENT HISTORY" (offline_report=6, :875-890): title, customer info, then a
  /// PAID DATE / PAID FOR / AMOUNT table of every row. No printer header/footer
  /// (Android omits them for this report).
  List<String> _buildHistoryPrintLines(ReceiptFormat fmt) {
    final c = widget.customer;
    final sep = fmt.sep;
    final lcoId = _payments.isNotEmpty ? _payments.first.customNumber : '';
    final lines = <String>[
      sep, '         PAYMENT HISTORY       ',
      sep, _timestamp(), sep,
      'CUSTOMER NAME     :${c.name}',
      'CUSTOMER ADDRESS  :${c.address}',
      'LCO CUSTOMER ID   :$lcoId',
      sep,
      'PAID DATE   PAID FOR   AMOUNT',
      sep,
    ];
    for (final p in _payments) {
      // 12 (date) + 4 (paid-for) + 12 (amount, right) = 28 cols (Android :881).
      lines.add(_padR(p.paidDateDisplay, 12) +
          _padR(p.billForMonth, 4) +
          _padL(p.amount, 12));
    }
    lines.add(sep);
    return lines;
  }

  Future<void> _printHistory() {
    if (_payments.isEmpty) return Future.value();
    return launchThermalPrint(
      context: context,
      printerService: _printerService,
      buildLines: _buildHistoryPrintLines,
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // System customer id = Android `altCustId` = JSON `customer_id` (Flutter
    // `lcoCustomerId`). `alt_cust_id` is only a display number — don't use it.
    final r = await PaymentHistoryRepository.instance
        .fetch(widget.customer.lcoCustomerId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _payments = r.payments;
      // statusCode 1 (no records) / 3 (transport) → message for empty state.
      _message = r.statusCode == 0 ? '' : r.statusMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Total count bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF0D47A1),
            child: Text(
              'Total Payments - ${_payments.length}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),

          // Customer summary
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _row('Customer Name', widget.customer.name),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _row('Address',
                    widget.customer.address.isEmpty ? 'N/A' : widget.customer.address),
                const Divider(
                    height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
                _row(
                    'Mobile No.',
                    widget.customer.primaryMobileNumber.isEmpty
                        ? 'N/A'
                        : widget.customer.primaryMobileNumber),
              ],
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
    if (_payments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _message.isEmpty ? 'No payments found' : _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _payments.length,
      itemBuilder: (_, i) {
        final rec = _payments[i];
        // Android: tap a payment row → PaymentHistoryDetailView (print + share).
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentHistoryDetailScreen(
                customer: widget.customer,
                record: rec,
              ),
            ),
          ),
          child: _PaymentCard(
            record: rec,
            index: i + 1,
            total: _payments.length,
          ),
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
          child: const Icon(Icons.arrow_back_ios_new,
              size: 16, color: Colors.white),
        ),
      ),
      title: const Text('PAYMENT HISTORY',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1)),
      actions: [
        // Single top Print button (Android viewpayhistory_printbtn) — prints the
        // WHOLE payment history as one report.
        IconButton(
          onPressed: _payments.isEmpty ? null : _printHistory,
          icon: const Icon(Icons.print, color: Colors.white, size: 22),
          tooltip: 'Print payment history',
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF5B7BAE))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D47A1))),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentRecord record;
  final int index;
  final int total;
  const _PaymentCard({
    required this.record,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    // Fields mirror Android's `paymenthistory_items` row.
    final rows = <MapEntry<String, String>>[
      MapEntry('Payment Date', record.paidDateDisplay),
      MapEntry('Amount Paid', '₹${record.amount}'),
      MapEntry('Payment Type', record.paymentTypeLabel),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text('$index / $total',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B7BAE),
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          ...List.generate(rows.length, (i) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(rows[i].key,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF5B7BAE))),
                      ),
                      Expanded(
                        child: Text(rows[i].value,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D47A1))),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1)
                  const Divider(
                      height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT HISTORY DETAIL — Android PaymentHistoryDetailView (tap a row → detail
// with Print + Share). Share hidden when share_option == "0".
// ─────────────────────────────────────────────────────────────────────────────
class PaymentHistoryDetailScreen extends StatefulWidget {
  final Customer customer;
  final PaymentRecord record;
  const PaymentHistoryDetailScreen({
    super.key,
    required this.customer,
    required this.record,
  });

  @override
  State<PaymentHistoryDetailScreen> createState() =>
      _PaymentHistoryDetailScreenState();
}

class _PaymentHistoryDetailScreenState
    extends State<PaymentHistoryDetailScreen> {
  final RealBluetoothService _printerService = RealBluetoothService();

  @override
  void initState() {
    super.initState();
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

  /// Android's `new Date().toString()` order: "EEE MMM dd yyyy HH:mm:ss".
  String _timestamp() {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wd[n.weekday - 1]} ${mo[n.month - 1]} ${two(n.day)} ${n.year} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  String get _address {
    final c = widget.record.city.trim();
    final s = widget.record.state.trim();
    return [c, s].where((e) => e.isNotEmpty).join(',');
  }

  /// Thermal print — 1:1 with BluetoothChatService "PAYMENT HISTORY DETAIL"
  /// (:1544-1560). CRF line omitted (Flutter payment model carries no CRF).
  List<String> _buildPrintLines(ReceiptFormat fmt) {
    final r = widget.record;
    final s = SettingsStore.instance;
    final sep = fmt.sep;
    return [
      sep, s.header1, sep, s.header2,
      sep, '      PAYMENT HISTORY DETAIL     ',
      sep, _timestamp(), sep,
      'LCO CUST Id      :${r.customNumber}',
      'CUSTOMER NAME    :${widget.customer.name}',
      'ADDRESS          :$_address',
      'MOBILE NO        :${r.mobileNumber}',
      'PAID DATE        :${r.paidDateDisplay}',
      'RECEIPT NO       :${r.receiptNumber}',
      'BILL FOR         :${r.billForMonth}',
      'PAID AMOUNT      :${r.amount}',
      'BILL AMOUNT      :${r.billAmount}',
      'TAX AMOUNT       :${r.taxAmount}',
      'DUE AMOUNT       :${r.pending}',
      'PAYMENT TYPE     :${r.paymentTypeLabel}',
      sep, s.footer1, sep, s.footer2, sep,
    ];
  }

  /// Share PDF — 1:1 with PaymentHistoryDetailView.ShareInvoice (:250-292)
  /// (header/footer only when non-empty; two separators before the footer).
  List<String> _buildShareLines() {
    final r = widget.record;
    final s = SettingsStore.instance;
    final lines = <String>[_sep];
    if (s.header1.isNotEmpty) lines..add(s.header1)..add(_sep);
    if (s.header2.isNotEmpty) lines..add(s.header2)..add(_sep);
    lines
      ..add(' PAYMENT HISTORY DETAIL ')
      ..add(_sep)
      ..add(_timestamp())
      ..add(_sep);
    lines.add('LCO CUSTOMER ID :${r.customNumber}');
    lines.add('CUSTOMER NAME   :${widget.customer.name}');
    lines.add('ADDRESS         :$_address');
    lines.add('MOBILE NO       :${r.mobileNumber}');
    lines.add('PAID DATE       :${r.paidOn}');
    lines.add('RECEIPT NO      :${r.receiptNumber}');
    lines.add('BILL FOR        :${r.billForMonth}');
    lines.add('PAID AMOUNT     :${r.amount}');
    lines.add('BILL AMOUNT     :${r.billAmount}');
    lines.add('TAX AMOUNT      :${r.taxAmount}');
    lines.add('DUE AMOUNT      :${r.pending}');
    lines.add('PAYMENT TYPE    :${r.paymentTypeLabel}');
    lines..add(_sep)..add(_sep); // Android appends two separators here
    if (s.footer1.isNotEmpty) lines..add(s.footer1)..add(_sep);
    if (s.footer2.isNotEmpty) lines..add(s.footer2)..add(_sep);
    return lines;
  }

  Future<void> _print() => launchThermalPrint(
        context: context,
        printerService: _printerService,
        buildLines: _buildPrintLines,
      );

  Future<void> _share() async {
    try {
      final lines = _buildShareLines();
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
      final path = '${dir.path}/${safe.isEmpty ? 'payment' : safe}.pdf';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)],
          subject: 'Payment History of ${widget.customer.name}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final rows = <MapEntry<String, String>>[
      MapEntry('LCO Customer ID', r.customNumber.isEmpty ? 'NA' : r.customNumber),
      MapEntry('Customer Name', widget.customer.name),
      MapEntry('Address', _address.isEmpty ? 'NA' : _address),
      MapEntry('Mobile No.', r.mobileNumber.isEmpty ? 'NA' : r.mobileNumber),
      MapEntry('Paid Date', r.paidDateDisplay),
      MapEntry('Receipt No.', r.receiptNumber.isEmpty ? 'NA' : r.receiptNumber),
      MapEntry('Bill For', r.billForMonth),
      MapEntry('Paid Amount', '₹${r.amount}'),
      MapEntry('Bill Amount', '₹${r.billAmount}'),
      MapEntry('Tax Amount', r.taxAmount),
      MapEntry('Due Amount', r.pending),
      MapEntry('Payment Type', r.paymentTypeLabel),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: AppBar(
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
            child: const Icon(Icons.arrow_back_ios_new,
                size: 16, color: Colors.white),
          ),
        ),
        title: const Text('PAYMENT DETAILS',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(rows[i].key,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF5B7BAE))),
                      ),
                      Expanded(
                        child: Text(rows[i].value,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D47A1))),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1)
                  const Divider(
                      height: 1, thickness: 0.5, color: Color(0xFFE5E7EB)),
              ],
              const SizedBox(height: 18),
              // Print + Share — Share hidden when share_option == "0".
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DetailActionButton(
                      icon: Icons.print,
                      label: 'Print',
                      color: const Color(0xFF0D47A1),
                      onTap: _print),
                  if (SessionService.instance.shareOption) ...[
                    const SizedBox(width: 20),
                    _DetailActionButton(
                        icon: Icons.share,
                        label: 'Share',
                        color: const Color(0xFF1565C0),
                        onTap: _share),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DetailActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
