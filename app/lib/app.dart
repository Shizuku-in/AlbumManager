import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/shell/shell.dart';

/// Keeps the native title bar in sync with the app theme. Only calls into the
/// window API when the brightness actually changes (calling it on every build
/// triggers a window message → rebuild loop).
class _TitleBarBrightness extends StatefulWidget {
  final Brightness brightness;
  final Widget child;
  const _TitleBarBrightness({required this.brightness, required this.child});

  @override
  State<_TitleBarBrightness> createState() => _TitleBarBrightnessState();
}

class _TitleBarBrightnessState extends State<_TitleBarBrightness> {
  Brightness? _applied;

  void _sync() {
    if (_applied == widget.brightness) return;
    _applied = widget.brightness;
    WidgetsBinding.instance.addPostFrameCallback((_) => windowManager.setBrightness(widget.brightness));
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TitleBarBrightness old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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
            builder: (context, child) => _TitleBarBrightness(brightness: Theme.of(context).brightness, child: child!),
            home: const Shell(),
          );
        },
      ),
    );
  }
}
