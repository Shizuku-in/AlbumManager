import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// One phase of a shared axis transition, t from 0 to 1. Shifts are in units
// of the slide distance, positive in the direction of travel.
double _exitOpacity(double t) => 1 - Easing.emphasizedAccelerate.transform(t);
double _exitShift(double t) => -Easing.emphasizedAccelerate.transform(t);
double _enterOpacity(double t) => Easing.emphasizedDecelerate.transform(t);
double _enterShift(double t) => 1 - Easing.emphasizedDecelerate.transform(t);

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
  SharedAxisSwitch({
    required TickerProvider vsync,
    int initial = 0,
    this.distance = 30,
    required this.onShownChanged,
  }) : shown = initial,
       _target = initial {
    controller =
        AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 300),
          value: 1,
        )..addListener(() {
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

  /// Where the old content starts leaving from: fully shown at rest, or as
  /// far as it had come in when a new selection interrupted its entrance.
  double _fromOpacity = 1, _fromShift = 0;

  void select(int target) {
    if (target == _target) return;
    _target = target;
    // Still fading the old content out: keep going, the new target is
    // picked up at the midpoint.
    if (controller.isAnimating && controller.value < _exitEnd) return;
    // Captured before the direction changes. Restarting from fully shown
    // would make content that was still fading in flash.
    _fromOpacity = opacity;
    _fromShift = shift;
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
    return v < _exitEnd
        ? _fromOpacity * _exitOpacity(v / _exitEnd)
        : _enterOpacity((v - _exitEnd) / (1 - _exitEnd));
  }

  /// Offset along the axis: towards negative while leaving, from positive
  /// while entering (reversed when moving to a lower index).
  double get shift {
    final v = controller.value;
    if (v < _exitEnd) {
      // From where the content is to a full exit.
      final t = Easing.emphasizedAccelerate.transform(v / _exitEnd);
      return lerpDouble(_fromShift, -_direction * distance, t)!;
    }
    return _direction * distance * _enterShift((v - _exitEnd) / (1 - _exitEnd));
  }

  void dispose() => controller.dispose();
}

/// M3 shared axis X between pages: the old page fades out sliding left, then
/// the new one fades in from the right; going back plays it in reverse.
///
/// Computed from the animation values alone. The framework transitions pick
/// forward / reverse curves by animation status, so a transition interrupted
/// by a quick back or a new push (the page below hops from the popping
/// route's animation onto the pushed one's) switched curves mid-way and the
/// pages jumped. Here a reversed or hopped animation carries on from where
/// the page is, and the phases never overlap: a page is shown only while
/// the route above it is in its first half.
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  static const _distance = 30.0;

  /// Exit and enter take half each, so going back mirrors going forward.
  static const _split = 0.5;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AnimatedBuilder(
    animation: Listenable.merge([animation, secondaryAnimation]),
    builder: (context, child) {
      final a = animation.value, s = secondaryAnimation.value;
      // This page coming in, then the next page coming in over it.
      var opacity = a < _split ? 0.0 : _enterOpacity((a - _split) / _split);
      var shift = a < _split ? 1.0 : _enterShift((a - _split) / _split);
      if (s > 0) {
        opacity *= s < _split ? _exitOpacity(s / _split) : 0;
        shift += s < _split ? _exitShift(s / _split) : -1;
      }
      return Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(shift * _distance, 0),
          child: child,
        ),
      );
    },
    child: child,
  );
}
