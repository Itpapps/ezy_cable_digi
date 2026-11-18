import 'package:flutter/material.dart';
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
        title: const Text('COMPLAINTS',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
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
