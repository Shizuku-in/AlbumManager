/// Library browsing options: source filter and sort order.
library;

import 'package:album_manager/src/rust/third_party/album_model.dart';

enum SourceFilter { all, cdRip, digital, hiRes, dsd, discImage }

enum SortMode { dateDesc, dateAsc, addedDesc, title, artist, size }

extension SortModeX on SortMode {
  String get label => switch (this) {
        SortMode.dateDesc => '发行日期（新→旧）',
        SortMode.dateAsc => '发行日期（旧→新）',
        SortMode.addedDesc => '最近添加',
        SortMode.title => '标题',
        SortMode.artist => '艺术家',
        SortMode.size => '占用空间',
      };
  bool get groupsByYear => this == SortMode.dateDesc || this == SortMode.dateAsc;
}

extension SourceFilterX on SourceFilter {
  String get label => switch (this) {
        SourceFilter.all => '全部',
        SourceFilter.cdRip => 'CD 抓轨',
        SourceFilter.digital => '数字发行',
        SourceFilter.hiRes => 'Hi-Res',
        SourceFilter.dsd => 'DSD',
        SourceFilter.discImage => '光盘镜像',
      };
  bool matches(AlbumSummary a) => switch (this) {
        SourceFilter.all => true,
        SourceFilter.cdRip => a.source == AlbumSource.cdRip,
        SourceFilter.digital => a.source == AlbumSource.digital,
        SourceFilter.hiRes => a.quality == AudioQuality.hiRes,
        SourceFilter.dsd => a.quality == AudioQuality.dsd,
        SourceFilter.discImage => a.source == AlbumSource.discImage,
      };
}
