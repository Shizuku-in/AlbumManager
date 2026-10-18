import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/navigation.dart';
import 'package:album_manager/ui/health/health_page.dart';
import 'package:album_manager/ui/library/library_page.dart';
import 'package:album_manager/ui/settings/settings_page.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/ui/shell/scan_status.dart';
import 'package:album_manager/ui/shell/drawer_destination.dart';
import 'package:album_manager/ui/stats/stats_page.dart';
import 'package:album_manager/ui/timeline/timeline_page.dart';

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;
  const _Dest(this.icon, this.selectedIcon, this.label, this.page);
}

const _dests = [
  _Dest(Icons.library_music_outlined, Icons.library_music, '专辑库', LibraryPage()),
  _Dest(Icons.view_timeline_outlined, Icons.view_timeline, '时间线', TimelinePage()),
  _Dest(Icons.insights_outlined, Icons.insights, '统计', StatsPage()),
  _Dest(Icons.health_and_safety_outlined, Icons.health_and_safety, '健康检查', HealthPage()),
  _Dest(Icons.settings_outlined, Icons.settings, '设置', SettingsPage()),
];

const _healthIndex = 3;

/// M3 navigation: a standard navigation drawer on expanded widths,
/// a navigation rail on medium widths.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _navKeys = List.generate(_dests.length, (_) => GlobalKey<NavigatorState>());

  // Built once: switching destinations must not rebuild the pages.
  late final List<Widget> _pages = [
    for (var i = 0; i < _dests.length; i++)
      Navigator(
        key: _navKeys[i],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _dests[i].page),
      ),
  ];

  void _select(int i) {
    // Re-selecting the current destination returns to its root page.
    if (i == navIndex.value) _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    navIndex.value = i;
  }

  Widget _icon(int i, {required bool selected}) {
    final icon = Icon(selected ? _dests[i].selectedIcon : _dests[i].icon);
    if (i != _healthIndex || library.issueCount == 0) return icon;
    return Badge.count(count: library.issueCount, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    return Scaffold(
      body: Row(children: [
        ListenableBuilder(
          listenable: Listenable.merge([library, navIndex]),
          builder: (context, _) => wide ? _drawer(context) : _rail(context),
        ),
        Expanded(
          child: Column(children: [
            ValueListenableBuilder(
              valueListenable: library.scanProgress,
              builder: (context, scan, _) => scan == null
                  ? const SizedBox.shrink()
                  : LinearProgressIndicator(value: scan.total == 0 ? null : scan.fraction),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([library, navIndex]),
                builder: (context, _) {
                  if (!library.ready) return const Center(child: CircularProgressIndicator());
                  if (library.root == null) return const WelcomePage();
                  return IndexedStack(index: navIndex.value, children: [
                    for (var i = 0; i < _pages.length; i++) _PageHost(active: i == navIndex.value, child: _pages[i]),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _drawer(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return NavigationDrawer(
      backgroundColor: cs.surfaceContainerLow,
      selectedIndex: navIndex.value,
      onDestinationSelected: _select,
      children: [
        const SizedBox(height: 12),
        for (var i = 0; i < _dests.length; i++)
          DrawerDestination(
            icon: Icon(_dests[i].icon),
            selectedIcon: Icon(_dests[i].selectedIcon),
            // M3 drawer: counts are shown as trailing badge label text.
            label: SizedBox(
              width: 176,
              child: Row(children: [
                Expanded(child: Text(_dests[i].label)),
                if (i == _healthIndex && library.issueCount > 0) Text('${library.issueCount}', style: tt.labelLarge),
              ]),
            ),
          ),
        const ScanStatus(),
      ],
    );
  }

  Widget _rail(BuildContext context) {
    return NavigationRail(
      selectedIndex: navIndex.value,
      onDestinationSelected: _select,
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (var i = 0; i < _dests.length; i++)
          NavigationRailDestination(
            icon: _icon(i, selected: false),
            selectedIcon: _icon(i, selected: true),
            label: Text(_dests[i].label),
          ),
      ],
    );
  }
}

/// Hosts one destination inside the IndexedStack.
///
/// * Shown destinations fade in. No scaling: a transform that is not exactly
///   identity makes text render blurry.
/// * Hidden destinations keep the theme they were last shown with, so a theme
///   change (which animates frame by frame) only rebuilds the visible page;
///   a hidden page catches up once when it is shown again.
class _PageHost extends StatefulWidget {
  final bool active;
  final Widget child;
  const _PageHost({required this.active, required this.child});

  @override
  State<_PageHost> createState() => _PageHostState();
}

class _PageHostState extends State<_PageHost> with SingleTickerProviderStateMixin {
  ThemeData? _theme;
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 250), value: 1);
  late final _curve = CurvedAnimation(parent: _enter, curve: Easing.emphasizedDecelerate);

  @override
  void didUpdateWidget(_PageHost old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = Theme.of(context);
    if (widget.active || _theme == null) _theme = live;
    return FadeTransition(opacity: _curve, child: Theme(data: _theme!, child: widget.child));
  }
}
