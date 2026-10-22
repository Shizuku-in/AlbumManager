/// Option types of the user preferences (see `SettingsController`).
library;

/// Grid card width presets.
enum CardSize {
  small('小', 160),
  medium('中', 220),
  large('大', 300);

  const CardSize(this.label, this.maxExtent);
  final String label;
  final double maxExtent;
}

/// Optional details on a grid card (the title is always shown).
enum CardField {
  source('来源'),
  quality('高解析度标记'),
  artist('艺术家'),
  date('日期'),
  catalog('品番'),
  event('展会'),
  ripStatus('抓轨状态'),
  favorite('收藏');

  const CardField(this.label);
  final String label;
}

/// What the library search looks in.
enum SearchField {
  title('标题'),
  artist('艺术家'),
  folderName('文件夹名'),
  genre('流派'),
  catalog('品番'),
  event('展会'),
  trackTitle('音轨标题'),
  trackArtist('音轨艺术家');

  const SearchField(this.label);
  final String label;
}

/// How release dates (`YYYY`, `YYYY-MM` or `YYYY-MM-DD`) are shown.
enum DateStyle {
  iso('2024-03-15'),
  slash('2024/03/15'),
  chinese('2024年3月15日'),
  year('仅年份');

  const DateStyle(this.label);
  final String label;

  String? format(String? date) {
    if (date == null) return null;
    final p = date.split('-');
    return switch (this) {
      DateStyle.iso => date,
      DateStyle.slash => p.join('/'),
      DateStyle.chinese =>
        '${p[0]}年${p.length > 1 ? '${int.parse(p[1])}月' : ''}${p.length > 2 ? '${int.parse(p[2])}日' : ''}',
      DateStyle.year => p[0],
    };
  }
}

/// How the album page's 文件 tab lists files.
enum FileListMode {
  flat('平铺完整路径'),
  tree('保持目录层级');

  const FileListMode(this.label);
  final String label;
}

/// How [FileListMode.tree] shows folders.
enum FolderView {
  expanded('全部展开'),
  browse('逐层浏览');

  const FolderView(this.label);
  final String label;
}

/// How the timeline's year cards are laid out.
enum TimelineCard {
  poster('海报'),
  classic('经典');

  const TimelineCard(this.label);
  final String label;
}

/// Layout of the cover wall on the timeline's year cards.
enum WallStyle {
  tilted('倾斜'),
  flat('平铺');

  const WallStyle(this.label);
  final String label;
}

/// Spacing between the covers of the timeline's cover walls.
enum WallGap {
  spaced('留缝'),
  seamless('铺满');

  const WallGap(this.label);
  final String label;
}

/// How the timeline's cover walls move.
enum WallMotion {
  hover('悬停时滚动'),
  follow('跟随鼠标'),
  always('始终滚动'),
  off('静止');

  const WallMotion(this.label);
  final String label;
}

/// Navigation destinations the user can hide.
enum HideablePage {
  timeline('时间线'),
  stats('统计'),
  health('健康检查');

  const HideablePage(this.label);
  final String label;
}
