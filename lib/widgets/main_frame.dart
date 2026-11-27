import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/services/offline_mode_service.dart';
import '../core/services/session_service.dart';
import '../core/widgets/premium_dialog.dart';
import '../features/dashboard/dashboard_screen.dart';
import 'app_drawer.dart';
import 'bottom_nav_bar.dart';
import 'main_header.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MainFrame — Android MainActivity's frame (activity_bottom_bar_dashboard.xml)
// ─────────────────────────────────────────────────────────────────────────────

/// Every Fragment that Android shows with MainActivity.changeFragment lands in
/// frame_container, between the fixed toolbar (menu, logo, search, bluetooth,
/// calendar, scan) and the bottom bar (Dashboard / Complaints / Analytics /
/// Expenses). Wrap the existing Scaffold of each such screen:
///
///   return MainFrame(child: Scaffold(...));
///
/// The screen's own AppBar (back arrow + title) stays under the header: it is
/// Android's in-page title, and iPhones have no hardware Back button.
///
/// No bars are added — the screen looks and works exactly as before — when:
///  • offline mode is on (Android Offline_Activity has neither bar);
///  • the screen is a Dashboard tab or sits inside another MainFrame;
///  • the window is shorter than [minHeight] (phone landscape, split screen);
///  • [enabled] is false.
/// The same outer Scaffold is always built (only its slots become null), so
/// the bars can come and go without re-creating the screen's State.
class MainFrame extends StatelessWidget {
  final Widget child;

  /// false hides the bars (e.g. a map mode that Android opens as its own
  /// Activity, without bars).
  final bool enabled;

  /// Height of the screen's OWN bottom action bar (SAVE, Print/Share…), if it
  /// has one. Snackbars are lifted by this much so they do not cover it.
  final double snackBarLift;

  /// Dark-mode top bar and tab bar for this screen only (demo). Off by default.
  final bool dark;

  const MainFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.snackBarLift = 0,
    this.dark = false,
  });

  /// Below this window height the bars would leave too little room.
  static const double minHeight = 500;

  /// With the keyboard open, the header stays only if at least this much of
  /// the window is still above the keyboard.
  static const double minRoomWhileTyping = 460;

  /// Extra bottom margin for floating snackbars of the screen at [context]
  /// (see [snackBarLift]). 0 outside a MainFrame.
  static double snackBarLiftOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_MainFrameScope>()?.snackBarLift ??
      0;

  @override
  Widget build(BuildContext context) {
    // A Dashboard tab (the Dashboard already shows both bars) or a screen
    // inside another MainFrame: leave it untouched.
    if (context.getInheritedWidgetOfExactType<_MainFrameScope>() != null ||
        context.findAncestorStateOfType<DashboardScreenState>() != null) {
      return child;
    }
    return ValueListenableBuilder<bool>(
      valueListenable: OfflineModeService.instance.offlineUi,
      builder: (context, offline, _) {
        final height = MediaQuery.sizeOf(context).height;
        final show = enabled && !offline && height >= minHeight;
        // The screen keeps handling the keyboard exactly as before: its box
        // still reaches down to the bottom bar (behind the keyboard) and it is
        // told the keyboard covers [extra] of it, so its body ends at the
        // keyboard top and its own bottom bar stays behind the keyboard.
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final barHeight = show
            ? BottomNavBar.height + MediaQuery.paddingOf(context).bottom
            : 0.0;
        final extra = math.max(0.0, keyboard - barHeight);
        // Small phone + keyboard open: the header steps aside while typing
        // (like Android's adjustPan moving the toolbar out of view), so the
        // screen keeps the room it has today.
        final showHeader =
            show && (keyboard == 0 || height - keyboard >= minRoomWhileTyping);

        Widget frame = Scaffold(
          drawer: show ? const AppDrawer() : null,
          appBar: showHeader
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(62),
                  child: MainHeader(
                    dark: dark,
                    onLogoTap: () => MainNav.goToTab(context, 0),
                  ),
                )
              : null,
          bottomNavigationBar: show
              ? BottomNavBar(
                  dark: dark,
                  currentIndex: DashboardScreenState.current?.selectedTab ?? 0,
                  onChanged: (i) => MainNav.openTab(context, i),
                )
              : null,
          body: LayoutBuilder(
            builder: (bodyContext, box) {
              final inner = MediaQuery.of(bodyContext);
              return OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: box.maxHeight + extra,
                maxHeight: box.maxHeight + extra,
                child: MediaQuery(
                  data: inner.copyWith(
                    viewInsets: inner.viewInsets.copyWith(bottom: extra),
                  ),
                  child: child,
                ),
              );
            },
          ),
        );

        // Floating snackbars are shown by this outer Scaffold, just above the
        // bottom bar — lift them over the screen's own action bar.
        if (snackBarLift > 0) {
          final theme = Theme.of(context);
          frame = Theme(
            data: theme.copyWith(
              snackBarTheme: theme.snackBarTheme.copyWith(
                insetPadding: EdgeInsets.fromLTRB(15, 5, 15, 10 + snackBarLift),
              ),
            ),
            child: frame,
          );
        }
        return _MainFrameScope(snackBarLift: snackBarLift, child: frame);
      },
    );
  }
}

/// Drop-in for [Center] in a box of limited height: lays the child out
/// exactly like Center when it fits, and scrolls instead of overflowing when
/// the box is shorter (small phones once the MainFrame bars take ~120 px).
class CenterOrScroll extends StatelessWidget {
  final Widget child;

  const CenterOrScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: box.hasBoundedWidth ? box.maxWidth : 0,
            minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _MainFrameScope extends InheritedWidget {
  final double snackBarLift;

  const _MainFrameScope({required this.snackBarLift, required super.child});

  @override
  bool updateShouldNotify(_MainFrameScope old) =>
      old.snackBarLift != snackBarLift;
}

// ─────────────────────────────────────────────────────────────────────────────
// MainNav — the bottom bar / logo / drawer "Dashboard" actions of a MainFrame
// screen. MainFrame screens are routes pushed above the Dashboard (the root
// route of an online session), so they reach it through
// [DashboardScreenState.current].
// ─────────────────────────────────────────────────────────────────────────────
class MainNav {
  MainNav._();

  /// Android MainActivity bottom bar (:170-205). Expenses needs the role's
  /// `expenses` permission — "No Access" is shown on the CURRENT screen.
  static bool tabAllowed(BuildContext context, int tab) {
    if (tab == 3 && !SessionService.instance.addExpense) {
      showPremiumConfirm(
        context: context,
        title: 'No Access',
        body: "You don't have access for this operation",
        confirmLabel: 'Ok',
        cancelLabel: 'Close',
      );
      return false;
    }
    return true;
  }

  /// Bottom bar tap on a MainFrame screen.
  static void openTab(BuildContext context, int tab) {
    if (!tabAllowed(context, tab)) return;
    goToTab(context, tab);
  }

  /// Back to the Dashboard (root route) and show its [tab].
  static void goToTab(BuildContext context, int tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    DashboardScreenState.current?.setTab(tab);
  }

  /// Closes the screen at [context] after an async step, even when another
  /// screen was opened on top of it meanwhile (MainFrame header / drawer):
  /// pops it when it is the top screen, otherwise removes it from underneath
  /// — never the screen the user moved to.
  static void closeScreen(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }
}
