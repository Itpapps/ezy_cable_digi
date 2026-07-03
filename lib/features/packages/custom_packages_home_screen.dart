import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/customer.dart';
import 'custom_packages_activation_screen.dart';
import 'custom_packages_deactivation_screen.dart';

/// Custom Packages hub — Android parity (`DigiPackage_Home`): two actions,
/// Activate and Deactivate, each opening a multi-select package cart.
///
/// Phase C step 1 (foundation): the hub + tile + `getDigiDealerPackages` repo.
/// The Activation (cart → BillDetails → `insertDigiDealerPackages`) and
/// Deactivation flows are wired in steps 2 and 3.
class CustomPackagesHomeScreen extends StatelessWidget {
  final Customer customer;
  const CustomPackagesHomeScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        title: const Text('CUSTOM PACKAGES'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _hubButton(
              context,
              'Activate Packages',
              Icons.add_box,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomPackagesActivationScreen(customer: customer),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _hubButton(
              context,
              'Deactivate Packages',
              Icons.indeterminate_check_box,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomPackagesDeactivationScreen(customer: customer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hubButton(BuildContext context, String label, IconData icon,
      {required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
        ),
        onPressed: onTap,
      ),
    );
  }
}
