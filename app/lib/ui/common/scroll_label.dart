import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Shows a bubble next to the scrollbar thumb while it is dragged, describing the
/// content at the top of the viewport (e.g. the year), like a photo gallery's
/// fast-scroll label.
///
/// The bubble is a teardrop whose sharp corner points at the thumb, with a
/// large primary line (e.g. year) over an optional small one (e.g. month).
///
/// Items opt in by wrapping themselves in [MetaData] whose `metaData` is a [T];
/// the item at the top edge of the viewport is looked up by layout position.
typedef ScrollLabelText = ({String main, String? sub});

class ScrollLabel<T> extends StatefulWidget {
  final ScrollLabelText? Function(T item) labelOf;

  /// Height of the pinned header covering the top of the viewport.
  final double topInset;
  final Widget child;
  const ScrollLabel({super.key, required this.labelOf, this.topInset = 64, required this.child});

  @override
  State<ScrollLabel<T>> createState() => _ScrollLabelState<T>();
}

class _ScrollLabelState<T> extends State<ScrollLabel<T>> {
  static const _fade = Duration(milliseconds: 150);
  static const _linger = Duration(milliseconds: 500);
  static const _bubbleSize = 56.0;

  final _childKey = GlobalKey();
  final _label = ValueNotifier<ScrollLabelText?>(null);
  final _top = ValueNotifier<double>(0);
  final _visible = ValueNotifier<bool>(false);
  Timer? _hide;
  bool _scheduled = false;
  bool _thumbDragging = false;

  @override
  void dispose() {
    _hide?.cancel();
    _label.dispose();
    _top.dispose();
    _visible.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      // Only scrollbar thumb drags show the bubble. RawScrollbar starts its
      // drag without a pointer kind, whereas the Scrollable's own drag
      // gestures (touch, trackpad) always carry one; wheel scrolls have none.
      final d = n.dragDetails;
      _thumbDragging = d != null && d.kind == null;
    } else if (n is ScrollUpdateNotification && _thumbDragging) {
      _hide?.cancel();
      // Position from the metrics right away so the bubble moves in the same
      // frame as the thumb; the label needs the new layout, so it follows.
      _follow(n.metrics);
      if (!_scheduled) {
        _scheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _scheduled = false;
          if (!mounted) return;
          final label = _labelAtTop();
          if (label != null) _label.value = label;
          _visible.value = _label.value != null;
        });
      }
    } else if (n is ScrollEndNotification) {
      _thumbDragging = false;
      _hide?.cancel();
      _hide = Timer(_linger, () => _visible.value = false);
    }
    return false;
  }

  void _follow(ScrollMetrics m) {
    final extent = m.maxScrollExtent - m.minScrollExtent;
    if (extent <= 0) return;
    // Mirror the scrollbar's thumb geometry; the bubble's tip (right point)
    // sits at the thumb's center.
    final viewport = m.viewportDimension;
    final thumb = math.max(18.0, viewport * viewport / (viewport + extent));
    final fraction = ((m.pixels - m.minScrollExtent) / extent).clamp(0.0, 1.0);
    final center = fraction * (viewport - thumb) + thumb / 2;
    _top.value = (center - _bubbleSize / 2).clamp(0.0, math.max(0.0, viewport - _bubbleSize));
  }

  ScrollLabelText? _labelAtTop() {
    final root = _childKey.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.hasSize) return null;
    // Not a hit test: Scrollable ignores pointers on its content while a
    // drag or animation is in progress. Walk the laid-out items instead and
    // take the top-left one still visible below the header.
    final probe = widget.topInset + 8;
    RenderMetaData? best;
    var bestRect = Rect.zero;
    void visit(RenderObject o) {
      if (o is RenderMetaData && o.metaData is T) {
        if (!o.hasSize) return;
        final r = MatrixUtils.transformRect(o.getTransformTo(root), Offset.zero & o.size);
        final better = best == null || r.top < bestRect.top - 0.5 || ((r.top - bestRect.top).abs() <= 0.5 && r.left < bestRect.left);
        if (r.bottom > probe && better) {
          best = o;
          bestRect = r;
        }
        return;
      }
      o.visitChildren(visit);
    }

    root.visitChildren(visit);
    return best == null ? null : widget.labelOf(best!.metaData as T);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = t.colorScheme.onPrimaryContainer;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: KeyedSubtree(key: _childKey, child: widget.child),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _top,
          builder: (context, top, child) => Positioned(top: top, right: 14, child: child!),
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _visible,
              // Grows out of / shrinks into the tip pointing at the thumb.
              builder: (context, visible, child) => AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: _fade,
                curve: Curves.easeOut,
                child: AnimatedScale(scale: visible ? 1 : 0.5, alignment: Alignment.centerRight, duration: _fade, curve: Curves.easeOutCubic, child: child),
              ),
              child: Material(
                color: t.colorScheme.primaryContainer,
                elevation: 3,
                shape: const _TeardropBorder(),
                child: AnimatedSize(
                  duration: _fade,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerRight,
                  child: Container(
                    height: _bubbleSize,
                    constraints: const BoxConstraints(minWidth: _TeardropBorder.minWidth, maxWidth: 240),
                    // Snug around the text; it may run a little into the base of the tip.
                    padding: const EdgeInsets.only(left: 10, right: 12 + _TeardropBorder.tipLength / 2),
                    child: ValueListenableBuilder<ScrollLabelText?>(
                      valueListenable: _label,
                      builder: (context, label, _) => AnimatedSwitcher(
                        duration: _fade,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                            child: child,
                          ),
                        ),
                        // Keep old and new centered on top of each other.
                        layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, ?current]),
                        child: label == null ? const SizedBox.shrink() : _content(t, fg, label),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(ThemeData t, Color fg, ScrollLabelText l) {
    final short = l.main.characters.length <= 4;
    final main = (short ? t.textTheme.titleLarge : t.textTheme.titleMedium)!.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.1);
    return Column(
      key: ValueKey(l),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.main, maxLines: 1, overflow: TextOverflow.ellipsis, style: main),
        if (l.sub != null) Text(l.sub!, maxLines: 1, style: t.textTheme.labelMedium?.copyWith(color: fg)),
      ],
    );
  }
}

/// A stadium whose right end narrows into a point, like a fast-scroll
/// teardrop rotated to point right. The tip's flanks are tangent to the right
/// end circle at ±45°, so a square bubble is exactly a rotated teardrop.
class _TeardropBorder extends ShapeBorder {
  const _TeardropBorder();

  static const _r = _ScrollLabelState._bubbleSize / 2;

  /// How far the point sticks out past the end circle.
  static const tipLength = _r * (math.sqrt2 - 1);
  static const minWidth = _r * (1 + math.sqrt2);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = rect.height / 2;
    final cy = rect.center.dy;
    final left = rect.left + r;
    final right = math.max(left, rect.right - r * math.sqrt2);
    final d = r / math.sqrt2;
    return Path()
      ..moveTo(right + d, cy - d)
      ..arcToPoint(Offset(right, rect.top), radius: Radius.circular(r), clockwise: false)
      ..lineTo(left, rect.top)
      ..arcToPoint(Offset(left, rect.bottom), radius: Radius.circular(r), clockwise: false)
      ..lineTo(right, rect.bottom)
      ..arcToPoint(Offset(right + d, cy + d), radius: Radius.circular(r), clockwise: false)
      ..lineTo(right + r * math.sqrt2, cy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
