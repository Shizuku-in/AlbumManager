import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_colors.dart';
import 'package:album_manager/ui/common/shared_axis.dart';

/// Fallback seed when the OS provides no accent color.
const defaultSeed = Color(0xFF6750A4);

/// Accent colors offered when the system accent color is off.
const seedPresets = [
  defaultSeed,
  Color(0xFF3F51B5), // indigo
  Color(0xFF1E88E5), // blue
  Color(0xFF00897B), // teal
  Color(0xFF43A047), // green
  Color(0xFFC0A000), // yellow
  Color(0xFFF57C00), // orange
  Color(0xFFE53935), // red
  Color(0xFFD81B60), // pink
  Color(0xFF795548), // brown
];

/// Flutter's platform text style: Segoe UI, SF Pro, or Roboto with Linux
/// fallbacks. The default UI font, so none is bundled.
final _platformText = Typography.material2021(platform: defaultTargetPlatform)
    .black
    .bodyMedium!;

/// The platform UI font, for previewing the default in settings.
final platformFont = _platformText.fontFamily!;

/// The platform's CJK UI fonts after the UI font (which has none, nor has
/// a chosen Western font): text falls back per character, so Latin keeps
/// the UI font. Japanese fonts fill in kanji used only in Japanese.
final appFontFallback = [
  ...?_platformText.fontFamilyFallback,
  ...switch (defaultTargetPlatform) {
    TargetPlatform.windows => ['Microsoft YaHei UI', 'Yu Gothic UI'],
    TargetPlatform.macOS => ['PingFang SC', 'Hiragino Sans'],
    TargetPlatform.linux => ['Noto Sans CJK SC', 'Noto Sans CJK JP'],
    _ => <String>[],
  },
];

ThemeData buildTheme(ColorScheme scheme, {String? font}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: font,
    fontFamilyFallback: appFontFallback,
    visualDensity: VisualDensity.standard,
    extensions: [AppColors.forScheme(scheme)],
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 480,
    ),
    // Standard (non-modal) navigation drawer: flush with the window edge.
    drawerTheme: const DrawerThemeData(
      shape: RoundedRectangleBorder(),
      width: 280,
    ),
    // M3 shared axis X (slide + fade). The Windows default zooms, and any
    // scale that is not exactly identity renders text blurry.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: const SharedAxisPageTransitionsBuilder(),
      },
    ),
  );
}

// Generating a theme runs ColorScheme.fromSeed for the scheme and for every
// custom color, so themes are cached per seed + brightness + font.
final _themes = <(int, Brightness, String?), ThemeData>{};

/// Theme generated from a seed color (tonal spot scheme) in the user's
/// font, cached.
ThemeData themeFor(Color seed, Brightness brightness) {
  if (_themes.length > 128) _themes.clear();
  final font = settings.fontFamily;
  return _themes.putIfAbsent(
    (seed.toARGB32(), brightness, font),
    () => buildTheme(
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      font: font,
    ),
  );
}

/// Theme derived from album content (cover color), per M3 content-based color.
ThemeData contentTheme(BuildContext context, Color? seed) {
  final base = Theme.of(context);
  if (seed == null) return base;
  return themeFor(seed, base.brightness);
}
