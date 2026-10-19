import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shifts a sliver horizontally when painting and hit testing, without
/// affecting layout (the sliver counterpart of [Transform.translate] along
/// the cross axis of a vertical scroll view).
class SliverTranslateX extends SingleChildRenderObjectWidget {
  final double dx;
  const SliverTranslateX({super.key, required this.dx, required Widget sliver}) : super(child: sliver);

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSliverTranslateX(dx);

  @override
  void updateRenderObject(BuildContext context, RenderSliverTranslateX renderObject) => renderObject.dx = dx;
}

class RenderSliverTranslateX extends RenderProxySliver {
  RenderSliverTranslateX(this._dx);

  double _dx;
  set dx(double v) {
    if (v == _dx) return;
    _dx = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && child!.geometry!.visible) context.paintChild(child!, offset + Offset(_dx, 0));
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) => transform.translateByDouble(_dx, 0, 0, 1);

  @override
  bool hitTestChildren(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    return child != null &&
        child!.geometry!.hitTestExtent > 0 &&
        child!.hitTest(result, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition - _dx);
  }
}
