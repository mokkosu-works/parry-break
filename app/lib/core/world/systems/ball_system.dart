part of '../world.dart';

/// ボールと分身弾の移動、壁・パドル・ブロックとの衝突。
extension _BallSystem on World {
  void _updateAllBalls(double dt) {
    _updateBall(ball, dt);
    if (phase != WorldPhase.playing) return;
    for (final f in List.of(phantoms)) {
      if (f.lost) continue;
      _updateBall(f, dt);
      if (phase != WorldPhase.playing) return;
      f.life -= dt;
    }
    phantoms.removeWhere((f) => f.lost || f.life <= 0);
    // 分身弾はボールの数に含めない: メインのボールを落としたらゲームオーバー
    if (ball.lost) _gameOver('BALL LOST');
  }

  void _updateBall(Ball b, double dt) {
    final p = paddle;
    final main = identical(b, ball);
    if (b.attached) {
      b.x = p.x;
      b.y = Field.paddleY - Field.ballR - 1;
      return;
    }
    // 段階移行時は補間して加速
    b.speed += (targetSpeed - b.speed) * math.min(1, (od ? 2 : 4) * dt);
    if (od) b.speed = math.min(b.speed, tuning.odMaxSpeed);
    for (final bl in blocks) {
      if (bl.behavior.influencesBalls) bl.behavior.influenceBall(this, bl, b, dt);
    }
    final s = hypot(b.vx, b.vy);
    final sn = s == 0 ? 1.0 : s;
    b.vx = b.vx / sn * b.speed;
    b.vy = b.vy / sn * b.speed;

    // 速いボールがすり抜けないよう、4px ごとのサブステップで進める
    final n = math.max(1, (b.speed * dt / 4).ceil());
    final sdt = dt / n, t0 = t - dt;
    const r = Field.ballR;
    for (var i = 0; i < n; i++) {
      final py = b.y;
      b.x += b.vx * sdt;
      b.y += b.vy * sdt;
      if (b.x < r) {
        b.x = r;
        b.vx = b.vx.abs();
        emit(const WallBounced());
      }
      if (b.x > Field.width - r) {
        b.x = Field.width - r;
        b.vx = -b.vx.abs();
        emit(const WallBounced());
      }
      if (b.y < Field.topY + r) {
        b.y = Field.topY + r;
        b.vy = b.vy.abs();
        emit(const WallBounced());
      }
      _collideBlocks(b, main);
      if (phase != WorldPhase.playing) return;
      if (b.vy > 0 &&
          b.y + r >= Field.paddleY &&
          py + r <= Field.paddleY + 8 &&
          (b.x - p.x).abs() <= paddleWidth / 2 + r * 0.6) {
        if (main) {
          // 接触時刻をサブステップ内で補間して求める
          final fr = b.y != py ? clampD((Field.paddleY - (py + r)) / (b.y - py), 0, 1) : 1.0;
          _paddleBounce(b, t0 + sdt * (i + fr));
        } else {
          _reflectOffPaddle(b); // 分身弾はパドルで自動的に跳ね返る
        }
      }
      if (b.y - r > Field.height) {
        b.lost = true;
        return;
      }
    }
  }

  /// パドルの中心からのずれで反射角を決める (中心ほど垂直、端で ±60°)。
  void _reflectOffPaddle(Ball b) {
    final off = clampD((b.x - paddle.x) / (paddleWidth / 2), -1, 1);
    final a = off * 60 * deg;
    b.vx = math.sin(a) * b.speed;
    b.vy = -math.cos(a) * b.speed;
    b.y = Field.paddleY - Field.ballR;
    _fixAngle(b);
  }

  void _paddleBounce(Ball b, double tc) {
    _reflectOffPaddle(b);
    if (b.flight >= 8) _ricochetBonus(b);
    b.flight = 0;
    final grade = _judgeContact(tc);
    if (grade != null) {
      _applyParry(grade, ParryTarget.ball, b.x, Field.paddleY);
      lastContact = Contact(tc, used: true);
    } else {
      lastContact = Contact(tc, used: false);
      emit(PaddleBounced(b.x));
    }
  }

