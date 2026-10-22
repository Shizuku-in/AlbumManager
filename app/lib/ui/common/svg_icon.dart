import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A single-color SVG asset drawn like an [Icon]: sized and tinted by the
/// ambient [IconTheme] unless given.
class SvgIcon extends StatelessWidget {
  final String asset;
  final double? size;
  final Color? color;
  const SvgIcon(this.asset, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SvgPicture.asset(
      asset,
      width: s,
      height: s,
      colorFilter: ColorFilter.mode(
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}
