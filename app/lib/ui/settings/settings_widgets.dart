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
            if (title != null) SectionHeader(title!) else const SizedBox(height: 8),
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
      child: Text(text, style: t.textTheme.bodySmall?.copyWith(color: color ?? t.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Chip row under a tile title.
Widget settingsChips(List<Widget> chips) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: chips),
);

/// A second-level settings page: rebuilt when the library or settings change.
class SettingsSubpage extends StatelessWidget {
  final String title;
  final List<Widget> Function(BuildContext context) groups;
  const SettingsSubpage({super.key, required this.title, required this.groups});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, settings]),
      builder: (context, _) => AppPage(title: title, slivers: [SliverList.list(children: groups(context))]),
    );
  }
}
