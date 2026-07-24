import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../complaints/complaint_details_screen.dart';

enum ComplaintStatus { assigned, inProcess }

class ComplaintCard extends StatelessWidget {
  final String complaintId;
  final String name;
  final String description;
  final ComplaintStatus status;
  // Complaint identifiers for the real closeComplaint API.
  final String altCustomerId;
  final String realComplaintId;
  // Real status text (e.g. ONHOLD/RESOLVED/CLOSED); null → fall back to the enum.
  final String? statusLabel;
  // Called after the Update screen returns success, so the caller can refetch.
  final VoidCallback? onUpdated;

  const ComplaintCard({
    super.key,
    required this.complaintId,
    required this.name,
    required this.description,
    required this.status,
    this.altCustomerId = '',
    this.realComplaintId = '',
    this.statusLabel,
    this.onUpdated,
  });

  /// Status → badge colour. Mirrors the dashboard `_TicketCard._statusColor`
  /// mapping so the tab and the dashboard complaint list stay consistent.
  static Color _statusColor(String s) {
    final u = s.toUpperCase();
    if (u.contains('ASSIGN')) return const Color(0xFF1565C0); // blue
    if (u.contains('PROCESS') || u.contains('PROGRESS')) {
      return const Color(0xFFF59E0B); // amber
    }
    if (u.contains('HOLD')) return const Color(0xFFE53935); // red
    if (u.contains('RESOLV')) return const Color(0xFF43A047); // green
    if (u.contains('CLOS')) return const Color(0xFF757575); // grey
    return const Color(0xFF1565C0); // default → blue
  }

  @override
  Widget build(BuildContext context) {
    final statusText = statusLabel ??
        (status == ComplaintStatus.assigned ? 'ASSIGNED' : 'INPROCESS');
    final statusColor = _statusColor(statusText);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.paddingS),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar (ticket id) — mirrors the dashboard complaint card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    width: 1),
              ),
            ),
            child: Text(
              complaintId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: AppColors.primary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          // ── Body ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Name : $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.30)),
                      ),
                      child: Text(
                        'Status : $statusText',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // ── Action (navigation UNCHANGED; colour = AppColors.primary,
                //    identical to the dashboard card) ────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ComplaintDetailsScreen(
                            complaintId: complaintId,
                            customerName: name,
                            complaint: description,
                            currentStatus: statusText,
                            altCustomerId: altCustomerId,
                            realComplaintId: realComplaintId,
                          ),
                        ),
                      ).then((ok) {
                        if (ok == true) onUpdated?.call();
                      });
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    label: const Text('Update Status'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
