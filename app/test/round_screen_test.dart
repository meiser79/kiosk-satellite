import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/round_screen.dart';
import 'package:kiosk_satellite/ui/ui_scale.dart';

void main() {
  const probe = Key('probe');
  // The Echo Spot: 480x480 logical at the test's devicePixelRatio of 3, and
  // the margin to the square inside its circle, less the screens' own inset.
  const side = 480.0;
  final margin =
      (side - side / math.sqrt2) / 2 - RoundScreenPadding.contentInset;

  Future<MediaQueryData Function()> pump(
    WidgetTester tester,
    ValueNotifier<bool> round, {
    double scale = 1.0,
    Widget Function(BuildContext context)? body,
  }) async {
    tester.view.physicalSize = const Size(side * 3, side * 3);
    addTearDown(tester.view.resetPhysicalSize);
    late MediaQueryData mq;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, c) => RoundScreenPadding(
          round: round,
          child: UiScaler(scale: scale, child: c!),
        ),
        home: Builder(
          builder: (context) {
            mq = MediaQuery.of(context);
            return body?.call(context) ?? const SizedBox.expand(key: probe);
          },
        ),
      ),
    );
    return () => mq;
  }

  testWidgets('a rectangular screen changes nothing', (tester) async {
    final mq = await pump(tester, ValueNotifier(false));
    expect(mq().padding, EdgeInsets.zero);
    expect(mq().viewPadding, EdgeInsets.zero);
  });

  testWidgets('a round screen pads to the square inside the circle', (
    tester,
  ) async {
    final mq = await pump(tester, ValueNotifier(true));
    expect(mq().padding, EdgeInsets.all(margin));
    expect(mq().viewPadding, EdgeInsets.all(margin));
    // Content kept 20 inside the padding stays clear of the circle.
    const r = side / 2;
    expect((r - margin - 20) * math.sqrt2, lessThan(r - 8));
  });

  testWidgets('a larger padding of the window wins', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 300);
    addTearDown(tester.view.resetPadding);
    final mq = await pump(tester, ValueNotifier(true));
    expect(mq().padding, EdgeInsets.fromLTRB(margin, 100, margin, margin));
  });

  testWidgets('Scale UI divides the padding with everything else', (
    tester,
  ) async {
    final mq = await pump(tester, ValueNotifier(true), scale: 1.5);
    expect(mq().padding, EdgeInsets.all(margin / 1.5));
  });

  testWidgets('a change follows without rebuilding the subtree', (
    tester,
  ) async {
    final round = ValueNotifier(false);
    final mq = await pump(tester, round);
    final before = tester.element(find.byKey(probe));
    round.value = true;
    await tester.pump();
    expect(mq().padding, EdgeInsets.all(margin));
    // The same element: the WebViews under it would not reload.
    expect(tester.element(find.byKey(probe)), same(before));
  });

  testWidgets('the screens below learn whether it is round', (tester) async {
    late bool seen;
    final round = ValueNotifier(false);
    await pump(
      tester,
      round,
      body: (context) {
        seen = RoundScreen.of(context);
        return const SizedBox.expand();
      },
    );
    expect(seen, isFalse);
    round.value = true;
    await tester.pump();
    expect(seen, isTrue);
  });

  testWidgets('outside the wrapper the screen is not round', (tester) async {
    late bool seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = RoundScreen.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(seen, isFalse);
  });

  testWidgets('a pane from the left reaches as far as the circle lets it', (
    tester,
  ) async {
    late double rectangular;
    await pump(
      tester,
      ValueNotifier(false),
      body: (context) {
        rectangular = RoundScreen.paneWidth(context, 300);
        return const SizedBox.expand();
      },
    );
    expect(rectangular, 300);

    late double width;
    await pump(
      tester,
      ValueNotifier(true),
      body: (context) {
        width = RoundScreen.paneWidth(context, 300);
        return const SizedBox.expand();
      },
    );
    // The pane's right edge meets the circle at the top of the safe area.
    const r = side / 2;
    expect(
      math.sqrt(math.pow(width - r, 2) + math.pow(r - margin, 2)),
      closeTo(r, 1e-9),
    );
    expect(width, greaterThan(300));
  });

  testWidgets('a list rests above the bottom of the circle', (tester) async {
    const padding = EdgeInsets.fromLTRB(20, 16, 20, 24);
    late EdgeInsets rectangular;
    await pump(
      tester,
      ValueNotifier(false),
      body: (context) {
        rectangular = RoundScreen.scrollPadding(context, padding);
        return const SizedBox.expand();
      },
    );
    expect(rectangular, padding);

    late EdgeInsets round;
    await pump(
      tester,
      ValueNotifier(true),
      body: (context) {
        round = RoundScreen.scrollPadding(context, padding);
        return const SizedBox.expand();
      },
    );
    expect(round, padding + EdgeInsets.only(bottom: margin));
  });

  for (final (name, wrap, inset) in [
    (
      'RoundScreenSides',
      (Widget child) => RoundScreenSides(child: child),
      (double m) => EdgeInsets.symmetric(horizontal: m),
    ),
    (
      'RoundScreenInset',
      (Widget child) => RoundScreenInset(child: child),
      (double m) => EdgeInsets.all(m),
    ),
  ]) {
    testWidgets('$name only moves its child on a round screen', (tester) async {
      const child = Key('child');
      Future<Rect> rect(bool round) async {
        await pump(
          tester,
          ValueNotifier(round),
          body: (context) => wrap(const SizedBox.expand(key: child)),
        );
        return tester.getRect(find.byKey(child));
      }

      const screen = Rect.fromLTWH(0, 0, side, side);
      expect(await rect(false), screen);
      expect(await rect(true), inset(margin).deflateRect(screen));
    });
  }
}
