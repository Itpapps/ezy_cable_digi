import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/data/customer.dart';
import '../../core/services/session_service.dart';
import '../packages/data/customer_box.dart';

/// One Customer Operations tile: icon + label + gradient.
class CustomerOperation {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  const CustomerOperation(this.icon, this.label, this.gradientColors);
}

/// Builds the Customer Operations grid dynamically — Android parity with
/// `CustomerOperations_Fragment` (compute-once-from-state; entry-driven, no
/// live refresh). Tiles are emitted in Android's canonical layout order so the
/// yet-to-be-built features (Temporary Activation, Renew, Custom Packages,
/// Unpaid Activation) slot into their exact positions once implemented.
///
/// PHASE 2 scope — emit ONLY operations Flutter already supports, gated exactly
/// as Android:
///  • Package Operations — hidden when `tmp_activation != 0` (Android GONEs it;
///    Temporary Activation takes this slot once built — Fragment:1314-1320).
///  • Deactivate STB — gated on `unpaid_customer_deactivation` (Fragment:1557).
///  • One Time Charges + History — gated on `onetime_charges` (Fragment:807).
/// Every other tile is always-on today (matches Android).
///
/// Defaults are off, so a session/customer with no flags renders exactly the
/// pre-builder set minus the correctly-gated tiles.
List<CustomerOperation> buildCustomerOperations(
  Customer customer,
  SessionService session, {
  // OTT boxes from getCustomerBoxes (fetched on the details screen). Drives the
  // OTT branch of Android's `editcustomer` button. Default false = tile hidden.
  bool hasOttBoxes = false,
  CustomerBox? selectedBox,
}) {
  final ops = <CustomerOperation>[
    // Always-visible (canonical slots 1–6).
    const CustomerOperation(Iconsax.money_send, 'Make Payments',
        [Color(0xFF7B5EA7), Color(0xFF9C6FE4)]),
    const CustomerOperation(Iconsax.clock, 'Payment History',
        [Color(0xFFD4A017), Color(0xFFF5C842)]),
    const CustomerOperation(Iconsax.message_question, 'Create Complaints',
        [Color(0xFF607D8B), Color(0xFF90A4AE)]),
    const CustomerOperation(Iconsax.location, 'Update Location',
        [Color(0xFF1976D2), Color(0xFF42A5F5)]),
    const CustomerOperation(Iconsax.document, 'Invoice History',
        [Color(0xFF5C35B1), Color(0xFF7E57C2)]),
    const CustomerOperation(Iconsax.message_text, 'Complaint History',
        [Color(0xFF7B1FA2), Color(0xFFAB47BC)]),
  ];

  // Canonical slots 7–9 — mutually exclusive priority chain.
  // When selectedBox is non-null (multi-box), decision is per-box:
  //   active box → Package Operations (always, ignores customer-level flags)
  //   deactivated box → unpaid_act > tmp_activation > fallback Package Ops
  // When null (single-box / no boxes), original customer-level logic preserved.
  if (selectedBox != null) {
    if (selectedBox.isActive) {
      ops.add(const CustomerOperation(Iconsax.box, 'Package Operations',
          [Color(0xFFE65100), Color(0xFFFF8C42)]));
    } else {
      if (customer.unpaidAct == 1 && session.unpaidCustomerActivation) {
        ops.add(const CustomerOperation(Icons.person_add_alt_1,
            'Unpaid Customer Activation', [Color(0xFF00838F), Color(0xFF26C6DA)]));
      } else if (customer.tmpActivation != 0) {
        ops.add(const CustomerOperation(Icons.play_circle_outline,
            'Temporary Activation', [Color(0xFF2E7D32), Color(0xFF66BB6A)]));
      } else {
        ops.add(const CustomerOperation(Iconsax.box, 'Package Operations',
            [Color(0xFFE65100), Color(0xFFFF8C42)]));
      }
    }
  } else {
    if (customer.unpaidAct == 1 && session.unpaidCustomerActivation) {
      ops.add(const CustomerOperation(Icons.person_add_alt_1,
          'Unpaid Customer Activation', [Color(0xFF00838F), Color(0xFF26C6DA)]));
    } else if (customer.tmpActivation != 0) {
      ops.add(const CustomerOperation(Icons.play_circle_outline,
          'Temporary Activation', [Color(0xFF2E7D32), Color(0xFF66BB6A)]));
    } else {
      ops.add(const CustomerOperation(Iconsax.box, 'Package Operations',
          [Color(0xFFE65100), Color(0xFFFF8C42)]));
    }
  }

  // Canonical slot 10 — Deactivate STB (Android gates on unpaid_customer_deactivation).
  if (session.unpaidCustomerDeactivation) {
    ops.add(const CustomerOperation(
        Icons.tv, 'Deactivate STB', [Color(0xFFB71C1C), Color(0xFFEF5350)]));
  }

  // Canonical slot 12 — Act-Deact Report (always).
  ops.add(const CustomerOperation(Iconsax.chart, 'Act-Deact Report',
      [Color(0xFFEF6C00), Color(0xFFFFA726)]));

  // Canonical slot 13 — Custom Packages. Android gates on show_custom_packages
  // (CustomerOperations_Fragment:800). Opens the DigiPackage_Home hub.
  if (session.showCustomPackages) {
    ops.add(const CustomerOperation(Icons.inventory_2, 'Custom Packages',
        [Color(0xFF00695C), Color(0xFF26A69A)]));
  }

  // Canonical slots 14–15 — One Time Charges + History (gated on onetime_charges).
  if (session.onetimeCharges) {
    ops.add(const CustomerOperation(Iconsax.timer_1, 'One Time Charges',
        [Color(0xFF00796B), Color(0xFF26A69A)]));
    ops.add(const CustomerOperation(Iconsax.receipt_1, 'One Time History',
        [Color(0xFF1565C0), Color(0xFF42A5F5)]));
  }

  // Canonical slot 16 — Renew Services (STB). Android gates on
  // renew=="1" && is_show!=0 (CustomerOperations_Fragment:1151-1157). The
  // "Renew BroadBand" variant is a SEPARATE feature (editcustomer →
  // BroadBandList screen), not packageRenew, and is intentionally NOT emitted here.
  if (session.renew && customer.isShow != 0) {
    ops.add(const CustomerOperation(Icons.autorenew, 'Renew Services',
        [Color(0xFFC2185B), Color(0xFFE91E63)]));
  }

  // Canonical slot 17 — Pay Later (always).
  ops.add(const CustomerOperation(Iconsax.clock, 'Pay Later',
      [Color(0xFF558B2F), Color(0xFF9CCC65)]));

  // Canonical slot 18 — Android `custoper_btn_editcustomer` (mutually exclusive
  // branches, per its onClick :1117): broadband_user_id != "" → Renew BroadBand
  // (BroadBandList); else, when OTT boxes exist → OTT (OTTFragment).
  if (customer.broadbandUserId.trim().isNotEmpty) {
    ops.add(const CustomerOperation(Icons.wifi, 'Renew BroadBand',
        [Color(0xFF6A1B9A), Color(0xFFAB47BC)]));
  } else if (hasOttBoxes) {
    ops.add(const CustomerOperation(Icons.live_tv, 'OTT',
        [Color(0xFF283593), Color(0xFF5C6BC0)]));
  }

  return ops;
}
