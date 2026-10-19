import 'package:flutter/material.dart';

import 'package:album_manager/theme/app_colors.dart';

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

/// Bundled (see pubspec.yaml). Fallbacks cover Japanese-only kanji etc.
const appFont = 'HarmonyOS Sans SC';
const appFontFallback = ['Microsoft YaHei UI', 'Yu Gothic UI', 'Segoe UI'];

ThemeData buildTheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFont,
    fontFamilyFallback: appFontFallback,
    visualDensity: VisualDensity.standard,
    extensions: [AppColors.forScheme(scheme)],
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 480),
    // Standard (non-modal) navigation drawer: flush with the window edge.
    drawerTheme: const DrawerThemeData(shape: RoundedRectangleBorder(), width: 280),
    // Current M3 page transition (slide + fade). The Windows default zooms,
    // and any scale that is not exactly identity renders text blurry.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {for (final p in TargetPlatform.values) p: const FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

// Generating a theme runs ColorScheme.fromSeed for the scheme and for every
// custom color, so themes are cached per seed + brightness.
final _themes = <(int, Brightness), ThemeData>{};

/// Theme generated from a seed color (tonal spot scheme), cached.
ThemeData themeFor(Color seed, Brightness brightness) {
  if (_themes.length > 128) _themes.clear();
  return _themes.putIfAbsent((seed.toARGB32(), brightness), () => buildTheme(ColorScheme.fromSeed(seedColor: seed, brightness: brightness)));
}

/// Theme derived from album content (cover color), per M3 content-based color.
ThemeData contentTheme(BuildContext context, Color? seed) {
  final base = Theme.of(context);
  if (seed == null) return base;
  return themeFor(seed, base.brightness);
}
