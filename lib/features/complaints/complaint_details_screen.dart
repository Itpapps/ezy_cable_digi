import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_constants.dart';
import '../dashboard/data/complaints_repository.dart';
import '../../core/widgets/premium_dialog.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COMPLAINT DETAILS SCREEN
// Phase 1: real implementation.
//   • Loads status LOV from `complaintTypes` API on open (fallback list if it
//     fails so the screen is always usable).
//   • Calls `closeComplaint` on submit with real altCustomerId, realComplaintId,
//     ticketNumber, status and comment.
//   • Handles statusCode 0 (success), 1 (invalid details), 2 (contact support),
//     3 / null / network / timeout / SOAP errors.
//   • Success dialog → pops with `true` so the caller can refresh the dashboard.
//   • Failure dialog → keeps the screen open so the user can correct and retry.
//   • Never crashes on null / missing fields / malformed responses.
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintDetailsScreen extends StatefulWidget {
  /// Display ticket number (tkt_number); shown as "Ticket No." in the UI and
  /// also sent as `ticketNumber` in the closeComplaint API call.
  final String complaintId;
  final String customerName;
  final String complaint;
  final String currentStatus;

  /// alt_cust_id from the complaint record — required by the closeComplaint API.
  /// Defaults to '' so existing call-sites that pre-date Phase 1 still compile.
  final String altCustomerId;

  /// Numeric complaint_id from the complaint record — required by the
  /// closeComplaint API. Defaults to '' for backward compatibility.
  final String realComplaintId;

  const ComplaintDetailsScreen({
    super.key,
    required this.complaintId,
    required this.customerName,
    required this.complaint,
    required this.currentStatus,
    this.altCustomerId = '',
    this.realComplaintId = '',
  });

  @override
  State<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends State<ComplaintDetailsScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<String> _statusOptions = kDefaultComplaintStatuses;
  String _selectedStatus = 'Select';
  bool _loadingStatuses = true;
  bool _updating = false;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  // ── API: load status LOV ───────────────────────────────────────────────────
  Future<void> _loadStatuses() async {
    try {
      final statuses =
          await ComplaintsRepository.instance.fetchComplaintStatuses();
      if (!mounted) return;
      setState(() {
        _statusOptions = statuses;
        // Pre-select the current status if the API returned it.
        final upper = widget.currentStatus.toUpperCase();
        if (_statusOptions.contains(upper)) {
          _selectedStatus = upper;
        } else if (_statusOptions.contains(widget.currentStatus)) {
          _selectedStatus = widget.currentStatus;
        } else {
          _selectedStatus = 'Select';
        }
        _loadingStatuses = false;
      });
    } catch (_) {
      // Even the fallback failed for some unexpected reason — still show safely.
      if (!mounted) return;
      setState(() {
        _statusOptions = kDefaultComplaintStatuses;
        _loadingStatuses = false;
      });
    }
  }

  // ── API: update / close complaint ──────────────────────────────────────────
  Future<void> _update() async {
    if (_selectedStatus == 'Select') {
      _showErrorDialog('Please select a complaint status before updating.');
      return;
    }
    if (_updating) return;
    setState(() => _updating = true);
    // Android ComplaintHistory_Others_Fragment :452: a non-cancellable
    // "Updating Complaint,   Please wait..." while the update runs. It also
    // keeps the header / bottom bar / drawer from opening another screen
    // meanwhile — the success OK pops THIS screen.
    showPremiumLoading(context,
        message: 'Updating Complaint,   Please wait...', canPop: false);
    var loaderOpen = true;
    void closeLoader() {
      if (!loaderOpen || !mounted) return;
      loaderOpen = false;
      Navigator.of(context).pop();
    }

    try {
      final result = await ComplaintsRepository.instance.closeComplaint(
        altCustomerId: widget.altCustomerId,
        complaintId: widget.realComplaintId,
        ticketNumber: widget.complaintId,
        status: _selectedStatus,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      closeLoader();
      if (result.isSuccess) {
        // statusCode 0 → success
        _showSuccessDialog();
      } else if (result.statusCode == 1) {
        // statusCode 1 → "Enter valid details"
        final msg = result.statusMessage.isNotEmpty
            ? result.statusMessage
            : 'Invalid details. Please check and try again.';
        _showErrorDialog(msg);
      } else if (result.statusCode == 2) {
        // statusCode 2 → "Contact support"
        final msg = result.statusMessage.isNotEmpty
            ? result.statusMessage
            : 'An error occurred. Please contact support.';
        _showErrorDialog(msg);
      } else {
        // statusCode 3 / null / unknown → server busy or unreachable
        final msg = result.statusMessage.isNotEmpty
            ? result.statusMessage
            : 'Server busy or unreachable. Please try again.';
        _showErrorDialog(msg);
      }
    } on TimeoutException {
      if (!mounted) return;
      closeLoader();
      _showErrorDialog('Request timed out. Please try again.');
    } catch (_) {
      if (!mounted) return;
      closeLoader();
      _showErrorDialog('Could not connect to server. Please try again.');
    } finally {
      closeLoader();
      if (mounted) setState(() => _updating = false);
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showSuccessDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Complaint Updated',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogRow('Ticket No.', widget.complaintId),
            const SizedBox(height: 6),
            _dialogRow('New Status', _selectedStatus),
            if (_commentCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _dialogRow('Comment', _commentCtrl.text.trim()),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx); // close dialog
              Navigator.pop(context, true); // return true → caller refreshes
            },
            child: const Text('OK',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Update Failed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5B7BAE),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D47A1),
            ),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware frame (page, title bar). Theme 1 keeps exactly the previous
  // blue/white; the white card is unchanged in both themes.
  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _buildAppBar(context, t),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Customer Name', widget.customerName),
              _divider(),
              _infoRow('Ticket No.', widget.complaintId),
              _divider(),
              _infoRow('Complaint', widget.complaint),
              _divider(),
              _infoRow(
                'Status',
                widget.currentStatus,
                valueColor: const Color(0xFF0D47A1),
                isBold: true,
              ),
              _divider(),

              // ── Complaint Status dropdown ─────────────────────────────────
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Text(
                      'Complaint Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5B7BAE),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loadingStatuses
                        ? const SizedBox(
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFFD1D5DB)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: AppColors.primary,
                                ),
                                items: _statusOptions
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(
                                          s,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0D47A1),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _updating
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          setState(
                                              () => _selectedStatus = v);
                                        }
                                      },
                              ),
                            ),
                          ),
                  ),
                ],
              ),

              _divider(),

              // ── Comment field ─────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 120,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Comment',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B7BAE),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      enabled: !_updating,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D47A1),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter comment...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                        ),
                        border: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // ── Update button ─────────────────────────────────────────────
              Center(
                child: ElevatedButton(
                  onPressed: _updating ? null : _update,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0E0E0),
                    foregroundColor: AppColors.primary,
                    elevation: 0,
                    minimumSize: const Size(140, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _updating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      : const Text(
                          'Update',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, AppThemeConst t) {
    return AppBar(
      backgroundColor: t.appBarBg,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 40, // compact, same as Customer / Payment Details
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque, // whole leading slot stays tappable
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: t.isLight
                ? t.backBtnBg
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
              Icons.arrow_back_ios_new, size: 16, color: t.backBtnIcon),
        ),
      ),
      title: Text(
        'COMPLAINT DETAILS',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: t.appBarFg,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B7BAE),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
                color: valueColor ?? const Color(0xFF0D47A1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 20, color: Color(0xFFE5E7EB));
}
