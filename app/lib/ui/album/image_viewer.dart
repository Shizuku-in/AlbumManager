import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/ui/common/cover_image.dart';
import 'package:album_manager/util/format.dart';
import 'package:album_manager/util/system.dart';

/// M3 full-screen dialog for browsing scans. Uses 2400px previews generated
/// by Rust, since originals can be several hundred MB.
class ImageViewer extends StatefulWidget {
  final List<ImageItem> images;
  final int initial;
  const ImageViewer({super.key, required this.images, required this.initial});

  static Future<void> show(
    BuildContext context,
    List<ImageItem> images,
    int index,
  ) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog.fullscreen(
        child: ImageViewer(images: images, initial: index),
      ),
    );
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = (_index + d).clamp(0, widget.images.length - 1);
    _page.animateToPage(
      n,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.images[_index];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              '${_index + 1} / ${widget.images.length}  ·  ${img.path.split(RegExp(r'[\\/]')).last}',
            ),
            actions: [
              Center(
                child: Text(
                  formatSize(img.size),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '用默认程序打开原图',
                onPressed: () => openPath(img.path),
                icon: const Icon(Icons.open_in_new),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LazyThumb(
                      path: widget.images[i].path,
                      size: 2400,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              if (_index > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton.filledTonal(
                      tooltip: '上一张',
                      onPressed: () => _go(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
              if (_index < widget.images.length - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton.filledTonal(
                      tooltip: '下一张',
                      onPressed: () => _go(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
