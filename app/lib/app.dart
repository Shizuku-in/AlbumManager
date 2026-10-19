import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/shell/shell.dart';
import 'package:album_manager/ui/shell/title_bar.dart';

class AlbumManagerApp extends StatelessWidget {
  const AlbumManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // On Windows, dynamic_color provides the system accent color.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final useDynamic =
              settings.useSystemColor &&
              lightDynamic != null &&
              darkDynamic != null;
          final lightSeed = useDynamic
              ? lightDynamic.primary
              : settings.seedColor;
          final darkSeed = useDynamic
              ? darkDynamic.primary
              : settings.seedColor;
          return MaterialApp(
            title: 'Album Manager',
            debugShowCheckedModeBanner: false,
            theme: themeFor(lightSeed, Brightness.light),
            darkTheme: themeFor(darkSeed, Brightness.dark),
            themeMode: settings.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            // The title bar sits above the Navigator, so it needs its own
            // Overlay for its tooltips.
            builder: (context, child) => Overlay.wrap(
              child: Column(
                children: [
                  const TitleBar(),
                  Expanded(child: child!),
                ],
              ),
            ),
            home: const Shell(),
          );
        },
      ),
    );
  }
}
