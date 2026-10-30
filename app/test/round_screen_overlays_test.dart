import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/core/app_locales.dart';
import 'package:kiosk_satellite/core/command_registry.dart';
import 'package:kiosk_satellite/core/events.dart';
import 'package:kiosk_satellite/ui/intercom_settings.dart';
import 'package:kiosk_satellite/ui/round_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Echo Spot: 480x480 logical, and its round margin.
  const side = 480.0;
  final margin =
      (side - side / math.sqrt2) / 2 - RoundScreenPadding.contentInset;

  /// The Call a kiosk screen with more kiosks than fit, scrolled to its end:
  /// where the last kiosk's name and the close button come to rest.
  Future<({double last, double close, Rect list})> roster(
    WidgetTester tester, {
    required bool round,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    final status = {
      'enabled': true,
      'available': true,
      'state': 'idle',
      'kiosks': [
        for (var i = 0; i < 8; i++)
          {
            'id': 'id$i',
            'name': 'Kiosk $i',
            'address': '192.0.2.$i',
            'version': 'test',
            'status': 'ready',
            'statusText': 'Ready',
          },
      ],
    };
    c.commands.register(
      Command(
        name: 'intercomStatus',
        description: 'Fixture',
        handler: (_) async => CommandResult.ok(status),
      ),
    );
    tester.view.physicalSize = const Size(side, side);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) =>
            RoundScreenPadding(round: ValueNotifier(round), child: child!),
        home: Scaffold(
          body: Stack(children: [IntercomRosterOverlay(container: c)]),
        ),
      ),
    );
    c.intercom.rosterVisible.value = true;
    await tester.pumpAndSettle();
    c.bus.publish(IntercomStateChanged(status));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(side / 2, 300), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final result = (
      last: tester.getBottomLeft(find.text('Kiosk 7')).dy,
      close: tester.getTopLeft(find.byIcon(Icons.close)).dy,
      list: tester.getRect(find.byType(SingleChildScrollView)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await c.settings.dispose();
    return result;
  }

  testWidgets('the Intercom list scrolls on to the bottom of the circle', (
    tester,
  ) async {
    final rectangular = await roster(tester, round: false);
    final round = await roster(tester, round: true);
    // The list itself runs from the top to the bottom of the screen...
    expect(round.list.top, 0);
    expect(round.list.bottom, side);
    // ...and at its end rests the round margin higher, so nothing in it
    // stays below the circle.
    expect(round.last, closeTo(rectangular.last - margin, 0.01));
    // The close button stays put, inside the circle.
    expect(round.close, closeTo(rectangular.close + margin, 0.01));
  });
}
