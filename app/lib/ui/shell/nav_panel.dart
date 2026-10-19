import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:album_manager/state/settings_controller.dart';

class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Shown as an icon badge when collapsed, as trailing text when expanded.
  final int count;
  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.count = 0,
  });
}

/// M3 navigation that morphs between a navigation rail (collapsed) and a
/// standard navigation drawer (expanded) instead of swapping widgets, so both
/// the toggle button and window-size changes animate.
///
/// The icons sit at the same x in both forms; the indicator morphs from the
/// rail's 56×32 pill to the drawer's full-width pill, and the labels below /
/// beside the icons cross-fade.
class NavPanel extends StatefulWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Whether the window is wide enough to expand by default.
  final bool wide;

  /// Shown under the destinations while expanded.
  final Widget? footer;
  const NavPanel({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.wide,
    this.footer,
  });

  static const collapsedWidth = 80.0;
  static const expandedWidth = 280.0;

  @override
  State<NavPanel> createState() => _NavPanelState();
}

class _NavPanelState extends State<NavPanel>
    with SingleTickerProviderStateMixin {
  static const _prefKey = 'navExpanded';

  /// The user's choice for wide windows; narrow windows start collapsed.
  late bool _preferExpanded = settings.prefs.getBool(_prefKey) ?? true;
  late bool _expanded = widget.wide && _preferExpanded;
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: _expanded ? 1 : 0,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
  );

  @override
  void didUpdateWidget(NavPanel old) {
    super.didUpdateWidget(old);
    if (widget.wide != old.wide) _setExpanded(widget.wide && _preferExpanded);
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setExpanded(bool v) {
    if (v == _expanded) return;
    _expanded = v;
    v ? _controller.forward() : _controller.reverse();
    setState(() {});
  }

  void _toggle() {
    _setExpanded(!_expanded);
    // Remember the choice only where it applies by default.
    if (widget.wide) {
      _preferExpanded = _expanded;
      settings.prefs.setBool(_prefKey, _expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final t = _progress.value;
          final width = lerpDouble(
            NavPanel.collapsedWidth,
            NavPanel.expandedWidth,
            t,
          )!;
          return SizedBox(
            width: width,
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  for (var i = 0; i < widget.items.length; i++)
                    _Destination(
                      item: widget.items[i],
                      selected: i == widget.selectedIndex,
                      t: t,
                      width: width,
                      onTap: () => widget.onSelected(i),
                    ),
                  if (widget.footer != null && t > 0)
                    Opacity(
                      opacity: t,
                      // Lay out at the final width so text doesn't rewrap while animating.
                      child: OverflowBox(
                        // Take the child's height; the Column gives no height bound.
                        fit: OverflowBoxFit.deferToChild,
                        alignment: Alignment.topLeft,
                        minWidth: NavPanel.expandedWidth,
                        maxWidth: NavPanel.expandedWidth,
                        child: widget.footer,
                      ),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
                    child: IconButton(
                      tooltip: _expanded ? '收起导航' : '展开导航',
                      onPressed: _toggle,
                      // ">" turns into "<" as the panel expands.
                      icon: Transform.rotate(
                        angle: math.pi * t,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  final NavItem item;
  final bool selected;

  /// 0 = rail, 1 = drawer.
  final double t;
  final double width;
  final VoidCallback onTap;
  const _Destination({
    required this.item,
    required this.selected,
    required this.t,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    // Rail: 64 tall + 8 gap, pill 56×32 at the top, label below.
    // Drawer: 56 tall rows, pill spans the row.
    final height = lerpDouble(72, 56, t)!;
    final pill = Rect.lerp(
      const Rect.fromLTWH(12, 4, 56, 32),
      Rect.fromLTWH(12, 0, width - 24, 56),
      t,
    )!;
    final radius = BorderRadius.circular(lerpDouble(16, 28, t)!);
    final iconCenterY = pill.center.dy;
    final railLabel = (1 - 2 * t).clamp(0.0, 1.0);
    final drawerLabel = (2 * t - 1).clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // The whole destination is tappable; the ink is confined to the pill.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
            ),
          ),
          Positioned.fromRect(
            rect: pill,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? 1 : 0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, s, _) => Transform.scale(
                scaleX: lerpDouble(0.5, 1, s),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: s),
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: pill,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: radius),
                onTap: onTap,
              ),
            ),
          ),
          // Icon: centered at x = 40 in both forms.
          Positioned(
            left: 28,
            top: iconCenterY - 12,
            child: IgnorePointer(
              child: Badge.count(
                count: item.count,
                isLabelVisible: item.count > 0 && railLabel > 0,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (railLabel > 0)
            Positioned(
              left: 0,
              width: NavPanel.collapsedWidth,
              top: pill.bottom + 4,
              child: IgnorePointer(
                child: Opacity(
                  opacity: railLabel,
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelMedium?.copyWith(
                      color: selected ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (drawerLabel > 0)
            Positioned(
              left: 64,
              // Fixed final width so the label doesn't rewrap while the panel grows.
              width: NavPanel.expandedWidth - 64 - 36,
              top: pill.top,
              height: pill.height,
              child: IgnorePointer(
                child: Opacity(
                  opacity: drawerLabel,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelLarge?.copyWith(
                            color: selected
                                ? cs.onSecondaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (item.count > 0)
                        Text(
                          '${item.count}',
                          style: tt.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
