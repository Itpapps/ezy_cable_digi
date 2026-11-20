import 'package:flutter/material.dart';

import '../../core/theme/theme_constants.dart';
import 'mini_day_report_screen.dart';
import 'monthly_report_screen.dart';
import 'package:ezy_cable_digi/widgets/main_frame.dart';

/// Reports Home — Android parity (ReportsHome_Fragment / activity_reports.xml).
///
/// A **static** screen (no loading, no API, no toolbar menu — Android's fragment
/// only wires two click listeners): a "Reports" header + one white card holding
/// two tappable tiles. Back returns to the dashboard, matching Android's
/// `changeFragment(ReportsHome, addToBackstack=true)`.
///
/// Tiles (Android order):
///  1. Employee Collections → MonthlyReportScreen (Report_EmpCollect: empCollection
///     employee list + Total → per-customer detail → Collection Report print).
///  2. Miniday Report → MiniDayReportScreen (MiniDayReport_Fragment).
class ReportsHomeScreen extends StatelessWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      MainFrame(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    // Theme-aware, matching Android's ?attr/background + ?attr/textclr and the
    // rest of the app: page/app-bar follow the theme; the card stays white in
    // both themes (with theme-aware text on it), exactly like every other card.
    final t = AppThemeConst.of(context);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 40, // compact, same as Customer / Payment Details
        title: const Text('Reports',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        backgroundColor: t.appBarBg,
        foregroundColor: t.appBarFg,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Card(
            color: t.cardBg,
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              // Android: LinearLayout marginTop/Bottom 50, padding 10.
              padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tile(
                    context,
                    'Employee Collections',
                    (_) => const MonthlyReportScreen(),
                  ),
                  const SizedBox(height: 50), // Android tile marginTop 50
                  _tile(
                    context,
                    'Miniday Report',
                    (_) => const MiniDayReportScreen(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A tile mirroring Android's `rectangle_new` button: rounded rectangle, light
  // elevation, bold 18sp centered text, padding 20 top/bottom, margins 20 L/R.
  Widget _tile(BuildContext context, String label, WidgetBuilder builder) {
    final t = AppThemeConst.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        // On a white card in both themes → a subtle bordered tile like Android's
        // rectangle_new; text follows the theme (cardHeadingText).
        color: t.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.inputBorderColor),
        boxShadow: [
          BoxShadow(
            color: t.cardShadowColor,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: builder)),
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: t.cardHeadingText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
