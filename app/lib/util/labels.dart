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
    RipStatus.warning => '未完全校验',
    RipStatus.error => '有错误',
    RipStatus.unknown => '无法判定',
  };
  String get description => switch (this) {
    RipStatus.notApplicable => '不是 CD 抓轨资源',
    RipStatus.noLog => '没有抓轨日志',
    RipStatus.perfect => '无读取错误，AccurateRip / CTDB 全部校验通过',
    RipStatus.good => '无读取错误，但数据库中无校验记录',
    RipStatus.warning => '部分音轨未能通过 AccurateRip 校验',
    RipStatus.error => '日志报告读取错误或 CRC 不一致',
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

extension IssueKindX on IssueKind {
  String get label => switch (this) {
    IssueKind.missingCover => '缺少封面',
    IssueKind.cueEncoding => 'CUE 非 UTF-8',
    IssueKind.cueMissingFile => 'CUE 引用失效',
    IssueKind.ripErrors => '抓轨错误',
    IssueKind.ripUnverified => '未通过校验',
    IssueKind.missingLog => '缺少日志',
    IssueKind.nonStandardName => '命名不规范',
  };
  IconData get icon => switch (this) {
    IssueKind.missingCover => Icons.hide_image_outlined,
    IssueKind.cueEncoding => Icons.translate,
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
      IssueKind.cueEncoding => _primary(s),
      _ => _neutral(s),
    };
  }
}

Color? accentOf(AlbumSummary a) =>
    a.accentColor == null ? null : Color(a.accentColor!);
