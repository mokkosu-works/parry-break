import 'dart:ui' as ui;

/// 光のにじみ (ぼかし) を、事前に描いた放射グラデーションの画像で表す。
/// Canvas のぼかしフィルタは重いため、色を掛けて加算合成で重ねる。
class GlowSprite {
  GlowSprite._(this.image);
  final ui.Image image;

  static const _size = 64;

  factory GlowSprite.create() {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    const r = _size / 2;
    c.drawCircle(
      const ui.Offset(r, r),
      r,
      ui.Paint()
        ..shader = ui.Gradient.radial(const ui.Offset(r, r), r, const [
          ui.Color(0xFFFFFFFF),
          ui.Color(0x66FFFFFF),
          ui.Color(0x00FFFFFF),
        ], const [0, 0.35, 1]),
    );
    return GlowSprite._(rec.endRecording().toImageSync(_size, _size));
  }

  final ui.Paint _paint = ui.Paint()..blendMode = ui.BlendMode.plus;

  /// 中心 ([x], [y])、幅 [w] × 高さ [h] の光を [color] で描く。
  void draw(ui.Canvas canvas, double x, double y, double w, double h, ui.Color color, {double opacity = 1}) {
    _paint.colorFilter = ui.ColorFilter.mode(
        color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0)), ui.BlendMode.modulate);
    canvas.drawImageRect(
      image,
      const ui.Rect.fromLTWH(0, 0, 64, 64),
      ui.Rect.fromCenter(center: ui.Offset(x, y), width: w, height: h),
      _paint,
    );
  }
}
