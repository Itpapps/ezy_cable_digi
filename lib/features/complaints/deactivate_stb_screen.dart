import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/data/customer.dart';
import '../../core/widgets/premium_dialog.dart';
import '../packages/data/customer_box.dart';
import '../packages/data/package.dart';
import '../packages/data/package_operations_repository.dart';

// DeactivateStbScreen — STB deactivation (mirrors Android Deactivatestb_Frag_New).
// Boxes via gcb; reasons via gdr (SOAP). Branches on the VERIFIED magic
// reasonId==17 ("Unpaid Customer") → db (SOAP deactivateBox); all other reasons →
// ds (REST deactivateSTB). GPS lat/lang with 0.0 fallback. Double-submit guarded;
// never crashes on null/empty/error.
class DeactivateStbScreen extends StatefulWidget {
  final Customer customer;
  const DeactivateStbScreen({super.key, required this.customer});

  @override
  State<DeactivateStbScreen> createState() => _DeactivateStbScreenState();
}

class _DeactivateStbScreenState extends State<DeactivateStbScreen> {
  bool _loading = true;
  bool _error = false;
  String _message = '';
  bool _submitting = false;

  List<CustomerBox> _boxes = const [];
  CustomerBox? _selectedBox;

  List<DeactivateReason> _reasons = const [DeactivateReason(0, 'Choose Reason')];
  int _reasonId = 0;

