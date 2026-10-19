import 'package:flutter/material.dart';

import 'package:album_manager/state/library_controller.dart';
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/common/app_page.dart';
import 'package:album_manager/ui/common/section_header.dart';

/// Outlined card holding one titled group of settings tiles.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsGroup({super.key, this.title, required this.children});

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
            if (title != null)
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
        TextButton(
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
