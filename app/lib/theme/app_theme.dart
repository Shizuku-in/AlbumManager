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
  );
}

ColorScheme schemeFor(Color seed, Brightness b) => ColorScheme.fromSeed(seedColor: seed, brightness: b);

/// Scheme derived from album content (cover color), per M3 content-based color.
ThemeData contentTheme(BuildContext context, Color? seed) {
  final base = Theme.of(context);
  if (seed == null) return base;
  return buildTheme(ColorScheme.fromSeed(
    seedColor: seed,
    brightness: base.brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  ));
}
