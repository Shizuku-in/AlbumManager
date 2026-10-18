import 'dart:ui' as ui;

import 'package:album_manager/ui/shell/drawer_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('programmatic return repaints the drawer without pointer events', (tester) async {
    final selected = ValueNotifier<int>(0);
    addTearDown(selected.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (context, index, _) => NavigationDrawer(
              selectedIndex: index,
              onDestinationSelected: (value) => selected.value = value,
              children: const [
                DrawerDestination(icon: Icon(Icons.library_music), label: Text('Library')),
                DrawerDestination(icon: Icon(Icons.view_timeline), label: Text('Timeline')),
                DrawerDestination(icon: Icon(Icons.insights), label: Text('Stats')),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<List<int>?> pixels() => tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List().toList();
    });

    final initial = (await pixels())!;
    for (final source in [1, 2]) {
      selected.value = source;
      await tester.pumpAndSettle();
      expect(await pixels(), isNot(orderedEquals(initial)));
      selected.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await pixels();
      await tester.pumpAndSettle();
      expect(await pixels(), orderedEquals(initial));
    }
  });
}
