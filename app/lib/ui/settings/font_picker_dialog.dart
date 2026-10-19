import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/fonts.dart' as api;
import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/theme/app_theme.dart';
import 'package:album_manager/ui/common/smooth_scroll.dart';

/// Chooses the UI font among the installed ones (or the default)
/// and applies it on confirm.
Future<void> showFontPicker(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _FontPickerDialog());

/// Radio value of the default font (no installed font has an empty name).
const _default = '';

class _FontPickerDialog extends StatefulWidget {
  const _FontPickerDialog();

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  final _fonts = api.systemFontFamilies();
  final _scroll = SmoothScrollController();
  String _selected = settings.fontFamily ?? _default;
  String _query = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('界面字体'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      // The list ends in a divider, so center the buttons below it instead
      // of the default top-aligned actions (0 above, 24 below).
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索已安装的字体',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder(
                future: _fonts,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final fonts = [
                    if (appFont.toLowerCase().contains(_query)) _default,
                    // The default font is listed once, as the first entry.
                    ...snap.data!.where(
                      (f) => f != appFont && f.toLowerCase().contains(_query),
                    ),
                  ];
                  // The tiles' hover / selection ink paints on the nearest
                  // Material: give the list its own, clipped to the list, so
                  // the ink doesn't spill over the dialog's action bar.
                  return RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: (v) => setState(() => _selected = v!),
                    child: Material(
                      type: MaterialType.transparency,
                      clipBehavior: Clip.hardEdge,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: fonts.length,
                        itemBuilder: (context, i) {
                          final f = fonts[i];
                          final family = f == _default ? appFont : f;
                          TextStyle? preview(TextStyle? s) => s?.copyWith(
                            fontFamily: family,
                            fontFamilyFallback: const [
                              appFont,
                              ...appFontFallback,
                            ],
                          );
                          return RadioListTile<String>(
                            value: f,
                            title: Text(
                              f == _default ? '$appFont（默认）' : f,
                              style: preview(t.textTheme.bodyLarge),
                            ),
                            subtitle: Text(
                              '专辑库 アルバム Album 0123',
                              style: preview(t.textTheme.bodyMedium)?.copyWith(
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            settings.setFontFamily(_selected == _default ? null : _selected);
            Navigator.pop(context);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
