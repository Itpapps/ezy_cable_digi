import 'package:flutter/material.dart';
import '../../core/theme/theme_constants.dart';
import '../../features/dashboard/widgets/complaint_card.dart';
import '../dashboard/data/complaints_repository.dart';
import '../dashboard/data/open_complaint.dart';
import 'data/complaint_option.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OPEN COMPLAINTS (bottom-nav Complaints tab)
// Real `getopencomplaintslist` data. Tapping "Update Status" opens the real
// closeComplaint flow with the correct alt_cust_id / complaint_id / tkt_number,
// and the list refetches after a successful update. Defensive: loading / error /
// empty states; never crashes.
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  bool _loading = true;
  bool _error = false;
  String _message = '';
  List<OpenComplaint> _complaints = const [];

  // Dealer/business dropdown — Android parity (OpenComplaints_Fragment "Dealer"
  // spinner from getMappedDealers). "Choose" (id 0) is the default, like Android.
  List<ComplaintOption> _dealers = const [ComplaintOption(0, 'Choose')];
  ComplaintOption _selectedDealer = const ComplaintOption(0, 'Choose');
  bool _dealersLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  // Android: onCreateView runs getMappedDealers first; the spinner's default
  // "Choose"(0) selection then triggers the complaint fetch (dealer_id 0).
  Future<void> _loadDealers() async {
    final dealers = await ComplaintsRepository.instance.fetchMappedDealers();
    if (!mounted) return;
    setState(() {
      _dealers = dealers;
      _selectedDealer = dealers.first; // "Choose" (id 0)
      _dealersLoading = false;
    });
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    // Android Complaints tab sends the selected dealer_id + from_dashboard "0"
    // (the dashboard card uses dealer_id 0 + "1", left unchanged).
    final r = await ComplaintsRepository.instance.fetchOpenComplaints(
      dealerId: _selectedDealer.id,
      fromDashboard: '0',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.statusCode == 0) {
        _complaints = r.complaints; // may be empty → empty-state
        _error = false;
      } else if (r.statusCode == 1) {
        _complaints = const []; // no records → empty-state
        _error = false;
      } else {
        _complaints = const [];
        _error = true; // status 2/3 → error message
        _message = r.statusMessage;
      }
    });
  }

  ComplaintStatus _mapStatus(String s) {
    final u = s.toUpperCase();
    if (u.contains('PROCESS') || u.contains('PROGRESS')) {
      return ComplaintStatus.inProcess;
    }
    return ComplaintStatus.assigned;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: t.appBarBorderColor, width: 1)),
        centerTitle: true,
        // This screen is the dashboard's "Complaints" tab body (not a pushed
        // route), so it must NOT show a back arrow — popping here would pop the
        // dashboard route itself and crash. Navigation is via the bottom nav.
        automaticallyImplyLeading: false,
        title: Text(
          'OPEN COMPLAINTS',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: t.appBarFg),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh, color: t.appBarFg),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Dealer dropdown — Android parity (OpenComplaints "Dealer" spinner)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dealer',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.subtitleText)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: (_dealersLoading || _loading)
                      ? null
                      : () async {
                          final result = await _showDealerDialog(t);
                          if (result == null || result == _selectedDealer) return;
                          setState(() => _selectedDealer = result);
                          _load();
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: t.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.inputBorderColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDealer.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.cardBodyText),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            color: t.subtitleText),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Count badge (real) ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: t.accent.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Total: ${_complaints.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: t.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── List / states ────────────────────────────────────────────────
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildBody(AppThemeConst t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.loadingColor));
    }
    if (_error) {
      return _message_(
        Icons.error_outline_rounded,
        _message.isEmpty ? 'Could not load complaints' : _message,
      );
    }
    if (_complaints.isEmpty) {
      return _message_(Icons.check_circle_outline, 'No open complaints');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _complaints.length,
        itemBuilder: (_, i) {
          final c = _complaints[i];
          return ComplaintCard(
            complaintId: c.tktNumber.isEmpty ? c.complaintId : c.tktNumber,
            name: c.name.isEmpty ? 'NA' : c.name,
            description: c.description.isEmpty ? c.des : c.description,
            status: _mapStatus(c.status),
            statusLabel: c.status.isEmpty ? null : c.status,
            altCustomerId: c.altCustId,
            realComplaintId: c.complaintId,
            onUpdated: _load,
          );
        },
      ),
    );
  }

  Future<ComplaintOption?> _showDealerDialog(AppThemeConst t) {
    return showGeneralDialog<ComplaintOption>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dealer',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width * 0.85,
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 360),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _dealers.length,
                  itemBuilder: (_, i) {
                    final dealer = _dealers[i];
                    final isSelected = dealer == _selectedDealer;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, dealer),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        color: isSelected
                            ? const Color(0xFF0D47A1).withValues(alpha: 0.06)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                dealer.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check,
                                  size: 20, color: Color(0xFF0D47A1)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _message_(IconData icon, String text) {
    final t = AppThemeConst.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: t.emptyStateBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: t.emptyStateIconColor, size: 38),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: t.bodyText, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
