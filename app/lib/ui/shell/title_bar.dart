import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Material window title bar (the native one is hidden): drag / double-click
/// to move and maximize, plus minimize / maximize / close icon buttons.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  static const height = 40.0;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    // 36 × 36 buttons with 18 px icons.
    const density = VisualDensity(horizontal: -1, vertical: -1);
    return Material(
      color: cs.surfaceContainerLow,
      child: SizedBox(
        height: TitleBar.height,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(Icons.album, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Text('Album Manager', style: t.textTheme.titleSmall),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '最小化',
              visualDensity: density,
              iconSize: 18,
              onPressed: windowManager.minimize,
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: _maximized ? '还原' : '最大化',
              visualDensity: density,
              iconSize: 18,
              onPressed: () => _maximized
                  ? windowManager.unmaximize()
                  : windowManager.maximize(),
              icon: Icon(_maximized ? Icons.filter_none : Icons.crop_square),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '关闭',
              visualDensity: density,
              iconSize: 18,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.hovered)
                      ? cs.errorContainer
                      : null,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.hovered)
                      ? cs.onErrorContainer
                      : null,
                ),
              ),
              onPressed: windowManager.close,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
