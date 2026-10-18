// Frame-time benchmark of common interactions against the real library.
//
//   cd app
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/perf_test.dart
//
// Results are written to build/integration_response_data.json.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:album_manager/main.dart' as app;
import 'package:album_manager/ui/library/album_card.dart';

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Finder nav(String label) => find.descendant(of: find.byType(NavigationDrawer), matching: find.text(label));

  Future<void> tap(WidgetTester tester, Finder f, {int settle = 700}) async {
    await tester.tap(f.first);
    await tester.pump();
    await _wait(settle);
  }

  testWidgets('interaction frame times', (tester) async {
    await app.main();
    for (var i = 0; i < 100 && find.byType(AlbumCard).evaluate().isEmpty; i++) {
      await tester.pump();
      await _wait(100);
    }
    expect(find.byType(AlbumCard), findsWidgets);
    await _wait(1500); // let the startup scan finish

    const dests = ['专辑库', '时间线', '统计', '健康检查', '设置'];
    await binding.watchPerformance(() async {
      for (var k = 0; k < 3; k++) {
        for (final d in [...dests.skip(1), dests.first]) {
          await tap(tester, nav(d));
        }
      }
    }, reportKey: 'nav');

    await binding.watchPerformance(() async {
      for (var k = 0; k < 6; k++) {
        await tap(tester, find.byIcon(Icons.view_list), settle: 800);
        await tap(tester, find.byIcon(Icons.grid_view), settle: 800);
      }
    }, reportKey: 'toggle');

    await tap(tester, nav('设置'));
    await binding.watchPerformance(() async {
      for (var k = 0; k < 4; k++) {
        await tap(tester, find.text('浅色'), settle: 900);
        await tap(tester, find.text('深色'), settle: 900);
      }
    }, reportKey: 'theme');
    await tap(tester, find.text('跟随系统'));
    await tap(tester, nav('专辑库'));

    await binding.watchPerformance(() => _wait(4000), reportKey: 'idle');
  });
}