  void _ricochetBonus(Ball b) {
    final n = b.flight;
    final v = n * n * 25 * mult;
    score += v;
    addHeat(n * 2.0);
    stats.bestRicochet = math.max(stats.bestRicochet, n);
    if (n >= 15) {
      emit(Callout(CalloutChannel.ricochet, 'RICOCHET ×$n', sub: '+${formatScore(v)}'));
    } else {
      emit(Popup(b.x, Field.paddleY - 84, 'RICOCHET ×$n  +${formatScore(v)}', PopupKind.ricochet, amount: v));
    }
    emit(RicochetBonus(n, v));
  }

  /// 水平に近い軌道を防ぐ (水平から [Tuning.minAngleDeg] 未満にしない)。
  void _fixAngle(Ball b) {
    final s = hypot(b.vx, b.vy);
    final sn = s == 0 ? 1.0 : s;
    var nx = b.vx / sn, ny = b.vy / sn;
    final minA = tuning.minAngleDeg * deg;
    if (ny.abs() < math.sin(minA)) {
      ny = (ny > 0 ? 1 : -1) * math.sin(minA);
      nx = (nx < 0 ? -1 : 1) * math.cos(minA);
    }
    b.vx = nx * b.speed;
    b.vy = ny * b.speed;
  }

  void _collideBlocks(Ball b, bool main) {
    const r = Field.ballR;
    var bounced = false;
    for (var k = blocks.length - 1; k >= 0; k--) {
      if (k >= blocks.length) continue; // 破壊で配列が縮んだ
      final bl = blocks[k];
      final ax = bl.x + form.ox, ay = bl.y + form.oy;
      final nx = clampD(b.x, ax, ax + bl.w), ny = clampD(b.y, ay, ay + bl.h);
      final dx = b.x - nx, dy = b.y - ny;
      if (dx * dx + dy * dy > r * r) continue;
      if (main) lastBlockHit = t;
      if (bounced) continue;
      if (_hitBlock(bl, b, main) == HitResult.pass) continue;
      bounced = true;
      double nX, nY;
      if (dx == 0 && dy == 0) {
        // 中心がブロックの中に入っている: 最も近い面から押し出す
        final pl = b.x - ax, pr = ax + bl.w - b.x, pt = b.y - ay, pb = ay + bl.h - b.y;
        final m = [pl, pr, pt, pb].reduce(math.min);
        if (m == pl) {
          (nX, nY) = (-1, 0);
        } else if (m == pr) {
          (nX, nY) = (1, 0);
        } else if (m == pt) {
          (nX, nY) = (0, -1);
        } else {
          (nX, nY) = (0, 1);
        }
      } else {
        final d = hypot(dx, dy);
        nX = dx / d;
        nY = dy / d;
      }
      if (nX.abs() > nY.abs()) {
        b.vx = b.vx.abs() * nX.sign;
        b.x = nX > 0 ? ax + bl.w + r : ax - r;
      } else {
        b.vy = b.vy.abs() * nY.sign;
        b.y = nY > 0 ? ay + bl.h + r : ay - r;
      }
      bl.behavior.afterBounce(this, bl, b, nX, nY);
      _fixAngle(b);
    }
  }

  HitResult _hitBlock(Block bl, Ball b, bool main) {
    final pierce = od || b.phantom || b.pierce > 0;
    final cause = b.phantom ? DestroyCause.phantom : pierce ? DestroyCause.pierce : DestroyCause.ball;
    if (main && b.breaker) {
      b.breaker = false;
      _triggerBreaker(b.x, b.y);
    }
    return bl.behavior.onBall(this, bl, BallHit(b, pierce: pierce, main: main, cause: cause));
  }
}

/// 3 桁区切りの得点表示 (ブラウザ版の toLocaleString('en-US') と同じ)。
String formatScore(num n) {
  final s = n.floor().abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
