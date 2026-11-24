import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/data/customer.dart';
import '../../core/theme/theme_constants.dart';
import '../../core/widgets/premium_dialog.dart';
import '../dashboard/data/complaints_repository.dart';
import 'data/complaint_option.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NEW COMPLAINT (Customer Details → Create Complaints)  — SIMPLE mode.
//   • Category + Assigned-employee dropdowns load from the real APIs
//     (complaintCategories / assignedemployeedetails) — never hardcoded.
//   • GPS lat/long captured if available, else 0.0 (mirrors Android).
//   • Submit calls createComplaint; handles statusCode 0/1/2/null.
//   • Validates: category ≠ Select, employee ≠ Select (description optional,
//     like Android).
//   • Never crashes on null / missing fields / malformed / network / timeout.
// The "Employee / Service" dropdown is kept for visual parity with Android (it is
// cosmetic there — it does not affect the request).
// ─────────────────────────────────────────────────────────────────────────────
class CreateComplaintScreen extends StatefulWidget {
  final Customer customer;
  const CreateComplaintScreen({super.key, required this.customer});

  @override
  State<CreateComplaintScreen> createState() => _CreateComplaintScreenState();
}

class _CreateComplaintScreenState extends State<CreateComplaintScreen> {
  bool _loading = true;
  bool _submitting = false;

  List<ComplaintOption> _categories = const [ComplaintOption.select];
  List<ComplaintOption> _employees = const [ComplaintOption.select];
  ComplaintOption _category = ComplaintOption.select;
  ComplaintOption _employee = ComplaintOption.select;

  // Cosmetic (parity with Android — no backend effect).
  String _assignTo = 'Employee';
  final _assignOptions = const ['Employee', 'Service'];

  final _descController = TextEditingController();

  String _lat = '0.0';
  String _long = '0.0';

