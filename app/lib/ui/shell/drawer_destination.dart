import 'package:flutter/material.dart';

/// Keeps the animated indicator's ink on the same repaint layer as its tile.
class DrawerDestination extends NavigationDrawerDestination {
  const DrawerDestination({
    super.key,
    required super.icon,
    super.selectedIcon,
    required super.label,
  });

  @override
  Widget build(BuildContext context) {
    // NavigationDrawer's list gives each tile a repaint boundary. Ink painted
    // on the shared Material outside that boundary can retain an old transform
    // until a pointer event repaints it. Give each tile its own ink surface.
    // Subclassing preserves NavigationDrawer's destination discovery.
    return Material(type: MaterialType.transparency, child: super.build(context));
  }
}
