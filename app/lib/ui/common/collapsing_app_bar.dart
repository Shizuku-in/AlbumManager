import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

const _toolbarHeight = 64.0;
const _expandedHeight = 112.0;

/// M3 medium-sized top app bar whose single title glides from the expanded
/// row into the toolbar while shrinking, instead of cross-fading two titles.
/// The scrolled-under background change fades rather than snapping.
SliverAppBar collapsingAppBar({required Widget title, List<Widget> actions = const []}) {
  return SliverAppBar(
    pinned: true,
    toolbarHeight: _toolbarHeight,
    expandedHeight: _expandedHeight,
    // The flexible space paints the (animated) background itself.
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    actions: actions,
    flexibleSpace: _CollapsingTitle(title: title),
  );
}

class _CollapsingTitle extends StatelessWidget {
  final Widget title;
  const _CollapsingTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final range = s.maxExtent - s.minExtent;
    // 0 = fully expanded, 1 = collapsed into the toolbar.
    final t = range <= 0 ? 1.0 : ((s.maxExtent - s.currentExtent) / range).clamp(0.0, 1.0);
    final collapsedStyle = theme.textTheme.titleLarge!.copyWith(color: scheme.onSurface);
    final expandedStyle = theme.textTheme.headlineSmall!;
    final topPadding = s.minExtent - _toolbarHeight;
    // Collapsed, the title moves past the back button (if any), like a
    // regular toolbar title.
    final hasBack = ModalRoute.of(context)?.canPop ?? false;
    final left = lerpDouble(16, hasBack ? 72 : 16, t)!;
    // Expanded: centered in the band below the toolbar, 20px above the bottom
    // (M3 medium spec). Collapsed: centered in the toolbar.
    final expandedLineHeight = expandedStyle.fontSize! * (expandedStyle.height ?? 1.2);
    final expandedCenter = _expandedHeight - 20 - expandedLineHeight / 2;
    final dy = lerpDouble(expandedCenter - _toolbarHeight / 2, 0, t)!;
    final scale = lerpDouble(expandedStyle.fontSize! / collapsedStyle.fontSize!, 1, t)!;

    return ScrolledUnderBackground(
      child: Stack(children: [
        Positioned(
          top: topPadding,
          left: left,
          right: 16,
          height: _toolbarHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: AlignmentDirectional.centerStart.resolve(Directionality.of(context)),
                child: DefaultTextStyle(style: collapsedStyle, maxLines: 1, overflow: TextOverflow.ellipsis, child: title),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// App bar background that fades to the M3 scrolled-under color. Use as a
/// SliverAppBar's flexibleSpace, with the bar's own background transparent,
/// or pass [scrolledUnder] explicitly (e.g. for a pinned header below it).
class ScrolledUnderBackground extends StatelessWidget {
  final bool? scrolledUnder;
  final Widget? child;
  const ScrolledUnderBackground({super.key, this.scrolledUnder, this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scrolledUnder = this.scrolledUnder ?? context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()?.isScrolledUnder ?? false;
    // Animate the scrolled-under amount, not the color: the colors are read
    // from the theme on every frame, so theme / accent changes (which the app
    // already animates) apply in lockstep instead of chasing a moving target.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: scrolledUnder ? 1 : 0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      // SizedBox.expand: a childless ColoredBox would size itself to zero.
      builder: (context, t, child) => SizedBox.expand(
        child: ColoredBox(color: Color.lerp(scheme.surface, scheme.surfaceContainer, t)!, child: child),
      ),
      child: child,
    );
  }
}
