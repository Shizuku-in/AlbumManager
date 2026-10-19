import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// An M3 "custom color": a key color plus its tonal roles, harmonized with
/// the scheme's primary so it sits comfortably next to the dynamic palette.
@immutable
class CustomColor {
  final Color color;
  final Color onColor;
  final Color container;
  final Color onContainer;
  const CustomColor(this.color, this.onColor, this.container, this.onContainer);

  factory CustomColor.from(Color seed, ColorScheme scheme) {
    final s = ColorScheme.fromSeed(
      seedColor: seed.harmonizeWith(scheme.primary),
      brightness: scheme.brightness,
    );
    return CustomColor(
      s.primary,
      s.onPrimary,
      s.primaryContainer,
      s.onPrimaryContainer,
    );
  }

  static CustomColor lerp(CustomColor a, CustomColor b, double t) =>
      CustomColor(
        Color.lerp(a.color, b.color, t)!,
        Color.lerp(a.onColor, b.onColor, t)!,
        Color.lerp(a.container, b.container, t)!,
        Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

/// Semantic colors not covered by ColorScheme (success / warning, media sources).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final CustomColor success;
  final CustomColor warning;
  final CustomColor cd;
  final CustomColor digital;
  final CustomColor hiRes;
  final CustomColor dsd;
  final CustomColor disc;

  const AppColors({
    required this.success,
    required this.warning,
    required this.cd,
    required this.digital,
    required this.hiRes,
    required this.dsd,
    required this.disc,
  });

  factory AppColors.forScheme(ColorScheme s) => AppColors(
    success: CustomColor.from(const Color(0xFF2E7D32), s),
    warning: CustomColor.from(const Color(0xFFF9A825), s),
    cd: CustomColor.from(const Color(0xFFEF8F00), s),
    digital: CustomColor.from(const Color(0xFF0277BD), s),
    hiRes: CustomColor.from(const Color(0xFFC8A400), s),
    dsd: CustomColor.from(const Color(0xFF8E24AA), s),
    disc: CustomColor.from(const Color(0xFF00897B), s),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: CustomColor.lerp(success, other.success, t),
      warning: CustomColor.lerp(warning, other.warning, t),
      cd: CustomColor.lerp(cd, other.cd, t),
      digital: CustomColor.lerp(digital, other.digital, t),
      hiRes: CustomColor.lerp(hiRes, other.hiRes, t),
      dsd: CustomColor.lerp(dsd, other.dsd, t),
      disc: CustomColor.lerp(disc, other.disc, t),
    );
  }
}
