part of '../world.dart';

/// 敵弾・撃ち返し弾・グレイズ・ロックオンレーザー。
extension _BulletSystem on World {
  void _spawnHostile(
    double x,
    double y,
    double vx,
    double vy,
    BulletKind kind, {
    Block? source,
    bool red = false,
  }) => bullets.add(
    Bullet(x: x, y: y, vx: vx, vy: vy, kind: kind, red: red, source: source),
  );

  void _updateBullets(double dt) {
    final p = paddle;
    final t0 = t - dt;
    for (var i = bullets.length - 1; i >= 0; i--) {
      if (i >= bullets.length) continue;
      final u = bullets[i];
      if (u.dead) {
        bullets.removeAt(i);
        continue;
      }
      final tc = u.contact;
      if (tc != null) {
        // 接触の後の押下を待っている。押した時刻 (補正後) が救済の窓を過ぎるまで処理した入力が届いたら被弾を確定する。
        // スタン・無敵は接触した時点から数える (待った分だけ短くする)。
        if (t - inputLag - tc > tuning.perfectWindow + 1e-6) {
          u.contact = null;
          if (p.invuln <= 0) {
            bullets.removeAt(i);
            _hurt(since: t - dt * 0.5 - tc);
          }
        }
        continue;
      }
      u.life += dt;
      if (!u.hostile && u.red) _homeToCore(u, dt);
      final ux0 = u.x, uy0 = u.y;
      u.x += u.vx * dt;
      u.y += u.vy * dt;
      if (u.x < -20 ||
          u.x > Field.width + 20 ||
          u.y < Field.topY - 4 ||
          u.y > Field.height + 20) {
        bullets.removeAt(i);
        continue;
      }
      if (u.hostile) {
        final pw = paddleWidth, px = p.x - pw / 2;
        if (rectDist(u.x, u.y, px, Field.paddleY, pw, Field.paddleH) <=
            u.r + tuning.grazeDist) {
          // グレイズの成否は、近くを通ったときに無敵だったかで決める。無敵中に近くを通った
          // (重なった弾を含む) 弾は、無敵が切れてから下へ抜けてもグレイズにしない。
          if (p.invuln > 0) {
            u.grazed = true;
          } else {
            u.near = true;
          }
        }
        if (u.vy > 0 &&
            circleRect(u.x, u.y, u.r, px, Field.paddleY, pw, Field.paddleH)) {
          final tcB = t0 + dt * _contactFraction(u, ux0, uy0, px, pw);
          final grade = _judgeContact(tcB);
          if (grade != null) {
            _parryBullet(u, grade);
          } else if (p.invuln <= 0) {
            u.contact = tcB; // 接触の後の押下を待つ (被弾の確定は上で)
          }
        } else if (u.near &&
            !u.grazed &&
            u.y > Field.paddleY + Field.paddleH + u.r &&
            p.invuln <= 0) {
          u.grazed = true;
          _graze(u);
        }
        continue;
      }
      // 撃ち返し弾 vs ブロック
      for (var k = 0; k < blocks.length; k++) {
        final b = blocks[k];
        if (!circleRect(
          u.x,
          u.y,
          u.r,
          b.x + form.ox,
          b.y + form.oy,
          b.w,
          b.h,
        )) {
          continue;
        }
        final gone = u.kind == BulletKind.shot
            ? b.behavior.onShot(this, b)
            : b.behavior.onReturnedBullet(this, b, u);
        if (gone) {
          final j = bullets.indexOf(u);
          if (j >= 0) bullets.removeAt(j);
        }
        break;
      }
    }
  }

