import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import '../core/blocks/turret.dart';
import '../core/core.dart';
import '../l10n/app_localizations.dart';
import 'block_painters.dart';
import 'fx.dart';
import 'item_painter.dart';
import 'palette.dart';
import 'pixel.dart';
import 'text_cache.dart';

/// 説明の翻訳キー (`intro.*`) の文言。知らないキーなら null。[loop] は `intro.loop` の周回数。
/// [scoreTarget] は `intro.score` の目標スコア (スコア目標の面でなければ null で、`intro.score` も null になる)。
/// [parryButton] はレール方式 (PARRY ボタンで弾く) のとき true で、`intro.parry` をボタン向けの文言にする。
String? introText(
  AppLocalizations l10n,
  String? key, {
  int loop = 1,
  int? scoreTarget,
  bool parryButton = false,
}) => switch (key) {
  'intro.keystone' => l10n.introKeystone,
  'intro.turret' => l10n.introTurret,
  'intro.explosive' => l10n.introExplosive,
  'intro.reflector' => l10n.introReflector,
  'intro.magnet' => l10n.introMagnet,
  'intro.splitter' => l10n.introSplitter,
  'intro.mirror' => l10n.introMirror,
  'intro.wall' => l10n.introWall,
  'intro.spread' => l10n.introSpread,
  'intro.gatling' => l10n.introGatling,
  'intro.ring' => l10n.introRing,
  'intro.spiral' => l10n.introSpiral,
  'intro.sniper' => l10n.introSniper,
  'intro.loop' => l10n.introLoop('$loop'),
  'intro.parry' => parryButton ? l10n.introParryButton : l10n.introParry,
  'intro.pierce' => l10n.introPierce,
  'intro.feverTime' => l10n.introFeverTime,
  'intro.survive' => l10n.introSurvive,
  'intro.score' =>
    scoreTarget == null ? null : l10n.introScore(formatScore(scoreTarget)),
  _ => null,
};

