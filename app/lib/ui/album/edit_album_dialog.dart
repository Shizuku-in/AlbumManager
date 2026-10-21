import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/labels.dart';

/// Edits the hand-set values of an album. Returns the new overrides, or null
/// when cancelled. "自动" (null) means the detected value.
Future<AlbumOverride?> showEditAlbumDialog(BuildContext context, Album album) {
  return showDialog<AlbumOverride>(
    context: context,
    builder: (_) => _EditAlbumDialog(album),
  );
}

class _EditAlbumDialog extends StatefulWidget {
  final Album album;
  const _EditAlbumDialog(this.album);

  @override
  State<_EditAlbumDialog> createState() => _EditAlbumDialogState();
}

class _EditAlbumDialogState extends State<_EditAlbumDialog> {
  late AlbumSource? _source = widget.album.summary.overrides.source;
  late String? _cover = widget.album.summary.overrides.coverPath;
  late bool? _hasScans = widget.album.summary.overrides.hasScans;
  late final _catalog = TextEditingController(
    text: widget.album.summary.overrides.catalog,
  );
  late final _event = TextEditingController(
    text: widget.album.summary.overrides.event,
  );

  @override
  void dispose() {
    _catalog.dispose();
    _event.dispose();
    super.dispose();
  }

  /// Empty = the value read from the folder name.
  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final images = widget.album.images;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(s, style: t.textTheme.titleSmall),
    );
    return AlertDialog(
      icon: const Icon(Icons.edit_outlined),
      title: const Text('编辑专辑'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('来源'),
            SegmentedButton<AlbumSource?>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                  value: null,
                  label: Text('自动'),
                  icon: Icon(Icons.auto_awesome_outlined),
                ),
                for (final s in const [
                  AlbumSource.cdRip,
                  AlbumSource.digital,
                  AlbumSource.discImage,
                ])
                  ButtonSegment(
                    value: s,
                    label: Text(s.label),
                    icon: Icon(s.icon),
                  ),
              ],
              selected: {_source},
              onSelectionChanged: (s) => setState(() => _source = s.first),
            ),
            const SizedBox(height: 24),
            label('扫图'),
            SegmentedButton<bool?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: null,
                  label: Text('自动'),
                  icon: Icon(Icons.auto_awesome_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('有扫图'),
                  icon: Icon(Icons.photo_library_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('无扫图'),
                  icon: Icon(Icons.hide_image_outlined),
                ),
              ],
              selected: {_hasScans},
              onSelectionChanged: (s) => setState(() => _hasScans = s.first),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                for (final (i, (c, name)) in [
                  (_catalog, '品番'),
                  (_event, '展会'),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: c,
                      decoration: InputDecoration(
                        labelText: name,
                        hintText: '留空则从文件夹名识别',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            label('封面'),
            if (images.isEmpty)
              Text(
                '专辑文件夹里没有图片，将使用自动识别的封面。',
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              )
            else
              // Flexible lets the grid shrink on short windows instead of
              // overflowing under the action buttons.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 120,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: images.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? _CoverOption(
                            selected: _cover == null,
                            tooltip: '自动识别',
                            onTap: () => setState(() => _cover = null),
                            child: ColoredBox(
                              color: t.colorScheme.surfaceContainerHighest,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_outlined,
                                    color: t.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '自动',
                                    style: t.textTheme.labelMedium?.copyWith(
                                      color: t.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _CoverOption(
                            selected: _cover == images[i - 1].path,
                            tooltip: [
                              images[i - 1].group,
                              baseName(images[i - 1].path),
                            ].where((s) => s.isNotEmpty).join('/'),
                            onTap: () =>
                                setState(() => _cover = images[i - 1].path),
                            child: LazyThumb(
                              path: images[i - 1].path,
                              size: 240,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            AlbumOverride(
              source: _source,
              coverPath: _cover,
              hasScans: _hasScans,
              catalog: _text(_catalog),
              event: _text(_event),
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _CoverOption extends StatelessWidget {
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  const _CoverOption({
    required this.selected,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Card.filled(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected
              ? BorderSide(color: cs.primary, width: 3)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (selected)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.primary,
                      child: Icon(Icons.check, size: 16, color: cs.onPrimary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
