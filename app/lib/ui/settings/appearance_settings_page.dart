import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}

/// Theme, accent color and navigation.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '外观',
      groups: (context) => [
        SettingsGroup(title: '主题', children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('颜色模式'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette_outlined),
            title: const Text('使用系统强调色'),
            subtitle: const Text('关闭后可自选强调色'),
            value: settings.useSystemColor,
            onChanged: settings.setUseSystemColor,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            // Unfold downward from the switch while fading.
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, alignment: Alignment.topCenter, child: child),
            ),
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: settings.useSystemColor
                ? const SizedBox(key: ValueKey(false), width: double.infinity)
                : ListTile(
                    key: const ValueKey(true),
                    leading: const Icon(Icons.color_lens_outlined),
                    title: const Text('强调色'),
                    subtitle: settingsChips([
                      for (final c in seedPresets) _Swatch(color: c, selected: c == settings.seedColor, onTap: () => settings.setSeedColor(c)),
                    ]),
                  ),
          ),
        ]),
        SettingsGroup(title: '导航栏', children: [
          for (final p in HideablePage.values)
            SwitchListTile(
              secondary: Icon(switch (p) {
                HideablePage.timeline => Icons.view_timeline_outlined,
                HideablePage.stats => Icons.insights_outlined,
                HideablePage.health => Icons.health_and_safety_outlined,
              }),
              title: Text('显示 “${p.label}”'),
              value: !settings.hiddenPages.contains(p),
              onChanged: (v) => settings.setPageShown(p, v),
            ),
        ]),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Check mark that stays legible on light swatches (e.g. yellow).
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // 40 px target around a 32 px swatch.
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected ? Border.all(color: scheme.onSurface, width: 2) : null,
            ),
            child: selected ? Icon(Icons.check, size: 18, color: onColor) : null,
          ),
        ),
      ),
    );
  }
}
