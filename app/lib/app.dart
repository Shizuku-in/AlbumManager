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
          final useDynamic = settings.useSystemColor && lightDynamic != null && darkDynamic != null;
          return MaterialApp(
            title: 'Album Manager',
            debugShowCheckedModeBanner: false,
            theme: themeFor(useDynamic ? lightDynamic.primary : defaultSeed, Brightness.light),
            darkTheme: themeFor(useDynamic ? darkDynamic.primary : defaultSeed, Brightness.dark),
            themeMode: settings.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => Column(children: [const TitleBar(), Expanded(child: child!)]),
            home: const Shell(),
          );
        },
      ),
    );
  }
}
