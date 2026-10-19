import 'package:flutter/widgets.dart';

/// Scroll controller whose mouse-wheel steps animate instead of jumping.
///
/// Consecutive wheel notches accumulate onto the running animation's target,
/// so fast scrolling stays fluid. Touchpad pans and scrollbar drags are not
/// affected (they don't go through [ScrollPosition.pointerScroll]).
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.debugLabel});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  static const _duration = Duration(milliseconds: 220);

  /// Where the current wheel animation is heading.
  double? _target;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return super.pointerScroll(delta);
    final from = _target ?? pixels;
    final target = (from + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == from) return;
    _target = target;
    animateTo(
      target,
      duration: _duration,
      curve: Curves.easeOutCubic,
    ).whenComplete(() {
      if (_target == target) _target = null;
    });
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // Any other interaction (drag, scrollbar, programmatic jump) cancels the
    // accumulated wheel target.
    if (newActivity is! DrivenScrollActivity) _target = null;
    super.beginActivity(newActivity);
  }
}
