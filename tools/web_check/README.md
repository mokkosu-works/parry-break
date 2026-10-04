# web_check

Web ビルドをヘッドレス Chromium で開いて、起動・音・画面を確かめる。Flutter が動かせないクラウドセッションでの動作確認用。

```sh
cd app && flutter build web --release --no-web-resources-cdn   # CDN を使わない (サンドボックスから gstatic に届かないため)
cd ../tools/web_check && npm install && node check.mjs
```

- AudioContext の状態と、実際に出ている音のレベルを調べる。最初のタップの前後を比べるので、ブラウザの自動再生の制限もわかる。
- `out/` にスクリーンショットが出る。
- 音が鳴っていれば `AUDIO OK` で終了コード 0。

Flutter SDK は `.claude/hooks/session-start.sh` がクラウドセッションの開始時に入れる (`flutter test` / `flutter analyze` / `flutter build web` が使える)。
