/// Display labels, icons and colors for the model enums.
library;

import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/theme/app_colors.dart';

CustomColor _error(ColorScheme s) =>
    CustomColor(s.error, s.onError, s.errorContainer, s.onErrorContainer);
CustomColor _neutral(ColorScheme s) => CustomColor(
  s.outline,
  s.surface,
  s.surfaceContainerHighest,
  s.onSurfaceVariant,
);
CustomColor _primary(ColorScheme s) => CustomColor(
  s.primary,
  s.onPrimary,
  s.primaryContainer,
  s.onPrimaryContainer,
);
CustomColor _secondary(ColorScheme s) => CustomColor(
  s.secondary,
  s.onSecondary,
  s.secondaryContainer,
  s.onSecondaryContainer,
);

extension OnlineSourceX on OnlineSource {
  String get label => switch (this) {
    OnlineSource.musicBrainz => 'MusicBrainz',
    OnlineSource.bangumi => 'Bangumi',
    OnlineSource.ctdb => 'CueTools 数据库',
  };

  String get iconAsset => switch (this) {
    OnlineSource.musicBrainz => 'assets/icons/musicbrainz.svg',
    OnlineSource.bangumi => 'assets/icons/bangumi.svg',
    OnlineSource.ctdb => 'assets/icons/ctdb.svg',
  };

  String get description => switch (this) {
    OnlineSource.musicBrainz => '按光盘 ID、品番、标题搜索，覆盖商业 CD 较全',
    OnlineSource.bangumi => '按标题搜索，动画 / 游戏原声与同人音乐，含展会',
    OnlineSource.ctdb => '按光盘目录匹配，汇总 MusicBrainz、Discogs、FreeDB',
  };
}

extension SourceX on AlbumSource {
  String get label => switch (this) {
    AlbumSource.cdRip => 'CD 抓轨',
    AlbumSource.digital => '数字发行',
    AlbumSource.discImage => '光盘镜像',
    AlbumSource.unknown => '未知',
  };
  String get short => switch (this) {
    AlbumSource.cdRip => 'CD',
    AlbumSource.digital => 'WEB',
    AlbumSource.discImage => 'ISO',
    AlbumSource.unknown => '?',
  };
  IconData get icon => switch (this) {
    AlbumSource.cdRip => Icons.album_outlined,
    AlbumSource.digital => Icons.cloud_download_outlined,
    AlbumSource.discImage => Icons.save_outlined,
    AlbumSource.unknown => Icons.help_outline,
  };
  CustomColor tone(BuildContext c) {
    final a = AppColors.of(c);
    return switch (this) {
      AlbumSource.cdRip => a.cd,
      AlbumSource.digital => a.digital,
      AlbumSource.discImage => a.disc,
      AlbumSource.unknown => _neutral(Theme.of(c).colorScheme),
    };
  }
}

extension QualityX on AudioQuality {
  String get label => switch (this) {
    AudioQuality.lossy => '有损',
    AudioQuality.lossless => '无损',
    AudioQuality.hiRes => 'Hi-Res',
    AudioQuality.dsd => 'DSD',
    AudioQuality.unknown => '未知',
  };
  CustomColor tone(BuildContext c) {
    final a = AppColors.of(c);
    final s = Theme.of(c).colorScheme;
    return switch (this) {
      AudioQuality.hiRes => a.hiRes,
      AudioQuality.dsd => a.dsd,
      AudioQuality.lossless => _secondary(s),
      _ => _neutral(s),
    };
  }
}

extension RipStatusX on RipStatus {
  String get label => switch (this) {
    RipStatus.notApplicable => '非抓轨',
    RipStatus.noLog => '无日志',
    RipStatus.perfect => '完美',
    RipStatus.good => '无错误',
    RipStatus.warning => '有问题设置',
    RipStatus.error => '有错误',
    RipStatus.unknown => '无法判定',
  };
  String get description => switch (this) {
    RipStatus.notApplicable => '不是 CD 抓轨资源',
    RipStatus.noLog => '没有抓轨日志',
    RipStatus.perfect => '日志检查无问题，AccurateRip / CTDB 全部校验通过',
    RipStatus.good => '日志检查无问题，但 AccurateRip / CTDB 未能确认',
    RipStatus.warning => '抓轨设置有问题（如未用安全模式、偏移不对），或日志签名不符',
    RipStatus.error => '日志报告读取错误、可疑位置或 CRC 不一致',
    RipStatus.unknown => '日志格式无法判定结果',
  };
  IconData get icon => switch (this) {
    RipStatus.perfect => Icons.verified_outlined,
    RipStatus.good => Icons.check_circle_outline,
    RipStatus.warning => Icons.warning_amber_outlined,
    RipStatus.error => Icons.error_outline,
    RipStatus.noLog => Icons.description_outlined,
    _ => Icons.help_outline,
  };
  CustomColor tone(BuildContext c) {
    final a = AppColors.of(c);
    final s = Theme.of(c).colorScheme;
    return switch (this) {
      RipStatus.perfect => a.success,
      RipStatus.good => _primary(s),
      RipStatus.warning => a.warning,
      RipStatus.error => _error(s),
      _ => _neutral(s),
    };
  }
}

extension LogChecksumX on LogChecksum {
  /// Null when the ripper doesn't sign its logs.
  String? get label => switch (this) {
    LogChecksum.valid => '有效',
    LogChecksum.invalid => '不符，日志可能被修改过',
    LogChecksum.missing => '无签名',
    LogChecksum.notApplicable => null,
  };
}

extension IssueKindX on IssueKind {
  String get label => switch (this) {
    IssueKind.missingCover => '缺少封面',
    IssueKind.cueEncoding => 'CUE 非 UTF-8',
    IssueKind.cueMissingBom => 'CUE 缺少 BOM',
    IssueKind.cueMissingFile => 'CUE 引用失效',
    IssueKind.ripErrors => '抓轨错误',
    IssueKind.ripUnverified => '抓轨设置问题',
    IssueKind.missingLog => '缺少日志',
    IssueKind.nonStandardName => '命名不规范',
  };
  IconData get icon => switch (this) {
    IssueKind.missingCover => Icons.hide_image_outlined,
    IssueKind.cueEncoding => Icons.translate,
    IssueKind.cueMissingBom => Icons.text_snippet_outlined,
    IssueKind.cueMissingFile => Icons.link_off,
    IssueKind.ripErrors => Icons.report_outlined,
    IssueKind.ripUnverified => Icons.gpp_maybe_outlined,
    IssueKind.missingLog => Icons.description_outlined,
    IssueKind.nonStandardName => Icons.drive_file_rename_outline,
  };
  CustomColor tone(BuildContext c) {
    final a = AppColors.of(c);
    final s = Theme.of(c).colorScheme;
    return switch (this) {
      IssueKind.ripErrors => _error(s),
      IssueKind.ripUnverified || IssueKind.cueMissingFile => a.warning,
      IssueKind.cueEncoding || IssueKind.cueMissingBom => _primary(s),
      _ => _neutral(s),
    };
  }
}

Color? accentOf(AlbumSummary a) =>
    a.accentColor == null ? null : Color(a.accentColor!);
