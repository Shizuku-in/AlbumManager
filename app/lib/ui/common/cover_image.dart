import 'dart:io';

import 'package:flutter/material.dart';

import 'package:album_manager/src/rust/api/library.dart' as api;

/// Tonal box with an album icon, standing in for a missing cover.
class CoverPlaceholder extends StatelessWidget {
  final double iconSize;
  const CoverPlaceholder({super.key, this.iconSize = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_outlined,
          color: cs.onSurfaceVariant,
          size: iconSize,
        ),
      ),
    );
  }
}

/// Album cover from the cached thumbnail, with a tonal placeholder.
class CoverImage extends StatelessWidget {
  final String? path;
  final double radius;
  final int? cacheWidth;
  const CoverImage({super.key, this.path, this.radius = 12, this.cacheWidth});

  static ImageProvider _provider(String path, int? cacheWidth) =>
      ResizeImage.resizeIfNeeded(cacheWidth, null, FileImage(File(path)));

  /// Decodes a cover ahead of time, so a [CoverImage] with the same
  /// [cacheWidth] shows it in the first frame it is built.
  static Future<void> precache(
    BuildContext context,
    String? path, {
    int? cacheWidth,
  }) => path == null
      ? Future.value()
      : precacheImage(_provider(path, cacheWidth), context);

  @override
  Widget build(BuildContext context) {
    const placeholder = CoverPlaceholder();
    final image = path == null
        ? placeholder
        : Image(
            image: _provider(path!, cacheWidth),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => placeholder,
          );
    // Square corners need no clip layer (the parent card already clips).
    return radius == 0
        ? image
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// Thumbnail of an arbitrary image (scans), generated on demand in Rust.
class LazyThumb extends StatefulWidget {
  final String path;
  final int size;
  final BoxFit fit;
  const LazyThumb({
    super.key,
    required this.path,
    this.size = 360,
    this.fit = BoxFit.cover,
  });

  @override
  State<LazyThumb> createState() => _LazyThumbState();
}

class _LazyThumbState extends State<LazyThumb> {
  late Future<String> _f = api.getThumbnail(
    path: widget.path,
    maxSize: widget.size,
  );

  @override
  void didUpdateWidget(LazyThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.size != widget.size) {
      _f = api.getThumbnail(path: widget.path, maxSize: widget.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.file(
          File(snap.data!),
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