  /// The numeric customer_id used by every complaint API (Android `altCustId`).
  String get _customerId => widget.customer.lcoCustomerId.isNotEmpty
      ? widget.customer.lcoCustomerId
      : widget.customer.altCustomerId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // GPS is best-effort and must never block the form.
    _loadLocation();
    final repo = ComplaintsRepository.instance;
    final results = await Future.wait([
      repo.fetchComplaintCategories(),
      repo.fetchAssignedEmployees(_customerId),
    ]);
    if (!mounted) return;
    setState(() {
      _categories = results[0].options;
      _employees = results[1].options;
      _loading = false;
    });
    // C8 / Android Complaint_NewComplaint_Fragment ComplaintCategoriesList
    // (:452-539) then ComplaintAssigned (:714-788): each list shows its own
    // failure message; the screen stays open.
    await _showListLoadFailure(results[0], 'Categories not Loaded');
    if (!mounted) return;
    await _showListLoadFailure(results[1], 'asigned employees not Loaded');
  }

  /// C8: Android's message when a dropdown fails to load. status 1 → toast
  /// "{message}: {notLoaded}"; status 2 → toast "{message}: Contact Support";
  /// failed call (Android's null response) → "Server is Un reachable!" dialog
  /// (OK closes it). Any other status shows nothing (Android).
  Future<void> _showListLoadFailure(
      ComplaintOptionsResult r, String notLoaded) async {
    if (r.statusCode == 1) {
      showPremiumSnackBar(context, '${r.statusMessage}: $notLoaded',
          isError: true);
    } else if (r.statusCode == 2) {
      showPremiumSnackBar(context, '${r.statusMessage}: Contact Support',
          isError: true);
    } else if (r.statusCode == 3) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Server is Un reachable!'),
          content: const Text(
              'Please check your Internet connection and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        _lat = pos.latitude.toString();
        _long = pos.longitude.toString();
      }
    } catch (_) {
      // keep 0.0 / 0.0
    }
  }

  Future<void> _register() async {
    if (_category.id == 0) {
      _snack('Please select a complaint category');
      return;
    }
    if (_employee.id == 0) {
      _snack('Please select an employee/service');
      return;
    }
    // Issue 4 / Android Complaint_NewComplaint_Fragment :229: the description
    // is optional — Android checks only category and employee, then sends
    // the text as typed (empty allowed).
    if (_submitting) return;
    setState(() => _submitting = true);
    // C12 / Android Complaint_NewComplaint_Fragment :1060: non-cancellable
    // "Registering Complaint,   Please wait..." (Back ignored). Closed exactly
    // once; createComplaint itself never throws.
    showPremiumLoading(context,
        message: 'Registering Complaint,   Please wait...', canPop: false);
    var loaderOpen = true;
    void closeLoader() {
      if (loaderOpen && mounted) {
        loaderOpen = false;
        Navigator.of(context).pop();
      }
    }

    try {
      final result = await ComplaintsRepository.instance.createComplaint(
        customerId: _customerId,
        complaint: _descController.text.trim(),
        category: _category.id,
        assignedTo: _employee.id,
        latitude: _lat,
        longitude: _long,
      );
      if (!mounted) return;
      closeLoader();
      if (result.isSuccess) {
        _showSuccessDialog();
      } else {
        final msg = result.statusMessage.isNotEmpty
            ? result.statusMessage
            : (result.statusCode == 1
                ? 'Please enter valid details.'
                : result.statusCode == 2
                    ? 'An error occurred. Please contact support.'
                    : 'Server busy or unreachable. Please try again.');
        _showErrorDialog(msg);
      }
    } catch (_) {
      if (mounted) {
        closeLoader();
        _showErrorDialog('Could not connect to server. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
              child: Text('Complaint Registered',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Category', _category.name),
            const SizedBox(height: 6),
            _row('Assigned To', _employee.name),
            const SizedBox(height: 6),
            _row('Description', _descController.text.trim()),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx); // dialog
              Navigator.pop(context, true); // screen → caller refreshes
            },
            child:
                const Text('OK', style: TextStyle(fontWeight: FontWeight.w800)),
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
              child: Text('Could Not Register',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Text(message,
            style: const TextStyle(fontSize: 14, color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B7BAE))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D47A1))),
        ),
      ],
    );
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  // Theme-aware frame (page, title bar, spinner). Theme 1 keeps exactly the
  // previous blue/white; the white card is unchanged in both themes.
  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: _buildAppBar(context, t),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.loadingColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _label('Complaint Category'),
                    const SizedBox(height: 10),
                    _optionDropdown(
                      value: _category,
                      items: _categories,
                      onChanged: (v) => setState(
                          () => _category = v ?? ComplaintOption.select),
                    ),
                    const SizedBox(height: 20),

                    _label('Assign To'),
                    const SizedBox(height: 10),
                    _stringDropdown(
                      value: _assignTo,
                      items: _assignOptions,
                      onChanged: (v) =>
                          setState(() => _assignTo = v ?? 'Employee'),
                    ),
                    const SizedBox(height: 20),

                    _label('Select Employee/Service'),
                    const SizedBox(height: 10),
                    _optionDropdown(
                      value: _employee,
                      items: _employees,
                      onChanged: (v) => setState(
                          () => _employee = v ?? ComplaintOption.select),
                    ),
                    const SizedBox(height: 20),

                    _label('Description'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descController,
                      enabled: !_submitting,
                      // The app theme's enabledBorder is a 20%-alpha line
                      // (near invisible on white), so this field sets its own
                      // visible borders.
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF9CA3AF), width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF0D47A1), width: 1.6),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _submitting ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE0E0E0),
                        foregroundColor: const Color(0xFF0D47A1),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Color(0xFF0D47A1)),
                            )
                          : const Text('Register',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0D47A1)));

  Widget _dropdownBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _optionDropdown({
    required ComplaintOption value,
    required List<ComplaintOption> items,
    required ValueChanged<ComplaintOption?> onChanged,
  }) {
    return _dropdownBox(
      child: DropdownButton<ComplaintOption>(
        value: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
        items: items
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                ))
            .toList(),
        onChanged: _submitting ? null : onChanged,
      ),
    );
  }

  Widget _stringDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return _dropdownBox(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(fontSize: 14))))
            .toList(),
        onChanged: _submitting ? null : onChanged,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AppThemeConst t) {
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
          child: Icon(Icons.arrow_back_ios_new,
              size: 16, color: t.backBtnIcon),
        ),
      ),
      title: Text('NEW COMPLAINT',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.appBarFg,
              letterSpacing: 1)),
    );
  }
}
