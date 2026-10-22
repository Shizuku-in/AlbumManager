import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/section_header.dart';

/// Outlined card holding one titled group of settings tiles.
class SettingsGroup extends StatelessWidget {
  final String? title;

  /// Shown at the end of the title row, e.g. a help button.
  final Widget? trailing;
  final List<Widget> children;
  const SettingsGroup({
    super.key,
    this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null && trailing != null)
              // Same height as a plain header with a compact icon button.
              SectionHeader(
                title!,
                trailing: trailing,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              )
            else if (title != null)
              SectionHeader(title!)
            else
              const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A setting that only applies while the one above has a certain value:
/// unfolds downward from it while fading when [shown] turns true.
class SettingsReveal extends StatelessWidget {
  final bool shown;
  final Widget child;
  const SettingsReveal({super.key, required this.shown, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: shown
          ? KeyedSubtree(key: const ValueKey(true), child: child)
          : const SizedBox(key: ValueKey(false), width: double.infinity),
    );
  }
}

/// Small explanatory text aligned with the tile text above (16 padding +
/// 24 icon + 16 gap).
class SettingsNote extends StatelessWidget {
  final String text;
  final Color? color;
  const SettingsNote(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 0, 24, 8),
      child: Text(
        text,
        style: t.textTheme.bodySmall?.copyWith(
          color: color ?? t.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// M3 basic dialog confirming an action that discards something.
Future<bool> confirmSetting(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String confirm,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(body),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Chip row under a tile title.
Widget settingsChips(List<Widget> chips) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: chips,
  ),
);

/// A tile choosing one of [values], as choice chips under its title.
class SettingsChoice<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;
  const SettingsChoice({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!),
          settingsChips([
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ]),
        ],
      ),
    );
  }
}

/// A tile turning each of [values] on or off, as filter chips under its
/// title.
class SettingsMultiChoice<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<T> values;
  final bool Function(T value) isOn;
  final String Function(T value) label;
  final void Function(T value, bool on) onChanged;
  const SettingsMultiChoice({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.values,
    required this.isOn,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!),
          settingsChips([
            for (final v in values)
              FilterChip(
                label: Text(label(v)),
                selected: isOn(v),
                onSelected: (on) => onChanged(v, on),
              ),
          ]),
        ],
      ),
    );
  }
}

/// A second-level settings page: rebuilt when the library or settings change.
///
/// With [onReset], the top app bar gets a "恢复默认" action (the same on
/// every page) that restores this page's settings after a confirmation;
/// [resetNote] adds what the dialog should mention beyond that.
class SettingsSubpage extends StatelessWidget {
  final String title;
  final List<Widget> Function(BuildContext context) groups;
  final Future<void> Function()? onReset;
  final String? resetNote;
  const SettingsSubpage({
    super.key,
    required this.title,
    required this.groups,
    this.onReset,
    this.resetNote,
  });

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await confirmSetting(
      context,
      icon: Icons.settings_backup_restore,
      title: '恢复默认设置？',
      body: '“$title”中的设置将恢复为默认值。${resetNote ?? ''}',
      confirm: '恢复默认',
    );
    if (ok) await onReset!();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) => AppPage(
        title: title,
        actions: [
          if (onReset != null)
            IconButton(
              tooltip: '恢复默认',
              onPressed: () => _confirmReset(context),
              icon: const Icon(Icons.settings_backup_restore),
            ),
        ],
        slivers: [SliverList.list(children: groups(context))],
      ),
    );
  }
}