/// 盤面 (1200×720) を描く。HUD・コールアウト・バナー・ラウンドクリアの表示も含む。
///
/// 見た目は 16 色のドット絵 (1 ドット = [Dot.px])。発光やぼかしは使わず、
/// 陰影は 1 ドットの縁、影は 1 ドットずらしの硬い影、グラデーションはディザや段階の帯で表す。
/// 位置は補間して滑らかに動かす (ドットの格子には合わせない)。
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.world,
    required this.fx,
    required this.alpha,
    required this.time,
    required this.text,
    required this.blockPainters,
    required this.l10n,
    required this.highQuality,
    required super.repaint,
    this.attract = false,
    this.parryButton = false,
  });

  final World world;
  final FxState fx;

  /// ステップ間の補間の割合 (0〜1)。
  final double Function() alpha;

  /// 実時間 (秒)。
  final double Function() time;
  final TextCache text;
  final BlockPainterRegistry blockPainters;
  final AppLocalizations l10n;

  /// 床のディザなど、なくても遊べる飾りを描くか。
  final bool highQuality;

  /// タイトル画面のデモ表示。HUD・文字の演出を描かない。
  final bool attract;

  /// 発射とパリィを PARRY ボタンでする操作方式 (レール方式) か。
  /// 案内を「TAP」ではなく PARRY ボタンを指す文にする。設定の変更に合わせて書き換える。
  bool parryButton;

  static const _w = Field.width, _h = Field.height, _d = Dot.px;

  /// HUD の右端に置くポーズボタンの場所 (盤面の座標)。ボタンそのものは game_screen.dart が重ねる。
  static const pauseButton = Rect.fromLTWH(_w - 56, 6, 44, 44);

  /// HUD のラベル (SCORE・ROUND・FEVER TIME の残り秒数など) が画面上でこれより小さくならないようにする (pt)。
  static const hudLabelMinPt = 11.0;

  /// HUD のラベルの大きさ (盤面の座標)。[scale] は盤面の 1 単位あたりの画面のピクセル数。
  /// 倍率が十分な端末では今までどおり 16。倍率が小さい端末 (スマホの横画面) では、画面上で
  /// [hudLabelMinPt] 以上になるように大きくする。下の数値 (24) と重ならないよう 24 までにする。
  static double hudLabelSize(double scale) =>
      (hudLabelMinPt / scale).ceilToDouble().clamp(16.0, 24.0);

  static final _floor = DitherFloor(const Rect.fromLTWH(0, 440, _w, _h - 440));
  final _rnd = math.Random();

  late Canvas _c;
  late double _t, _a, _ox, _oy;

  /// HUD のラベルの大きさ ([hudLabelSize]) と、縦の中心。
  /// 大きくしたときは、下の端がコンボのメーターの目盛り (y = 24) より上に収まるように上へずらす。
  late double _label, _labelY;

  /// 盤面の 1 単位あたりの画面のピクセル数。
  late double _scale;

  /// 帯の説明文が画面上でこれより小さくならないようにする (pt)。
  static const bannerSubMinPt = 11.0;

  /// 帯の説明文の大きさ (盤面の座標)。倍率が十分な端末では今までどおり 15。
  /// 倍率が小さい端末 (スマホの横画面) では、画面上で [bannerSubMinPt] 以上になるように大きくする。
  static double bannerSubSize(double scale) =>
      math.max(15.0, (bannerSubMinPt / scale).ceilToDouble());

  /// 帯の説明文を折り返すときの 1 行の幅の上限 (盤面の座標)。
  static const bannerSubWidth = _w - 80;

  double _lerp(double a, double b) => a + (b - a) * _a;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _t = time();
    _a = alpha().clamp(0.0, 1.0);
    final w = world;
    _ox = _lerp(w.form.prevOx, w.form.ox);
    _oy = _lerp(w.form.prevOy, w.form.oy);
    _scale = size.width / _w;
    _label = hudLabelSize(_scale);
    _labelY = math.min(14.0, 24 - _label / 2);
    canvas.save();
    canvas.scale(size.width / _w);
    canvas.clipRect(const Rect.fromLTWH(0, 0, _w, _h));
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      pixelPaint(w.od ? Dot.odBg : Dot.ink),
    );
    canvas.save();
    if (fx.shake > 0) {
      // 揺れもドット単位で動かす
      double q(double v) => (v / 2).roundToDouble() * 2;
      canvas.translate(
        q((_rnd.nextDouble() - 0.5) * fx.shake),
        q((_rnd.nextDouble() - 0.5) * fx.shake),
      );
    }
    _background();
    _field();
    for (final b in w.blocks) {
      if (b.behavior.influencesBalls) _magnetField(b);
    }
    final ctx = BlockPaintContext(
      canvas,
      text,
      _t,
      fx.blockColor,
      calm: fx.reduceEffects,
    );
    for (final b in w.blocks) {
      _block(ctx, b, Rect.fromLTWH(b.x + _ox, b.y + _oy, b.w, b.h));
    }
    for (final b in w.blocks) {
      if (b.type == 'P' && b.telegraph) _sniperSight(b);
    }
    _cracking();
    _debris();
    _guard();
    _items();
    _bullets();
    for (final f in w.phantoms) {
      _ball(f);
    }
    if (w.phase == WorldPhase.playing && w.ballInPlay) _ball(w.ball);
    _paddle();
    _lasers();
    _rings();
    _particles();
    if (!attract) _popups();
    canvas.restore();
    _edgeFx();
    if (!attract) {
      _effects();
      _hud();
      if (w.practice case final p?) _practicePanel(p);
      _callouts();
      _banner();
      if (w.phase == WorldPhase.clearing) _clearScreen();
    }
    if (fx.flash > 0) {
      // 光の強さは段階に丸める (なめらかに消えるとドット絵らしくない)
      final k = (math.min(0.35, fx.flash) * 6).floor() / 6;
      if (k > 0) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, _w, _h),
          pixelPaint(withAlpha(fx.flashColor, k)),
        );
      }
    }
    canvas.restore();
  }

  /// ドット文字。[size] は 8 の倍数にするとドットが揃う。
  void _txt(
    String s,
    double x,
    double y,
    double size,
    Color color, {
    TextAlignH align = TextAlignH.center,
    double weight = 700,
    String? family,
  }) => text.draw(
    _c,
    s,
    x,
    y,
    size,
    color,
    align: align,
    weight: weight,
    family: family ?? TextCache.pixel,
  );

  /// 1 ドット右下にずらした硬い影を付けた文字 (見出し・判定)。
  void _bigTxt(
    String s,
    double x,
    double y,
    double size,
    Color color, {
    Color? shadow,
    TextAlignH align = TextAlignH.center,
  }) {
    final o = size / 8;
    final a = color.a;
    _txt(
      s,
      x + o,
      y + o,
      size,
      withAlpha(shadow ?? Dot.dark(color), a),
      align: align,
    );
    _txt(s, x, y, size, color, align: align);
  }

  /// `(_t * rate).floor().isEven` の点滅 (1 秒に rate / 2 回)。
  /// 「演出を控えめにする」では 1 秒に 3 回を超えて点滅させない。[calm] を渡せばその状態で止め、
  /// 渡さなければ 1 秒に 2 回のゆっくりした点滅にする。
  bool _blink(double rate, {bool? calm}) {
    if (fx.reduceEffects && rate > 6) {
      if (calm != null) return calm;
      rate = 4;
    }
    return (_t * rate).floor().isEven;
  }

  /// 点線 (ドットの破線)。
  void _dashedLine(
    double x0,
    double y,
    double x1,
    double dash,
    double gap,
    double offset,
    Color col, {
    double h = _d,
  }) {
    final p = pixelPaint(col);
    var x = x0 - (offset % (dash + gap));
    while (x < x1) {
      final a = math.max(x0, x), b = math.min(x1, x + dash);
      if (b > a) _c.drawRect(Rect.fromLTWH(a, y - h / 2, b - a, h), p);
      x += dash + gap;
    }
  }

  // ---- 背景・盤面 ---------------------------------------------------------

  void _background() {
    final od = world.od;
    if (highQuality) _floor.draw(_c, od ? Dot.odDither : Dot.dither);
    if (od) {
      // FEVER TIME: 速く流れる線 (加速している感じ)
      final p = pixelPaint(Dot.odDither);
      final off = (_t * 900) % 240;
      for (var x = 60.0; x < _w; x += 90) {
        final y0 = off - 240 + (x * 7) % 240;
        for (var y = y0; y < _h; y += 240) {
          _c.drawRect(Rect.fromLTWH(x, y, _d, 48), p);
        }
      }
      return;
    }
    // 遠くの星のような点 (ゆっくり流れる)
    final p = pixelPaint(Dot.night);
    final off = (_t * 12) % 96;
    for (var row = 0; row < 6; row++) {
      final y = off - 96 + row * 96;
      for (var x = 30.0; x < _w; x += 120) {
        _c.drawRect(Rect.fromLTWH(x + (row.isEven ? 0 : 60), y, _d, _d), p);
      }
    }
  }

  void _field() {
    _c.drawRect(
      const Rect.fromLTWH(0, 0, _w, Field.topY),
      pixelPaint(world.od ? Dot.odHud : Dot.night),
    );
    _c.drawRect(
      const Rect.fromLTWH(0, Field.topY - _d, _w, _d),
      pixelPaint(Dot.edge),
    );
    if (world.practice != null) return; // 練習場にはブロックがないので、デッドラインを描かない
    final danger = world.isDanger;
    final col = danger
        ? (_blink(7, calm: true) ? Dot.bulletRed : Dot.brick)
        : Dot.dark(Dot.brick);
    _dashedLine(0, Field.warnY, _w, 16, 8, -_t * 32, col);
    if (attract) return;
    _txt(
      'DEAD LINE',
      _w - 16,
      Field.warnY - 18,
      16,
      danger ? Dot.bulletRed : Dot.brick,
      align: TextAlignH.right,
    );
  }

  void _magnetField(Block b) {
    final x = b.x + _ox + b.w / 2, y = b.y + _oy + b.h / 2;
    final rad = world.tuning.magnetRadius;
    final n = (rad * 2 * math.pi / 24).round();
    final spin = (_t * 20 / rad) % (math.pi * 2 / n);
    drawDots(
      _c,
      ringDots(x, y, rad, n, from: spin, to: spin + math.pi * 2),
      withAlpha(Dot.sky, 0.35),
      size: 3,
    );
    final r = rad - ((_t * 60) % rad);
    final m = math.max(6, (r * 2 * math.pi / 20).round());
    drawDots(
      _c,
      ringDots(x, y, r, m),
      withAlpha(Dot.sky, 0.3 * r / rad),
      size: 3,
    );
  }

  /// 狙撃砲台の照準線 (ドットの点線)。予兆の間はパドルを追い、固定されると詰まって明滅する。
  void _sniperSight(Block b) {
    final x = b.x + _ox + b.w / 2, y = b.y + _oy + b.h;
    final locked = b.fireT <= SniperTurretBlock.lockTime;
    final len = (Field.paddleY - y) / math.max(0.2, math.sin(b.aim));
    final step = locked ? _d * 2 : _d * 4;
    final col = locked
        ? (_blink(16, calm: true) ? Dot.white : Dot.bulletRed)
        : withAlpha(Dot.bulletRed, 0.6);
    final n = (len / step).floor();
    final pts = Float32List(n * 2);
    for (var k = 0; k < n; k++) {
      // ドットの格子に揃える
      pts[k * 2] =
          ((x + math.cos(b.aim) * k * step) / _d).floorToDouble() * _d + _d / 2;
      pts[k * 2 + 1] =
          ((y + math.sin(b.aim) * k * step) / _d).floorToDouble() * _d + _d / 2;
    }
    drawDots(_c, pts, col, size: locked ? _d : _d / 2 + 1);
  }

  void _block(BlockPaintContext ctx, Block b, Rect r) {
    blockPainters.of(b.type)(ctx, b, r);
    final i = r.deflate(2);
    // 支えの脈動: 要石から塊へ光が伝わる (どこが繋がっているかが分かる)
    if (b.supported && !b.behavior.anchor) {
      final ph = (_t * 8) % 16;
      if ((ph - b.depth).abs() < 0.75) {
        _c.drawRect(i, pixelPaint(const Color(0x40FFFFFF)));
      }
    }
    if (b.flash > 0) _c.drawRect(i, pixelPaint(Dot.white));
  }

  /// ひびが入って落下を待つブロック (その場で震える)。
  void _cracking() {
    final on = (_t * 25).floor().isEven;
    // 「演出を控えめにする」では白と入れ替えず、明るい色のままにする
    Color col(Color c) => fx.reduceEffects
        ? Dot.light(c)
        : on
        ? Dot.white
        : c;
    for (final f in world.falling) {
      final b = f.block;
      final x = b.x + _ox + ((_rnd.nextInt(3) - 1) * 2),
          y = b.y + _oy + ((_rnd.nextInt(3) - 1) * 2);
      _debrisRect(Rect.fromLTWH(x, y, b.w, b.h), col(fx.blockColor(b)));
    }
    for (final d in fx.debris) {
      if (d.dropped) continue;
      final x = d.x + ((_rnd.nextInt(3) - 1) * 2),
          y = d.y + ((_rnd.nextInt(3) - 1) * 2);
      _debrisRect(Rect.fromLTWH(x, y, d.w, d.h), col(d.color));
    }
  }

  void _debris() {
    for (final d in fx.debris) {
      if (!d.dropped) continue;
      _c.save();
      _c.translate(d.x + d.w / 2, d.y + d.h / 2);
      // 回転は 45 度ずつ (ドット絵のコマ送り)
      _c.rotate((d.rot / (math.pi / 4)).round() * math.pi / 4);
      final a = (1 - (d.y - Field.warnY) / 260).clamp(0.15, 1.0);
      _debrisRect(
        Rect.fromCenter(center: Offset.zero, width: d.w, height: d.h),
        withAlpha(d.color, a),
      );
      _c.restore();
    }
  }

  void _debrisRect(Rect r, Color col) => bevelRect(_c, r.deflate(2), col);

  // ---- 弾・ボール・パドル --------------------------------------------------

  static final _bullet = DotSprite(['.#.', '###', '.#.']);
  static final _bulletBig = DotSprite(['.##.', '####', '####', '.##.']);
  static final _shard = [
    DotSprite(['.#.', '.#.', '###']),
    DotSprite(['#..', '###', '#..']),
    DotSprite(['###', '.#.', '.#.']),
    DotSprite(['..#', '###', '..#']),
  ];

  void _bullets() {
    for (final u in world.bullets) {
      if (u.dead) continue;
      final x = _lerp(u.prevX, u.x), y = _lerp(u.prevY, u.y);
      if (u.kind == BulletKind.shot) {
        // SHOT (アイテム) の弾: 縦長の棒 (丸い敵弾・撃ち返し弾と形で分ける)
        final col = Palette.items[ItemKind.shot]!;
        _c.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: _d, height: _d * 4),
          pixelPaint(col),
        );
        _c.drawRect(
          Rect.fromCenter(
            center: Offset(x, y - _d * 1.5),
            width: _d,
            height: _d,
          ),
          pixelPaint(Dot.white),
        );
        continue;
      }
      final c = switch (u) {
        Bullet(hostile: false, :final red) => red ? Dot.mustard : Dot.peach,
        Bullet(kind: BulletKind.shard) => Dot.steel,
        Bullet(kind: BulletKind.shrapnel) => Dot.orange,
        Bullet(:final red) => red ? Dot.bulletRed : Dot.bullet,
      };
      if (u.hostile && u.kind == BulletKind.shard) {
        // 回転は 4 コマ
        final f = _shard[(u.life * 8 / (math.pi / 2)).floor() % 4];
        f.drawCentered(_c, x, y, c);
        continue;
      }
      // 2 コマで明滅する縁 (弾幕が派手に見え、背景から浮く)
      final blink =
          !fx.reduceEffects && ((_t * 12).floor() + u.hashCode).isEven;
      if (u.hostile && u.red) {
        _bulletBig.drawCentered(_c, x, y, blink ? Dot.white : c, scale: 1.25);
        _bulletBig.drawCentered(_c, x, y, c);
      } else {
        _bulletBig.drawCentered(
          _c,
          x,
          y,
          blink ? Dot.light(c) : Dot.dark(c),
          scale: 1.25,
        );
        _bullet.drawCentered(_c, x, y, c);
      }
      _c.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: _d, height: _d),
        pixelPaint(Dot.white),
      );
    }
  }

  // ---- アイテム (design.md 7.10) ---------------------------------------------

  /// 落ちてきているアイテム (横長のカプセル)。
  void _items() {
    final tun = world.tuning;
    for (final it in world.items) {
      drawItemCapsule(
        _c,
        text,
        it.kind,
        it.x,
        _lerp(it.prevY, it.y),
        w: tun.itemWidth,
        h: tun.itemHeight,
        lit: !fx.reduceEffects && (_t * 6).floor().isEven,
      );
    }
  }

  /// GUARD の防壁: 画面の下の点線。消える 3 秒前から点滅する。
  void _guard() {
    final left = world.effects.guard;
    if (left <= 0 || world.phase != WorldPhase.playing) return;
    if (left < 3 && !_blink(6)) return;
    final col = Palette.items[ItemKind.guard]!;
    _dashedLine(0, Field.guardY, _w, 24, 8, _t * 24, col, h: _d * 2);
    _dashedLine(0, Field.guardY - _d, _w, 24, 8, _t * 24, Dot.light(col));
  }

  /// 効いている効果の記号と残り (盤面の左下)。時間は秒、BLAST は回数。
  void _effects() {
    final w = world;
    if (w.phase != WorldPhase.playing) return;
    const y = 698.0;
    var x = 14.0;
    for (final (kind, left) in w.effects.active) {
      drawItemCapsule(_c, text, kind, x + 16, y, w: 32, h: 20);
      final timed = kind != ItemKind.blast;
      final s = timed ? '${left.ceil()}' : '×${left.round()}';
      // 残り 3 秒を切ったら点滅 (控えめのときは色だけ変える)
      final ending = timed && left < 3;
      final col = ending
          ? (fx.reduceEffects || _blink(6) ? Dot.mustard : Dot.dim)
          : Dot.white;
      _txt(s, x + 38, y, _label, col, align: TextAlignH.left);
      x += 38 + text.width(s, _label) + 14;
    }
  }

  static final _ballSprite = DotSprite(['.##.', '####', '####', '.##.']);

  void _ball(Ball b) {
    final w = world;
    final st = w.stage;
    final pierce = b.pierce > 0 || w.od || b.phantom;
    final col = w.od || b.phantom
        ? Dot.rose
        : b.breaker
        ? Dot.blush
        : pierce
        ? Dot.mustard
        : const [Dot.white, Dot.white, Dot.peach, Dot.peach][st];
    final tr = fx.trails[b.id] ?? const <Offset>[];
    // 残像: 古いものほど小さく暗い (3 段階)
    for (var i = 0; i < tr.length; i++) {
      final a = (i + 1) / tr.length;
      final s = a > 0.66
          ? 3.0
          : a > 0.33
          ? 2.0
          : 1.0;
      final c = a > 0.66
          ? col
          : a > 0.33
          ? Dot.dark(col)
          : Dot.edge;
      if (w.od && i % 4 == 0) {
        _ballSprite.drawCentered(
          _c,
          tr[i].dx,
          tr[i].dy,
          withAlpha(Dot.rose, 0.4),
        );
      }
      _c.drawRect(
        Rect.fromCenter(center: tr[i], width: _d * s, height: _d * s),
        pixelPaint(c),
      );
    }
    final x = _lerp(b.prevX, b.x), y = _lerp(b.prevY, b.y);
    if (pierce) {
      _ballSprite.drawCentered(_c, x, y, withAlpha(col, 0.35), scale: 1.75);
    }
    _ballSprite.drawCentered(_c, x, y, col);
    _c.drawRect(Rect.fromLTWH(x - _d, y - _d, _d, _d), pixelPaint(Dot.white));
    if (b.breaker) {
      final a0 = (_t * 1000 / 120 / (math.pi / 4)).floor() * math.pi / 4;
      drawDots(
        _c,
        ringDots(x, y, 16, 8, from: a0, to: a0 + math.pi * 2),
        Dot.blush,
      );
    }
    if (b.pierce > 0 && !w.od && !b.phantom) {
      final pts = <double>[];
      for (var k = 0; k < b.pierce; k++) {
        final a = _t * 1000 / 150 + k * math.pi * 2 / b.pierce;
        pts.addAll([x + math.cos(a) * 16, y + math.sin(a) * 16]);
      }
      drawDots(_c, Float32List.fromList(pts), Dot.mustard);
    }
    if (b.phantom || attract) return;
    if (b.flight >= 5 && !b.attached) {
      _txt(
        '${b.flight} HIT',
        x,
        y - 24,
        16,
        b.flight >= 15 ? Dot.mustard : Dot.dim,
      );
    }
    if (b.attached) {
      if (w.countdown > 0) {
        _bigTxt('READY', x, y - 32, 24, Dot.mustard, shadow: Dot.brick);
      } else if ((_t * 2).floor().isEven) {
        _bigTxt(
          parryButton ? 'PARRY' : 'TAP',
          x,
          y - 32,
          24,
          Dot.white,
          shadow: Dot.edge,
        );
      }
    }
  }

  void _paddle() {
    final w = world, p = w.paddle, pr = w.parry;
    final pw = w.paddleWidth;
    final px = _lerp(p.prevX, p.x);
    final x = px - pw / 2;
    const y = Field.paddleY;
    final stunned = p.stun > 0;
    final cooling = w.t < pr.cooldownUntil;
    var col = Dot.sky;
    if (stunned) {
      col = _blink(20, calm: true) ? Dot.brick : Dot.edge;
    } else if (p.invuln > 0 && _blink(15)) {
      col = Dot.edge; // 被弾後の無敵: 点滅
    } else if (cooling) {
      col = Dot.steel;
    } else if (pr.active) {
      col = Dot.mustard;
    }
    bevelRect(_c, Rect.fromLTWH(x, y, pw, Field.paddleH + 2), col);
    // 両端の印
    final dark = pixelPaint(Dot.dark(col));
    _c.drawRect(Rect.fromLTWH(x + _d * 2, y + _d, _d, _d), dark);
    _c.drawRect(Rect.fromLTWH(x + pw - _d * 3, y + _d, _d, _d), dark);
    if (pr.active && w.phase == WorldPhase.playing) {
      // パリィの受付: 広がるドットの弧
      final k = ((w.t - pr.press) / w.tuning.parryWindow).clamp(0.0, 1.0);
      final rx = pw / 2 + 8 + k * 14, ry = 14 + k * 10;
      final n = (rx / 5).round();
      final pts = Float32List(n * 2);
      for (var i = 0; i < n; i++) {
        final a = math.pi + math.pi * i / (n - 1);
        pts[i * 2] = px + math.cos(a) * rx;
        pts[i * 2 + 1] = y + 2 + math.sin(a) * ry;
      }
      drawDots(_c, pts, (k * 3).floor().isEven ? Dot.mustard : Dot.white);
    }
    if (cooling && !stunned) {
      final k = ((pr.cooldownUntil - w.t) / w.tuning.parryCooldown).clamp(
        0.0,
        1.0,
      );
      _c.drawRect(
        Rect.fromLTWH(x, y + Field.paddleH + 6, pw * k, _d),
        pixelPaint(Dot.dim),
      );
    }
    if (stunned) {
      _c.drawRect(
        Rect.fromLTWH(
          x,
          y + Field.paddleH + 6,
          pw * (p.stun / w.tuning.stunTime),
          _d,
        ),
        pixelPaint(Dot.brick),
      );
    }
  }

  void _lasers() {
    for (final l in world.lasers) {
      if (l.t < l.warn) {
        final blink = _blink(12, calm: true);
        _c.drawRect(
          Rect.fromLTWH(l.x - l.w / 2, Field.topY, l.w, _h - Field.topY),
          pixelPaint(const Color(0x14FF3B5C)),
        );
        final p = pixelPaint(blink ? Dot.bulletRed : Dot.dark(Dot.brick));
        for (final lx in [l.x - l.w / 2, l.x + l.w / 2]) {
          for (var y = Field.topY; y < _h; y += 16) {
            _c.drawRect(Rect.fromLTWH(lx - _d / 2, y, _d, 8), p);
          }
        }
        if (blink) _bigTxt('!', l.x, Field.paddleY - 40, 32, Dot.bulletRed);
      } else {
        // 発射: 中心ほど明るい段階の帯 (グラデーションの代わり)
        final k = math.max(0.0, 1 - (l.t - l.warn) / l.fire);
        for (final (f, c) in [
          (1.0, Dot.dark(Dot.brick)),
          (0.66, Dot.bulletRed),
          (0.33, Dot.white),
        ]) {
          final hw = l.w * f * (0.4 + 0.6 * k);
          _c.drawRect(
            Rect.fromLTWH(l.x - hw, Field.topY, hw * 2, _h - Field.topY),
            pixelPaint(withAlpha(c, k)),
          );
        }
      }
    }
  }

  // ---- エフェクト ---------------------------------------------------------

  void _rings() {
    for (final r in fx.rings) {
      final k = r.t / FxRing.life;
      final rad = r.r * (0.2 + 0.8 * math.sqrt(k));
      final n = math.max(8, (rad * 2 * math.pi / 14).round());
      drawDots(
        _c,
        ringDots(r.x, r.y, rad, n),
        withAlpha(r.color, k < 0.66 ? 1 : 0.5),
        size: math.max(2.0, r.width * (1 - k) + 2),
      );
    }
  }

  void _particles() {
    for (final p in fx.particles) {
      final a = 1 - p.life / p.max;
      // 大きさは 1 ドットか 2 ドット、色は途中で暗くなる
      final s = p.size > 3 && a > 0.5 ? _d * 2 : _d;
      _c.drawRect(
        Rect.fromCenter(center: Offset(p.x, p.y), width: s, height: s),
        pixelPaint(a > 0.4 ? p.color : Dot.dark(p.color)),
      );
    }
  }

  void _popups() {
    for (final p in fx.popups) {
      if (!fx.reduceEffects && p.t > 0.6 && (p.t * 20).floor().isEven) {
        continue; // 消える前に点滅
      }
      _txt(p.text, p.x, p.y, p.size, p.color);
    }
  }

  void _edgeFx() {
    final w = world;
    if (w.phase != WorldPhase.playing) return;
    if (w.od) {
      _marquee();
    } else if (w.stage >= 2) {
      _edgeBands(
        w.stage == 3 ? Dot.mustard : Dot.orange,
        0.3,
        (_t * 4).floor().isEven ? 3 : 2,
      );
    }
    if (w.isDanger) {
      _edgeBands(Dot.bulletRed, 0.45, _blink(7, calm: true) ? 4 : 2);
    }
  }

  /// FEVER TIME 中、盤面のふちを回る電飾 (ゲーム筐体の電飾のように、色が順に送られる)。
  /// 残り 2 秒を切ると全体が点滅して、終わりが近いことを知らせる。
  /// 「演出を控えめにする」設定では、色をゆっくり送り、点滅はしない。
  void _marquee() {
    final w = world, calm = fx.reduceEffects;
    if (!calm && w.odTime < 2 && (_t * 8).floor().isEven) return;
    const step = 24.0, inset = _d * 2;
    final pts = <List<double>>[[], [], []];
    var k = 0;
    void put(double x, double y) => pts[k++ % 3].addAll([x, y]);
    for (var x = inset; x < _w - inset; x += step) {
      put(x, Field.topY + inset);
    }
    for (var y = Field.topY + inset; y < _h - inset; y += step) {
      put(_w - inset, y);
    }
    for (var x = _w - inset; x > inset; x -= step) {
      put(x, _h - inset);
    }
    for (var y = _h - inset; y > Field.topY + inset; y -= step) {
      put(inset, y);
    }
    final phase = (_t * (calm ? 3 : 12)).floor();
    final cols = [Dot.white, Dot.rose, Dot.dark(Dot.rose)];
    for (var i = 0; i < 3; i++) {
      drawDots(
        _c,
        Float32List.fromList(pts[i]),
        cols[(i + phase) % 3],
        size: _d * 2,
      );
    }
  }

  /// 画面の左右と下の端に、外側ほど濃い段階の帯を描く (発光の代わり)。
  void _edgeBands(Color c, double a, int steps) {
    for (var i = 0; i < steps; i++) {
      final p = pixelPaint(withAlpha(c, a * (1 - i / steps)));
      final o = i * _d * 2, s = _d * 2;
      _c.drawRect(Rect.fromLTWH(o, Field.topY, s, _h - Field.topY), p);
      _c.drawRect(Rect.fromLTWH(_w - o - s, Field.topY, s, _h - Field.topY), p);
      _c.drawRect(Rect.fromLTWH(o + s, _h - o - s, _w - (o + s) * 2, s), p);
    }
  }

  // ---- HUD・表示 ------------------------------------------------------------

  void _hud() {
    final w = world;
    _txt('SCORE', 20, _labelY, _label, Dot.dim, align: TextAlignH.left);
    _txt(
      formatScore(fx.dispScore),
      20,
      38,
      24,
      Dot.white,
      align: TextAlignH.left,
    );
    final boss = w.boss;
    final practice = w.practice;
    _txt(
      practice != null
          ? 'PRACTICE'
          : boss != null
          ? 'BOSS ${boss.index + 1}'
          : 'ROUND',
      400,
      _labelY,
      _label,
      Dot.dim,
    );
    _txt(
      practice != null
          ? practiceSpeedLabel(practice.speed)
          : '${_roundNo(w.round.number)}${w.round.loop > 0 ? ' L${w.round.loop + 1}' : ''}',
      400,
      38,
      24,
      Dot.white,
    );
    final clear = w.round.clear;
    if (boss != null) {
      final tm = boss.time.ceil();
      _txt('TIME', 530, _labelY, _label, Dot.dim);
      _txt('$tm', 530, 38, 24, tm <= 10 ? Dot.bulletRed : Dot.white);
    } else if (clear is SurviveClear) {
      final left = math.max(0, (clear.seconds - w.roundTime).ceil());
      _txt('SURVIVE', 530, _labelY, _label, Dot.dim);
      _txt('$left', 530, 38, 24, left <= 5 ? Dot.mustard : Dot.white);
    } else if (clear is ScoreClear) {
      _txt('GOAL', 530, _labelY, _label, Dot.dim);
      _txt(formatScore(clear.target), 530, 38, 24, Dot.white);
    } else {
      _txt('CHAIN', 530, _labelY, _label, Dot.dim);
      _txt('${w.streak}', 530, 38, 24, Dot.white);
    }
    // コンボ: ドットのマスを並べたメーター
    const bx = 680.0, by = 28.0, bw = 340.0, bh = 16.0;
    final st = w.od ? 4 : w.stage;
    _txt(
      w.od
          ? 'FEVER TIME ${math.max(0, w.odTime).toStringAsFixed(1)}s'
          : 'COMBO LV${st + 1}',
      bx,
      _labelY,
      _label,
      w.od ? Dot.rose : Dot.dim,
      align: TextAlignH.left,
    );
    final tun = w.tuning;
    const cell = 12.0, gap = 4.0;
    final cells = ((bw + gap) / (cell + gap)).floor();
    final k = w.od
        ? (w.odTime / tun.odMaxTime).clamp(0.0, 1.0)
        : (w.combo / tun.odCombo).clamp(0.0, 1.0);
    final lit = (cells * k).ceil();
    for (var i = 0; i < cells; i++) {
      final r = Rect.fromLTWH(bx + i * (cell + gap), by, cell, bh);
      if (i >= lit) {
        _c.drawRect(r, pixelPaint(Dot.dither));
        continue;
      }
      final step = (_t * (fx.reduceEffects ? 3 : 12))
          .floor(); // 控えめでは電飾と同じくゆっくり送る
      final c = w.od
          ? ((i + step) % 3 == 0 ? Dot.white : Dot.rose)
          : Palette.comboBar[st];
      bevelRect(_c, r, c);
    }
    if (!w.od) {
      // 段階の境目
      final p = pixelPaint(Dot.dim);
      for (final m in tun.stageMin.skip(1)) {
        final i = (cells * m / tun.odCombo).round();
        _c.drawRect(
          Rect.fromLTWH(bx + i * (cell + gap) - gap / 2 - 1, by - 4, 2, bh + 8),
          p,
        );
      }
    }
    final m = w.mult, mc = Palette.multColor[st];
    _bigTxt('×$m', pauseButton.left - 16, 34, 32, mc, align: TextAlignH.right);
    if (boss != null) {
      final hp = w.bossHp;
      const bw2 = 360.0, x = _w / 2 - bw2 / 2, y = Field.topY + 6;
      _c.drawRect(const Rect.fromLTWH(x, y, bw2, 8), pixelPaint(Dot.night));
      bevelRect(
        _c,
        Rect.fromLTWH(x, y, bw2 * hp / boss.maxHp, 8),
        Palette.blocks['C']!,
        d: 2,
      );
      final p = pixelPaint(Dot.ink);
      for (final th in boss.def.phaseThresholds) {
        _c.drawRect(Rect.fromLTWH(x + bw2 * th - 1, y, 2, 8), p);
      }
    }
    final j = fx.judge;
    if (j != null && w.phase == WorldPhase.playing) {
      // 出た瞬間だけ 1 段大きく (なめらかに縮めない)
      final base = j.big ? 40.0 : 32.0;
      final size = base + (j.t < 0.08 ? 8 : 0);
      final y = Field.paddleY - 36 - (j.t * 20 / 4).floor() * 4;
      _bigTxt(j.text, w.paddle.x, y, size, j.color);
      // ずれ: 判定の文字の下、パドルの上に小さく (判定の文字が出た瞬間に大きくなっても重ならない位置)
      final sub = j.sub;
      if (sub != null) {
        _txt(sub, w.paddle.x, y + base / 2 + 10, 16, Dot.white);
      }
    }
  }

  /// 練習場の画面の左端: 直近 [PracticeLog.capacity] 回の判定の内訳と、ずれの平均・ばらつき。
  void _practicePanel(PracticeMode p) {
    final log = p.log;
    const x = 24.0, x2 = 236.0, lh = 22.0, s = 16.0;
    var y = Field.topY + 22;
    _txt(
      'LAST ${log.length}/${PracticeLog.capacity}',
      x,
      y,
      s,
      Dot.dim,
      align: TextAlignH.left,
    );
    y += lh + 4;
    void row(String label, String value, Color c) {
      _txt(label, x, y, s, Dot.dim, align: TextAlignH.left);
      _txt(value, x2, y, s, c, align: TextAlignH.right);
      y += lh;
    }

    row('JUST', '${log.count(ParryGrade.just)}', Dot.rose);
    row('PERFECT', '${log.count(ParryGrade.perfect)}', Dot.mustard);
    row('GOOD', '${log.count(ParryGrade.good)}', Dot.peach);
    row('MISS', '${log.count(null)}', Dot.white);
    y += 4;
    final m = log.mean, sd = log.spread;
    row('AVG', m == null ? '-' : timingLabel(m), Dot.white);
    row('SPREAD', sd == null ? '-' : '${(sd * 1000).round()}ms', Dot.white);
  }

  void _callouts() {
    if (world.phase == WorldPhase.over) return;
    for (var i = 0; i < fx.callouts.length; i++) {
      final c = fx.callouts[i];
      final fading = c.t > FxCallout.life - 0.3;
      if (fading && !fx.reduceEffects && (c.t * 20).floor().isEven) continue;
      final pop = c.t < 0.08 ? 8.0 : 0.0;
      final y = 210.0 + i * 64;
      _bigTxt(c.text, _w / 2, y, c.size + pop, c.color);
      if (c.sub.isNotEmpty) {
        _txt(c.sub, _w / 2, y + c.size * 0.8, 16, Dot.white);
      }
    }
  }

  /// ラウンド開始時などの帯。副題は翻訳する。
  void _banner() {
    final b = fx.banner;
    if (b == null || world.phase == WorldPhase.over) return;
    final (title, sub, color) = switch (b.kind) {
      BannerKind.round => (
        'ROUND ${_roundNo(b.value)}',
        _introText(b.introKey) ?? _goalText(),
        Dot.white,
      ),
      BannerKind.boss => (
        'WARNING',
        'BOSS ${b.value}  —  ${l10n.bannerBoss}',
        Dot.bulletRed,
      ),
      BannerKind.feverTime => ('FEVER TIME', l10n.bannerFeverTime, Dot.rose),
      BannerKind.bossPhase => (
        'PHASE ${b.value}',
        b.value == 2 ? l10n.bannerPhase2 : l10n.bannerPhase3,
        Dot.white,
      ),
      BannerKind.timeOver => ('TIME OVER', l10n.bannerTimeOver, Dot.bulletRed),
    };
    // アイテムが初めて出るラウンドでは、説明を 1 行足す (design.md 7.10)
    final item = b.kind == BannerKind.round && world.round.itemIntro
        ? l10n.introItem
        : null;
    b.describe(
      [sub, item].whereType<String>().join(' ').nullIfEmpty,
      extra: item != null,
    );
    final size = bannerSubSize(_scale), lineH = (size * 1.25).ceilToDouble();
    final lines = [
      if (sub != null && sub.isNotEmpty) ...wrapText(sub, size, bannerSubWidth),
      if (item != null) ...wrapText(item, size, bannerSubWidth),
    ];
    // 説明が 2 行以上になったら、その分だけ帯を下へ広げる
    final extra = math.max(0, lines.length - 1) * lineH;
    // 帯は上下から開いて閉じる (高さを 4 段階で変える)
    final open = b.open;
    final h = ((90 + extra) * open / 24).ceil() * 24.0;
    if (h <= 0) return;
    final band = Rect.fromLTWH(0, 375 + extra / 2 - h / 2, _w, h);
    _c.drawRect(band, pixelPaint(withAlpha(Dot.ink, 0.85)));
    _c.drawRect(Rect.fromLTWH(0, band.top, _w, _d), pixelPaint(color));
    _c.drawRect(Rect.fromLTWH(0, band.bottom - _d, _w, _d), pixelPaint(color));
    if (open < 0.7) return;
    _bigTxt(
      title,
      _w / 2,
      360,
      40,
      color,
      shadow: color == Dot.white ? Dot.edge : Dot.dark(color),
    );
    for (var i = 0; i < lines.length; i++) {
      _txt(
        lines[i],
        _w / 2,
        400 + i * lineH,
        size,
        Dot.white,
        family: TextCache.jp,
      );
    }
  }

  /// [s] を、大きさ [size] の説明文の字で 1 行が [maxWidth] に収まるように折り返す。
  /// 英語は空白で、日本語は字の間で折り返す。
  List<String> wrapText(String s, double size, double maxWidth) {
    double width(String t) =>
        text.get(t, size, Dot.white, family: TextCache.jp).width;
    if (width(s) <= maxWidth) return [s];
    final lines = <String>[];
    var line = '';
    for (final ch in s.runes.map(String.fromCharCode)) {
      final next = line + ch;
      if (line.isEmpty || width(next) <= maxWidth) {
        line = next;
        continue;
      }
      // 英単語の途中なら、直前の空白で切る
      final sp = line.lastIndexOf(' ');
      if (ch != ' ' &&
          sp > 0 &&
          !line.endsWith(' ') &&
          line.codeUnitAt(line.length - 1) < 0x2000) {
        lines.add(line.substring(0, sp).trimRight());
        line = line.substring(sp + 1) + ch;
      } else {
        lines.add(line.trimRight());
        line = ch == ' ' ? '' : ch;
      }
    }
    if (line.trim().isNotEmpty) lines.add(line.trim());
    return lines;
  }

  /// ラウンドの番号。ステージモードで 2 ラウンド以上ある面は「いま/全体」で出す。
  String _roundNo(int n) => switch (world.mode) {
    StageMode(:final stage) when stage.rounds.length > 1 =>
      '$n/${stage.rounds.length}',
    _ => '$n',
  };

  String? _introText(String? key) => introText(
    l10n,
    key,
    loop: world.round.loop + 1,
    scoreTarget: switch (world.round.clear) {
      ScoreClear(:final target) => target,
      _ => null,
    },
    parryButton: parryButton,
  );

  /// ステージモードでは、説明がなければクリア条件を出す。
  String? _goalText() {
    if (world.mode is! StageMode) return null;
    return switch (world.round.clear) {
      AnnihilateClear() => l10n.clearAnnihilate,
      ScoreClear(:final target) => l10n.clearScore(formatScore(target)),
      SurviveClear(:final seconds) => l10n.clearSurvive('${seconds.round()}'),
    };
  }

  void _clearScreen() {
    final w = world;
    final k = math.min(1.0, w.clearT / 0.3);
    _c.drawRect(
      const Rect.fromLTWH(0, 0, _w, _h),
      pixelPaint(withAlpha(Dot.ink, (k * 3).ceil() / 3 * 0.8)),
    );
    if (k < 1) return;
    final last = w.mode.roundAt(w.round.number + 1) == null;
    final title = w.round.ending
        ? 'ALL ROUNDS CLEAR'
        : last && w.mode is StageMode
        ? 'STAGE CLEAR'
        : w.boss != null
        ? 'BOSS DESTROYED'
        : 'ROUND ${w.round.number} CLEAR';
    _bigTxt(
      title,
      _w / 2,
      220,
      40,
      w.round.ending ? Dot.rose : Dot.mustard,
      shadow: w.round.ending ? Dot.violet : Dot.brick,
    );
    final bon = w.bonuses;
    for (var i = 0; i < bon.length; i++) {
      if (w.clearT < 0.3 + i * 0.18) continue;
      final y = 290.0 + i * 34;
      _txt(bon[i].label, _w / 2 - 220, y, 16, Dot.dim, align: TextAlignH.left);
      _txt(
        '+${formatScore(bon[i].points)}',
        _w / 2 + 220,
        y,
        16,
        Dot.mustard,
        align: TextAlignH.right,
      );
    }
    final y = 290.0 + bon.length * 34 + 20;
    if (w.clearT > 0.3 + bon.length * 0.18) {
      _dashedLine(_w / 2 - 220, y - 14, _w / 2 + 220, 8, 4, 0, Dot.edge);
      _txt('SCORE', _w / 2 - 220, y + 10, 16, Dot.dim, align: TextAlignH.left);
      _txt(
        formatScore(fx.dispScore),
        _w / 2 + 220,
        y + 10,
        24,
        Dot.white,
        align: TextAlignH.right,
      );
    }
    if (w.round.ending) {
      _txt(l10n.endingSub, _w / 2, y + 60, 16, Dot.rose, family: TextCache.jp);
    }
  }

  @override
  bool shouldRepaint(FieldPainter old) => true;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// 練習場のボールの速さの表示。
String practiceSpeedLabel(PracticeSpeed s) => switch (s) {
  PracticeSpeed.stage1 => 'LV1',
  PracticeSpeed.stage3 => 'LV3',
  PracticeSpeed.fever => 'FEVER',
};
