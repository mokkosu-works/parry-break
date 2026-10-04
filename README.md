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
