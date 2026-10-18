import 'package:flutter/material.dart';

import 'package:album_manager/theme/app_colors.dart';

/// Fallback seed when the OS provides no accent color.
const defaultSeed = Color(0xFF6750A4);

const appFont = 'Microsoft YaHei UI';
const appFontFallback = ['Yu Gothic UI', 'Segoe UI', 'Microsoft YaHei'];

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
