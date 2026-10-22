import 'package:flutter/material.dart';

import 'package:album_manager/state/settings_controller.dart';
import 'package:album_manager/ui/settings/settings_widgets.dart';

/// Year cards and cover walls of the timeline.
class TimelineSettingsPage extends StatelessWidget {
  const TimelineSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '时间线',
      onReset: settings.resetTimeline,
      groups: (context) => [
        SettingsGroup(
          title: '年份卡片',
          children: [
            SettingsChoice(
              icon: Icons.crop_portrait_outlined,
              title: '卡片样式',
              subtitle: '海报：封面墙铺满卡片，年份压在封面上；经典：年份和统计在封面下方',
              values: TimelineCard.values,
              selected: settings.timelineCard,
              label: (c) => c.label,
              onSelected: settings.setTimelineCard,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.calendar_view_month_outlined),
              title: const Text('按年代分组'),
              subtitle: const Text('每个年代以一条横幅封面墙开头'),
              value: settings.timelineDecades,
              onChanged: settings.setTimelineDecades,
            ),
          ],
        ),
        SettingsGroup(
          title: '封面墙',
          children: [
            SettingsChoice(
              icon: Icons.view_comfy_outlined,
              title: '排列',
              values: WallStyle.values,
              selected: settings.wallStyle,
              label: (s) => s.label,
              onSelected: settings.setWallStyle,
            ),
            SettingsChoice(
              icon: Icons.grid_on,
              title: '封面间距',
              values: WallGap.values,
              selected: settings.wallGap,
              label: (g) => g.label,
              onSelected: settings.setWallGap,
            ),
          ],
        ),
        SettingsGroup(
          title: '动画',
          children: [
            SettingsChoice(
              icon: Icons.animation,
              title: '封面动画',
              values: WallMotion.values,
              selected: settings.wallMotion,
              label: (m) => m.label,
              onSelected: settings.setWallMotion,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.zoom_in),
              title: const Text('悬停时放大'),
              subtitle: const Text('鼠标移到卡片上时封面墙略微放大，倾斜的封面墙同时摆正一些'),
              value: settings.wallZoom,
              onChanged: settings.setWallZoom,
            ),
            const SettingsNote('系统开启 “减少动画” 时，封面墙保持静止。'),
          ],
        ),
      ],
    );
  }
}
