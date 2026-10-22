import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

/// How albums are shown and found: library cards, search, album page.
class BrowsingSettingsPage extends StatelessWidget {
  const BrowsingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '专辑浏览',
      onReset: settings.resetBrowsing,
      groups: (context) => [
        SettingsGroup(
          title: '专辑库',
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
            SettingsMultiChoice(
              icon: Icons.dashboard_customize_outlined,
              title: '卡片显示内容',
              subtitle: '标题总是显示',
              values: CardField.values,
              isOn: settings.showsOnCard,
              label: (f) => f.label,
              onChanged: settings.setCardField,
            ),
            SettingsChoice(
              icon: Icons.calendar_today_outlined,
              title: '日期格式',
              values: DateStyle.values,
              selected: settings.dateStyle,
              label: (s) => s.label,
              onSelected: settings.setDateStyle,
            ),
          ],
        ),
        SettingsGroup(
          title: '搜索与筛选',
          children: [
            SettingsMultiChoice(
              icon: Icons.search,
              title: '搜索范围',
              values: SearchField.values,
              isOn: settings.searches,
              label: (f) => f.label,
              onChanged: settings.setSearchField,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.filter_list),
              title: const Text('记住筛选条件'),
              subtitle: const Text('下次打开时恢复专辑库的筛选（排序方式总是会记住）'),
              value: settings.rememberFilters,
              onChanged: settings.setRememberFilters,
            ),
          ],
        ),
        SettingsGroup(
          title: '专辑页',
          children: [
            SettingsChoice(
              icon: Icons.account_tree_outlined,
              title: '文件列表',
              values: FileListMode.values,
              selected: settings.fileListMode,
              label: (m) => m.label,
              onSelected: settings.setFileListMode,
            ),
            SettingsReveal(
              shown: settings.fileListMode == FileListMode.tree,
              child: SettingsChoice(
                icon: Icons.folder_open_outlined,
                title: '目录显示',
                values: FolderView.values,
                selected: settings.folderView,
                label: (v) => v.label,
                onSelected: settings.setFolderView,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
