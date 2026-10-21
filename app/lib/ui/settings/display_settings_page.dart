import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

IconData _fieldIcon(CardField f) => switch (f) {
  CardField.source => Icons.label_outline,
  CardField.quality => Icons.high_quality_outlined,
  CardField.artist => Icons.person_outline,
  CardField.date => Icons.event_outlined,
  CardField.ripStatus => Icons.verified_outlined,
};

/// How albums are shown in the library.
class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '专辑显示',
      onReset: settings.resetDisplay,
      groups: (context) => [
        SettingsGroup(
          title: '封面卡片',
          children: [
            ListTile(
              leading: const Icon(Icons.photo_size_select_large_outlined),
              title: const Text('卡片大小'),
              trailing: SegmentedButton<CardSize>(
                showSelectedIcon: false,
                segments: [
                  for (final s in CardSize.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {settings.cardSize},
                onSelectionChanged: (s) => settings.setCardSize(s.first),
              ),
            ),
            for (final f in CardField.values)
              SwitchListTile(
                secondary: Icon(_fieldIcon(f)),
                title: Text('显示${f.label}'),
                value: settings.showsOnCard(f),
                onChanged: (v) => settings.setCardField(f, v),
              ),
          ],
        ),
        SettingsGroup(
          title: '格式',
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('日期格式'),
              subtitle: settingsChips([
                for (final s in DateStyle.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: settings.dateStyle == s,
                    onSelected: (_) => settings.setDateStyle(s),
                  ),
              ]),
            ),
          ],
        ),
        SettingsGroup(
          title: '专辑页',
          children: [
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('文件列表'),
              subtitle: settingsChips([
                for (final m in FileListMode.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: settings.fileListMode == m,
                    onSelected: (_) => settings.setFileListMode(m),
                  ),
              ]),
            ),
            SettingsReveal(
              shown: settings.fileListMode == FileListMode.tree,
              child: ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('目录显示'),
                subtitle: settingsChips([
                  for (final v in FolderView.values)
                    ChoiceChip(
                      label: Text(v.label),
                      selected: settings.folderView == v,
                      onSelected: (_) => settings.setFolderView(v),
                    ),
                ]),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '浏览',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.filter_list),
              title: const Text('记住筛选条件'),
              subtitle: const Text('下次打开时恢复专辑库的筛选（排序方式总是会记住）'),
              value: settings.rememberFilters,
              onChanged: settings.setRememberFilters,
            ),
          ],
        ),
      ],
    );
  }
}
