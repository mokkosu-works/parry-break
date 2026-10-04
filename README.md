# RICOCHET OVERDRIVE

ブロック崩し × パリィ × 弾幕のアーケード型スコアアタック。Flutter で iOS / Android に対応する。

- ゲームの仕様: [design.md](design.md)
- ネイティブ版の仕様・アーキテクチャ・ストア公開の手順: [docs/native-app-spec.md](docs/native-app-spec.md)
- アプリ本体: [app/](app/)

```sh
cd app
flutter pub get
flutter run
flutter test
```

ステージは `app/assets/stages/campaign.json`、エンドレスの配置とボスは `app/assets/stages/endless.json` に書く。

## iOS シミュレータで動かす (macOS)

初回だけ、開発ツールの向き先を Xcode にする。Command Line Tools のままだとシミュレータが `flutter devices` に出てこない。出てきても、ビルド中に `objective_c` のビルドフックが `Bad state: No element` で落ちる。

```sh
xcode-select -p   # /Applications/Xcode.app/Contents/Developer ならそのままでよい
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

起動するときは次のとおり。

```sh
open -a Simulator        # シミュレータを立ち上げる
cd app
flutter devices          # iPhone が一覧に出ることを確かめる
flutter run              # 複数ある場合は番号で選ぶ。-d <デバイス ID> で直接指定もできる
```

`flutter run` の実行中に使えるキー: `r` ホットリロード、`R` ホットリスタート、`q` 終了。
