import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/ui/health/health_page.dart';
import 'package:album_manager/ui/library/library_page.dart';
import 'package:album_manager/ui/settings/settings_page.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/ui/shell/scan_status.dart';
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

  void _select(int i) {
    // Re-selecting the current destination returns to its root page.
    if (i == library.navIndex) _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    library.setNav(i);
  }

  Widget _icon(int i, {required bool selected}) {
    final icon = Icon(selected ? _dests[i].selectedIcon : _dests[i].icon);
    if (i != _healthIndex || library.issueCount == 0) return icon;
    return Badge.count(count: library.issueCount, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 1200;
        final body = !library.ready
            ? const Center(child: CircularProgressIndicator())
            : library.root == null
                ? const WelcomePage()
                : IndexedStack(
                    index: library.navIndex,
                    children: [
                      for (var i = 0; i < _dests.length; i++)
                        Navigator(
                          key: _navKeys[i],
                          observers: [HeroController()],
                          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _dests[i].page),
                        ),
                    ],
                  );
        return Scaffold(
          body: Row(children: [
            if (wide) _drawer(context) else _rail(context),
            Expanded(
              child: Column(children: [
                if (library.scanning)
                  LinearProgressIndicator(value: (library.scan!.total == 0) ? null : library.scan!.fraction)
                else
                  const SizedBox(height: 4),
                Expanded(child: body),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _drawer(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // Standard (non-modal) drawer: flush with the window, no rounded edge.
    return Theme(
      data: Theme.of(context).copyWith(drawerTheme: const DrawerThemeData(shape: RoundedRectangleBorder(), width: 280)),
      child: NavigationDrawer(
        backgroundColor: cs.surfaceContainerLow,
        selectedIndex: library.navIndex,
        onDestinationSelected: _select,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 16, 16),
            child: Row(children: [
              Icon(Icons.album, color: cs.primary, size: 28),
              const SizedBox(width: 12),
              Text('Album Manager', style: tt.titleMedium),
            ]),
          ),
          for (var i = 0; i < _dests.length; i++)
            NavigationDrawerDestination(
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
          const Padding(padding: EdgeInsets.fromLTRB(28, 16, 28, 16), child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: const ScanStatus()),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context) {
    return NavigationRail(
      selectedIndex: library.navIndex,
      onDestinationSelected: _select,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Icon(Icons.album, color: Theme.of(context).colorScheme.primary, size: 28),
      ),
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