  String _lat = '0.0';
  String _lang = '0.0';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    final repo = PackageOperationsRepository.instance;
    final boxesFuture = repo.getCustomerBoxes(widget.customer.lcoCustomerId);
    final reasonsFuture = repo.getStbDeactivateReasons();
    _loadLocation(); // fire-and-forget GPS (0.0 fallback)
    final boxesRes = await boxesFuture;
    final reasonsRes = await reasonsFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _reasons = [
        const DeactivateReason(0, 'Choose Reason'),
        // Defensive: drop any server "0" to avoid a duplicate dropdown value.
        ...reasonsRes.reasons.where((r) => r.reasonId != 0),
      ];
      _reasonId = 0;
      if (boxesRes.statusCode == 0 && boxesRes.boxes.isNotEmpty) {
        _boxes = boxesRes.boxes;
        // C-B2 / Android Deactivatestb_Frag_New :259-261: the box list starts
        // on "Select" — no box is chosen until the user picks one (the first
        // box must never be deactivated by default).
        _selectedBox = null;
        _error = false;
      } else if (boxesRes.statusCode == 3) {
        _boxes = const [];
        _selectedBox = null;
        _error = true;
        _message = boxesRes.statusMessage;
      } else {
        _boxes = const [];
        _selectedBox = null;
        _error = true;
        _message = 'No Boxes For this Customer';
      }
    });
    // C8 / Android Deactivatestb_Frag_New. Boxes (packageoperations :307-343):
    // status 1 → "No Details Found!" + server message, OK closes the screen
    // (:317; Back only closes the dialog); failed call → "Failed." toast.
    if (boxesRes.statusCode == 1) {
      final ok =
          await _loadFailedDialog('No Details Found!', boxesRes.statusMessage);
      if (!mounted) return;
      if (ok == true) {
        Navigator.pop(context);
        return;
      }
    } else if (boxesRes.statusCode == 3) {
      showPremiumSnackBar(context, 'Failed.', isError: true);
    }
    // Reasons (Deactivation_Reasons.onPostExecute :491-545): status 1 →
    // "No Records Found!"; status 2 → "{message}: Contact Support" toast;
    // failed call (Android's null response) → "Server is busy or not
    // reachable!". The screen stays. Any other status shows nothing (Android).
    if (reasonsRes.statusCode == 1) {
      await _loadFailedDialog('No Records Found!', reasonsRes.statusMessage);
    } else if (reasonsRes.statusCode == 2) {
      showPremiumSnackBar(
          context, '${reasonsRes.statusMessage}: Contact Support',
          isError: true);
    } else if (reasonsRes.statusCode == 3) {
      await _loadFailedDialog(
          'Server is busy or not reachable!', 'Please try again after sometime');
    }
  }

  /// C8: Android's load-failure AlertDialog — cancelable (Back / outside tap
  /// close it and return null); OK returns true.
  Future<bool?> _loadFailedDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        _lat = pos.latitude.toString();
        _lang = pos.longitude.toString();
      }
    } catch (_) {
      // keep 0.0 / 0.0
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // C-B2: the form needs boxes, not a selected box ("Select" is valid).
    if (_error || _boxes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off_rounded, color: Colors.white70, size: 44),
              const SizedBox(height: 12),
              Text(_message.isEmpty ? 'Could not load' : _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D47A1),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Please select STB',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D47A1))),
                ),
                Expanded(child: _boxDropdown()),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('Please select a reason',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D47A1))),
                ),
                Expanded(child: _reasonDropdown()),
              ],
            ),
            const SizedBox(height: 30),
            // Android parity (Deactivatestb_Frag_New.java:160-165): the Deactivate
            // action is shown only when the selected box is Active (box_status=="1")
            // and hidden otherwise. Mirrors Android's setVisibility(INVISIBLE) —
            // layout space is preserved (maintainSize) so nothing shifts. Pure
            // presentation: _submit, APIs, dialogs and navigation are unchanged.
            Visibility(
              visible: _selectedBox?.isActive ?? false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('DEACTIVATE',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownBox({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _boxDropdown() {
    const selectLabel = Text('Select',
        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13));
    return _dropdownBox(
      // C-B2 / Android :259-261 + :153-166: "Select" (no box) is the first
      // item and the starting value; choosing it again clears the box, which
      // hides DEACTIVATE (Android stat "Select" → INVISIBLE).
      child: DropdownButton<CustomerBox?>(
        value: _selectedBox,
        isDense: true,
        isExpanded: true,
        hint: selectLabel, // shown while no box is chosen
        icon: const Icon(Icons.keyboard_arrow_down),
        items: [
          const DropdownMenuItem<CustomerBox?>(
            value: null,
            child: selectLabel,
          ),
          ..._boxes.map((b) => DropdownMenuItem<CustomerBox?>(
                value: b,
                child: Text(b.boxNumber.isEmpty ? b.vcNumber : b.boxNumber,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              )),
        ],
        onChanged: (b) => setState(() => _selectedBox = b),
      ),
    );
  }

  Widget _reasonDropdown() {
    return _dropdownBox(
      child: DropdownButton<int>(
        value: _reasonId,
        isDense: true,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down),
        items: _reasons
            .map((r) => DropdownMenuItem(
                  value: r.reasonId,
                  child: Text(r.reasonName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        onChanged: (v) => setState(() => _reasonId = v ?? 0),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return; // double-submit guard
    // C-B2 / Android :184-190: the reason is checked first, then the box.
    if (_reasonId == 0) {
      _snack('Select Reason to Deactivate');
      return;
    }
    final box = _selectedBox;
    if (box == null) {
      _snack('Select Box to Deactivate');
      return;
    }

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deactivate STB',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Do you want to Deactivate STB?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    // Production sends the box's customer_id (fall back to lcoCustomerId if empty).
    final customerId = box.customerId.isNotEmpty
        ? box.customerId
        : widget.customer.lcoCustomerId;
    final serial = box.boxNumber;

    setState(() => _submitting = true);
    // C12 / Android Deactivatestb_Frag_New: non-cancellable loader (Back
    // ignored) — "Deactivation in progress...,   Please wait..." for the SOAP
    // path (reason 17, :559), "Loading...Please wait..." for REST (:704). Both
    // requests never throw (status 3 on timeout / transport).
    showPremiumLoading(context,
        message: _reasonId == 17
            ? 'Deactivation in progress...,   Please wait...'
            : 'Loading...Please wait...',
        canPop: false);
    final repo = PackageOperationsRepository.instance;
    // VERIFIED branch: reasonId 17 ("Unpaid Customer") → db (SOAP); else → ds (REST).
    final PackageWriteResult r = _reasonId == 17
        ? await repo.deactivateBoxSoap(
            reasonId: _reasonId,
            serialNumber: serial,
            boxId: box.boxId,
            customerId: customerId,
            lat: _lat,
            lang: _lang)
        : await repo.deactivateStbRest(
            reasonId: _reasonId,
            serialNumber: serial,
            boxId: box.boxId,
            customerId: customerId,
            lat: _lat,
            lang: _lang);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the loader
    setState(() => _submitting = false);

    // Production response handling:
    //   ds (REST): 0 → "Success!" pop; 1 → "No Details Found!" pop.
    //   db (SOAP): 0 → "Success!" pop; 1 → "No Details Found!" STAY; 2 → toast;
    //              null/transport → "Server busy" dialog, stay.
    if (r.statusCode == 0) {
      await _resultDialog('Success!', r.statusMessage);
      if (!mounted) return;
      Navigator.pop(context, true); // back to previous screen
    } else if (r.statusCode == 1) {
      await _resultDialog('No Details Found!', r.statusMessage);
      if (!mounted) return;
      if (_reasonId != 17) Navigator.pop(context, true); // ds pops; db stays
    } else if (r.statusCode == 2) {
      _snack('${r.statusMessage}: Contact Support');
    } else {
      await _resultDialog(
          'Server is busy or Un-reachable!',
          r.statusMessage.isEmpty
              ? 'Please try again after sometime'
              : r.statusMessage);
    }
  }

  Future<void> _resultDialog(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message.isEmpty ? '-' : message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFF0D47A1), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
      title: const Text('DEACTIVATE STB',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1)),
    );
  }
}
