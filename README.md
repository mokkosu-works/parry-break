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

各ステージの動作確認には、デバッグモードが使える。タイトル右下の `VER 1.0.0` を 3 回続けてタップすると入り、もう一度 3 回タップするか、設定画面のスイッチで抜ける。デバッグモード中は全ステージの鍵が外れ、プレイ結果は記録にもランキングにも残らない。画面の左下には DEBUG の帯が出る。

ステージは `app/assets/stages/campaign.json`、エンドレスの配置とボスは `app/assets/stages/endless.json` に書く。
