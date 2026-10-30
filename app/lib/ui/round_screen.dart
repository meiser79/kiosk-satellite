import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Keeps the app's own chrome (menu, settings, dialogs, overlays) clear of
/// the edge of a round screen, such as the Echo Spot's, whose circle cuts
/// off the corners.
///
/// While [round] is true, the margin to the square within the circle, less
/// [contentInset], goes into MediaQuery's padding and viewPadding, so every
/// SafeArea, and every overlay that pads by MediaQuery.paddingOf, keeps its
/// close button where it can be seen. [RoundScreen] below it tells the
/// screens that use the circle beyond that, such as a list that scrolls on
/// to the edge. The dashboard page does not move: Chromium takes
/// env(safe-area-inset-*) from Android's window insets, never from
/// MediaQuery.
///
/// Always in the tree, even on a rectangular screen, for the reason
/// [UiScaleExempt] is: a wrapper that came and went would change the tree
/// shape and recreate the WebViews, a full page reload.
class RoundScreenPadding extends StatelessWidget {
  const RoundScreenPadding({
    super.key,
    required this.round,
    required this.child,
  });

  final ValueListenable<bool> round;

  /// How far the safe area reaches past the square within the circle.
  ///
  /// The rule this takes for granted: every screen keeps its content at
  /// least [contentClearance] inside its safe area, as the overlays' lists,
  /// eyebrows and close buttons do. Content [contentClearance] inside the
  /// safe area's corner still lies about 11 inside the circle on the Echo
  /// Spot. Something drawn right at the safe area's corner would be cut.
  static const contentInset = 12.0;

  /// How far inside the safe area the screens keep their content at the
  /// least, which [contentInset] relies on.
  static const contentClearance = 20.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: round,
      builder: (context, round, child) {
        final mq = MediaQuery.of(context);
        // The circle fills the shorter side; the square inside it is its
        // diameter over the square root of two. The safe area reaches
        // [contentInset] past it, its corners off the circle.
        final size = mq.size;
        final square = size.shortestSide / math.sqrt2 + 2 * contentInset;
        final inset = round
            ? EdgeInsets.symmetric(
                horizontal: math.max(0.0, (size.width - square) / 2),
                vertical: math.max(0.0, (size.height - square) / 2),
              )
            : EdgeInsets.zero;
        EdgeInsets atLeastInset(EdgeInsets e) => EdgeInsets.fromLTRB(
          math.max(e.left, inset.left),
          math.max(e.top, inset.top),
          math.max(e.right, inset.right),
          math.max(e.bottom, inset.bottom),
        );
        return MediaQuery(
          data: mq.copyWith(
            padding: atLeastInset(mq.padding),
            viewPadding: atLeastInset(mq.viewPadding),
          ),
          child: RoundScreen(round: round, child: child!),
        );
      },
      child: child,
    );
  }
}

/// Whether the screen is round, for the screens that use the circle beyond
/// the safe area [RoundScreenPadding] gives them. On a rectangular screen
/// they keep their usual layout.
///
/// The pattern for a list that reaches the top or bottom of the screen: its
/// SafeArea leaves that edge out on a round screen, and the list adds the
/// MediaQuery padding left there to its own. The list then rests inside the
/// circle and scrolls on to its edge. Under a SafeArea that keeps the edge
/// the padding left is 0, so the same code serves both screens.
class RoundScreen extends InheritedWidget {
  const RoundScreen({super.key, required this.round, required super.child});

  final bool round;

  /// Whether the screen is round; false outside a [RoundScreenPadding].
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoundScreen>()?.round ?? false;

  /// The width of a pane that slides in from the left edge, [narrow] on a
  /// rectangular screen. On a round screen it reaches as far right as the
  /// circle does at the top of the safe area, so its rows, which run from
  /// the safe area's left edge, never meet the curve on the right.
  static double paneWidth(BuildContext context, double narrow) {
    if (!of(context)) return narrow;
    final mq = MediaQuery.of(context);
    final r = mq.size.shortestSide / 2;
    final dy = r - mq.padding.top;
    final reach = math.sqrt(math.max(0.0, r * r - dy * dy));
    return math.max(narrow, mq.size.width / 2 + reach);
  }

  /// [padding] for a list that reaches the bottom of the screen under a
  /// SafeArea that leaves the bottom out: on a round screen it adds the
  /// round margin there, so the list rests above it and scrolls on to the
  /// edge. On a rectangular screen it is [padding] as it is.
  static EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) =>
      of(context)
      ? padding + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)
      : padding;

  @override
  bool updateShouldNotify(RoundScreen oldWidget) => round != oldWidget.round;
}

/// The body of a page with an app bar, such as a settings page on a phone.
/// On a round screen it keeps clear of the circle on the left and right;
/// the app bar takes the top, and the page's list the bottom
/// ([RoundScreen.scrollPadding]). On a rectangular screen it changes
/// nothing.
class RoundScreenSides extends StatelessWidget {
  const RoundScreenSides({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final round = RoundScreen.of(context);
    return SafeArea(
      top: false,
      bottom: false,
      left: round,
      right: round,
      child: child,
    );
  }
}

/// Keeps [child] inside the safe area on a round screen only, for what is
/// otherwise meant to run to the screen's edges, such as the screensaver's
/// corner widgets. On a rectangular screen it changes nothing.
class RoundScreenInset extends StatelessWidget {
  const RoundScreenInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final round = RoundScreen.of(context);
    return SafeArea(
      left: round,
      top: round,
      right: round,
      bottom: round,
      child: child,
    );
  }
}
