import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/navigation.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/shared_axis.dart';
import 'package:album_manager/ui/health/health_page.dart';
import 'package:album_manager/ui/library/library_page.dart';
import 'package:album_manager/ui/settings/settings_page.dart';
import 'package:album_manager/ui/settings/welcome_page.dart';
import 'package:album_manager/ui/shell/scan_status.dart';
import 'package:album_manager/ui/shell/nav_panel.dart';
import 'package:album_manager/ui/stats/stats_page.dart';
import 'package:album_manager/ui/timeline/timeline_page.dart';

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;
  final HideablePage? hideable;
  const _Dest(
    this.icon,
    this.selectedIcon,
    this.label,
    this.page, [
    this.hideable,
  ]);
}

const _dests = [
  _Dest(
    Icons.library_music_outlined,
    Icons.library_music,
    '专辑库',
    LibraryPage(),
  ),
  _Dest(
    Icons.view_timeline_outlined,
    Icons.view_timeline,
    '时间线',
    TimelinePage(),
    HideablePage.timeline,
  ),
  _Dest(
    Icons.insights_outlined,
    Icons.insights,
    '统计',
    StatsPage(),
    HideablePage.stats,
  ),
  _Dest(
    Icons.health_and_safety_outlined,
    Icons.health_and_safety,
    '健康检查',
    HealthPage(),
    HideablePage.health,
  ),
  _Dest(Icons.settings_outlined, Icons.settings, '设置', SettingsPage()),
];

const _healthIndex = 3;

/// M3 navigation: a drawer on expanded widths, a rail on medium widths; the
/// user can toggle between them and the change animates (see [NavPanel]).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with SingleTickerProviderStateMixin {
  final _navKeys = List.generate(
    _dests.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  // Built once: switching destinations must not rebuild the pages.
  late final List<Widget> _pages = [
    for (var i = 0; i < _dests.length; i++)
      Navigator(
        key: _navKeys[i],
        onGenerateRoute: (_) =>
            MaterialPageRoute(builder: (_) => _dests[i].page),
      ),
  ];

  /// Shared axis Y, matching the vertical rail: a destination further down
  /// comes up from below. Content follows the selection.
  late final _pageSwitch = SharedAxisSwitch(
    vsync: this,
    initial: navIndex.value,
    onShownChanged: _onPageShown,
  );

  /// Ctrl+F was pressed while another destination was showing.
  bool _focusSearch = false;

  @override
  void initState() {
    super.initState();
    navIndex.addListener(_onNav);
  }

  @override
  void dispose() {
    navIndex.removeListener(_onNav);
    _pageSwitch.dispose();
    super.dispose();
  }

  void _onNav() => _pageSwitch.select(navIndex.value);

  void _onPageShown() {
    setState(() {});
    if (_focusSearch && _pageSwitch.shown == 0) _requestSearchFocus();
  }

  void _requestSearchFocus() {
    _focusSearch = false;
    // After the frame that makes the library page focusable again (hidden
    // IndexedStack children exclude focus).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => librarySearchFocus.requestFocus(),
    );
  }

  void _select(int i) {
    // Re-selecting the current destination returns to its root page.
    if (i == navIndex.value) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    }
    navIndex.value = i;
  }

  /// Mouse back button / Alt+←: back within the current destination.
  void _back() => _navKeys[navIndex.value].currentState?.maybePop();

  /// Ctrl+F: the library's search field, from anywhere.
  void _search() {
    _navKeys[0].currentState?.popUntil((r) => r.isFirst);
    navIndex.value = 0;
    // Focus once the library page is the one on screen.
    _focusSearch = true;
    if (_pageSwitch.shown == 0) _requestSearchFocus();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    // Dialogs live on the root navigator, outside this subtree, so neither
    // the shortcuts nor the back button reach the page behind an open dialog.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _search,
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerDown: (e) {
            if (e.buttons & kBackMouseButton != 0) _back();
          },
          child: _scaffold(wide),
        ),
      ),
    );
  }

  Widget _scaffold(bool wide) {
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([library, navIndex, settings]),
            builder: (context, _) {
              // First run: the welcome page alone until a library is chosen.
              // Shown while loading, so normal launches don't flash without it.
              if (library.ready && library.root == null) {
                return const SizedBox.shrink();
              }
              // Indices into _dests of the destinations shown.
              final shown = [
                for (var i = 0; i < _dests.length; i++)
                  if (!settings.hiddenPages.contains(_dests[i].hideable)) i,
              ];
              return NavPanel(
                wide: wide,
                selectedIndex: shown.indexOf(navIndex.value),
                onSelected: (i) => _select(shown[i]),
                items: [
                  for (final i in shown)
                    NavItem(
                      icon: _dests[i].icon,
                      selectedIcon: _dests[i].selectedIcon,
                      label: _dests[i].label,
                      count: i == _healthIndex ? library.issueCount : 0,
                    ),
                ],
                footer: const ScanStatus(),
              );
            },
          ),
          Expanded(
            child: Column(
              children: [
                ValueListenableBuilder(
                  valueListenable: library.scanProgress,
                  builder: (context, scan, _) => scan == null
                      ? const SizedBox.shrink()
                      : LinearProgressIndicator(
                          value: scan.total == 0 ? null : scan.fraction,
                        ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: library,
                    builder: (context, _) {
                      if (!library.ready) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (library.root == null) return const WelcomePage();
                      final shown = _pageSwitch.shown;
                      return AnimatedBuilder(
                        animation: _pageSwitch.controller,
                        builder: (context, child) => Opacity(
                          opacity: _pageSwitch.opacity,
                          child: Transform.translate(
                            offset: Offset(0, _pageSwitch.shift),
                            child: child,
                          ),
                        ),
                        child: IndexedStack(
                          index: shown,
                          children: [
                            for (var i = 0; i < _pages.length; i++)
                              _PageHost(active: i == shown, child: _pages[i]),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hosts one destination inside the IndexedStack.
///
/// * No scaling in the switch transition: a transform that is not exactly
///   identity makes text render blurry (the slide ends at exactly zero).
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

class _PageHostState extends State<_PageHost> {
  Widget? _themedChild;

  @override
  void didUpdateWidget(_PageHost old) {
    super.didUpdateWidget(old);
    if (widget.child != old.child) _themedChild = null;
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to animated theme updates, but only forward them while visible.
    // Capture all inherited themes: Theme(data: ...) alone still inherits the
    // live Cupertino theme and wakes hidden descendants on every frame.
    Theme.of(context);
    if (widget.active || _themedChild == null) {
      _themedChild = InheritedTheme.captureAll(context, widget.child);
    }
    return _themedChild!;
  }
}
