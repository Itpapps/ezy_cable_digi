import 'package:flutter/material.dart';

/// iOS-only requirement of `share_plus` (7.2.2).
///
/// `UIActivityViewController` anchors its popover to a source rect. share_plus
/// rejects the share outright — before ever presenting the sheet — when that
/// rect is empty or falls outside the root view:
///
/// ```objc
/// // FPPSharePlusPlugin.m:390
/// if (hasPopoverPresentationController &&
///     (!isCoordinateSpaceOfSourceView || CGRectIsEmpty(origin))) {
///   result([FlutterError errorWithCode:@"error" message:sharePositionIssue ...]);
///   return;
/// }
/// ```
///
/// The plugin comments assume `popoverPresentationController` is non-nil only
/// on iPad, but on current iOS it is non-nil on iPhone too — so the rect must
/// always be supplied, on every device. Android ignores the value entirely, so
/// passing it changes nothing there.
///
/// Returns the tapped widget's rect in global (root-view) coordinates, clamped
/// into the screen. Falls back to a small rect at the centre of the screen when
/// the render object is missing or degenerate, so a share can never fail for
/// want of an anchor.
Rect shareOriginFrom(BuildContext context) {
  final screenSize = MediaQuery.maybeOf(context)?.size;
  final screen = Offset.zero & (screenSize ?? const Size(1, 1));
  final fallback = Rect.fromCenter(center: screen.center, width: 1, height: 1);

  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return fallback;

  // A button scrolled partly off-screen would otherwise yield a rect iOS
  // refuses (CGRectContainsRect fails), so intersect with the root view.
  final rect = (box.localToGlobal(Offset.zero) & box.size).intersect(screen);
  if (rect.isEmpty || !rect.isFinite) return fallback;
  return rect;
}
