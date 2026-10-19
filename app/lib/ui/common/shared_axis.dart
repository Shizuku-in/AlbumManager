import 'package:flutter/material.dart';

/// M3 shared axis transition between indexed contents (tabs, destinations):
/// the old content fades out sliding away (first third), then the new one
/// fades in from the side it comes from. The caller applies [shift] along
/// the axis of its options: x for tabs side by side (shared axis X), y for
/// a vertical navigation rail (shared axis Y).
///
/// [shown] trails the selection by the exit half, so the caller keeps
/// rendering the old content until [onShownChanged] fires.
///
/// With a [distance] of 0 nothing slides: M3 fade through, for switching
/// between layouts with no spatial relationship (without its scale, which
/// blurs text).
class SharedAxisSwitch {
  SharedAxisSwitch({required TickerProvider vsync, int initial = 0, this.distance = 30, required this.onShownChanged}) : shown = initial, _target = initial {
    controller = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 300), value: 1)
      ..addListener(() {
        if (controller.value >= _exitEnd && shown != _target) {
          shown = _target;
          onShownChanged();
        }
      });
  }

  static const _exitEnd = 1 / 3;

  /// How far the content slides, in logical pixels.
  final double distance;

  late final AnimationController controller;
  final VoidCallback onShownChanged;

  /// Index whose content is on screen.
  int shown;
  int _target;

  /// +1 when moving to a higher index, -1 to a lower one.
  int _direction = 1;

  void select(int target) {
    if (target == _target) return;
    _target = target;
    // Still fading the old content out: keep going, the new target is
    // picked up at the midpoint.
    if (controller.isAnimating && controller.value < _exitEnd) return;
    _direction = target > shown ? 1 : -1;
    controller.forward(from: 0);
  }

  /// Shows [index] without animating (e.g. when the selection falls back to
  /// another option on its own). Ignored mid-transition.
  void jump(int index) {
    if (controller.isAnimating) return;
    shown = _target = index;
  }

  double get opacity {
    final v = controller.value;
    return v < _exitEnd ? 1 - Easing.emphasizedAccelerate.transform(v / _exitEnd) : Easing.emphasizedDecelerate.transform((v - _exitEnd) / (1 - _exitEnd));
  }

  /// Offset along the axis: towards negative while leaving, from positive
  /// while entering (reversed when moving to a lower index).
  double get shift {
    final v = controller.value;
    return v < _exitEnd
        ? -_direction * distance * Easing.emphasizedAccelerate.transform(v / _exitEnd)
        : _direction * distance * (1 - Easing.emphasizedDecelerate.transform((v - _exitEnd) / (1 - _exitEnd)));
  }

  void dispose() => controller.dispose();
}
