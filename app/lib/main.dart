import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:album_manager/app.dart';
import 'package:album_manager/src/rust/frb_generated.dart';
import 'package:album_manager/state/library_browser.dart';
import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await settings.load();
  browser.load();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(960, 640),
      center: true,
      title: 'Album Manager',
      titleBarStyle: TitleBarStyle.hidden, // replaced by the Material TitleBar
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  library.init();
  runApp(const AlbumManagerApp());
}
