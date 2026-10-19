import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/album/text_file_dialog.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

IconData _fileIcon(String rel) {
  final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'flac' ||
    'wav' ||
    'ape' ||
    'tak' ||
    'tta' ||
    'dsf' ||
    'mp3' ||
    'm4a' ||
    'wv' => Icons.audio_file_outlined,
    'jpg' ||
    'jpeg' ||
    'png' ||
    'bmp' ||
    'tif' ||
    'tiff' ||
    'webp' => Icons.image_outlined,
    'cue' => Icons.queue_music,
    'log' || 'txt' => Icons.article_outlined,
    'iso' || 'mds' || 'm2ts' => Icons.album_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

List<Widget> filesSlivers(BuildContext context, Album a) {
  final root = a.summary.path;
  final t = Theme.of(context);
  return [
    SliverList.builder(
      itemCount: a.files.length,
      itemBuilder: (context, i) {
        final f = a.files[i];
        final full = '$root\\${f.relPath.replaceAll('/', '\\')}';
        final isText = RegExp(
          r'\.(log|cue|txt|m3u8?|lrc|accurip)$',
          caseSensitive: false,
        ).hasMatch(f.relPath);
        return ListTile(
          dense: true,
          leading: Icon(_fileIcon(f.relPath)),
          title: Text(f.relPath, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(formatSize(f.size), style: t.textTheme.bodySmall),
          onTap: () =>
              isText ? showTextFile(context, full) : revealInFileManager(full),
        );
      },
    ),
  ];
}