  /// このステップの移動 ([x0], [y0] → 今の位置) のうち、弾がパドルの矩形に初めて触れた割合 (0〜1)。
  /// 線分上で円と矩形が重なる範囲は 1 つの区間なので、二分法で求める (#97)。
  double _contactFraction(
    Bullet u,
    double x0,
    double y0,
    double px,
    double pw,
  ) {
    bool hits(double s) => circleRect(
      x0 + (u.x - x0) * s,
      y0 + (u.y - y0) * s,
      u.r,
      px,
      Field.paddleY,
      pw,
      Field.paddleH,
    );
    if (hits(0)) return 0;
    var lo = 0.0, hi = 1.0;
    for (var k = 0; k < 20; k++) {
      final mid = (lo + hi) / 2;
      if (hits(mid)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  /// 撃ち返した赤い弾は最寄りのコアへ誘導する。
  void _homeToCore(Bullet u, double dt) {
    final tg = u.target;
    if (tg == null || tg.removed) u.target = _nearestCore(u.x, u.y);
    final target = u.target;
    if (target == null) return;
    final o = blockCenter(target), sp = hypot(u.vx, u.vy);
    final want = math.atan2(o.y - u.y, o.x - u.x), cur = math.atan2(u.vy, u.vx);
    var da = want - cur;
    while (da > math.pi) {
      da -= 2 * math.pi;
    }
    while (da < -math.pi) {
      da += 2 * math.pi;
    }
    final na = cur + clampD(da, -6 * dt, 6 * dt);
    u.vx = math.cos(na) * sp;
    u.vy = math.sin(na) * sp;
  }

  /// かすり: 敵弾がパドルに当たらず、近くを通り過ぎた。
  void _graze(Bullet u) {
    stats.graze++;
    addCombo(8);
    final v = 50 * mult;
    score += v;
    emit(Grazed(u.x));
    emit(Popup(u.x, Field.paddleY - 8, 'GRAZE', PopupKind.graze, amount: v));
  }

  /// 敵弾を撃ち返す。赤い弾はコアへ、それ以外は発射元の砲台 (なければ最寄りのブロック) へ向かう。
  void _parryBullet(Bullet u, ParryGrade grade) {
    u
      ..hostile = false
      ..y = Field.paddleY - u.r - 1;
    final sp = tuning.returnSpeed * round.loopMul;
    Vec2? to;
    if (u.red) {
      u.target = _nearestCore(u.x, u.y);
      final tg = u.target;
      if (tg != null) to = blockCenter(tg);
    }
    // 発射元がコアの赤くない弾は、コアにはじかれるだけなので、発射元がない弾と同じく最寄りのブロックへ (#123)
    final src = u.source;
    if (to == null && src != null && !src.removed && src.type != bossCoreId) {
      to = blockCenter(src);
    }
    if (to == null) {
      final nb = _nearestBlock(u.x, u.y);
      if (nb != null) to = blockCenter(nb);
    }
    if (to != null) {
      final a = math.atan2(to.y - u.y, to.x - u.x);
      u
        ..vx = math.cos(a) * sp
        ..vy = math.sin(a) * sp;
    } else {
      u
        ..vx = 0
        ..vy = -sp;
    }
    _applyParry(grade, ParryTarget.bullet, u.x, Field.paddleY);
  }

  Block? _nearestCore(double x, double y) {
    Block? best;
    var bd = double.infinity;
    for (final b in blocks) {
      if (b.type != bossCoreId) continue;
      final o = blockCenter(b), d = hypot(o.x - x, o.y - y);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  /// 撃ち返し弾の行き先: 自分より上にある、最寄りのクリア対象ブロック。
  Block? _nearestBlock(double x, double y) {
    Block? best;
    var bd = double.infinity;
    for (final b in blocks) {
      if (!b.behavior.clearable) continue;
      final o = blockCenter(b);
      if (o.y > y) continue;
      final d = (o.x - x) * (o.x - x) + (o.y - y) * (o.y - y);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  /// ロックオンレーザー: パリィ不可。予兆の後に照射し、パドルが範囲内なら被弾。
  void _updateLasers(double dt) {
    final p = paddle;
    for (var i = lasers.length - 1; i >= 0; i--) {
      final l = lasers[i];
      l.t += dt;
      if (l.t >= l.warn) {
        if (!l.fired) {
          l.fired = true;
          emit(LaserFired(l.x));
        }
        if (!l.hit &&
            p.invuln <= 0 &&
            (p.x - l.x).abs() < paddleWidth / 2 + l.w / 2 - 6) {
          l.hit = true;
          _hurt();
        }
      }
      if (l.t > l.warn + l.fire) lasers.removeAt(i);
    }
  }
}
