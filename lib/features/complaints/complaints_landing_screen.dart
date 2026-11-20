import 'package:flutter/material.dart';
import '../../core/theme/theme_constants.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/data/customer.dart';
import 'create_complaint_screen.dart';
import 'complaints_history_screen.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COMPLAINTS landing (Customer Details → Create Complaints) — mirrors Android's
// Complaints_Fragment: two actions.
//   • New Complaint    → the create form (createComplaint).
//   • Update Complaint → this customer's complaint list (getCustomerComplaintList),
//     each row tappable to update its status (closeComplaint).
// ─────────────────────────────────────────────────────────────────────────────
class ComplaintsLandingScreen extends StatelessWidget {
  final Customer customer;
  const ComplaintsLandingScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final t = AppThemeConst.of(context);
    return Scaffold(
      // Theme-aware page (Theme 1: the same blue as before).
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 40, // compact, same as Customer / Payment Details
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque, // whole leading slot stays tappable
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppThemeConst.of(context).backBtnBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_new,
                size: 16, color: AppThemeConst.of(context).backBtnIcon),
          ),
        ),
        title: Text('COMPLAINTS',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppThemeConst.of(context).appBarFg,
                letterSpacing: 1)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              // Theme 2 only: lift the white card off the light page.
              boxShadow: t.isLight
                  ? [
                      BoxShadow(
                          color: t.cardShadowColor,
                          blurRadius: 14,
                          offset: const Offset(0, 6)),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  customer.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D47A1)),
                ),
                const SizedBox(height: 22),
                _actionButton(
                  context,
                  icon: Iconsax.add_circle,
                  label: 'New Complaint',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateComplaintScreen(customer: customer),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _actionButton(
                  context,
                  icon: Iconsax.edit,
                  label: 'Update Complaint',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ComplaintHistoryScreen(customer: customer),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFFF4F7FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF0D47A1).withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0D47A1), size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D47A1))),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF5B7BAE)),
            ],
          ),
        ),
      ),
    );
  }
}
