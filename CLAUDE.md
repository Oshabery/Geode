# Geode

URL スキームでアプリを起動する iPhone 用ランチャー（Launch Center Pro 風）。SwiftUI + WidgetKit、iOS 17 以上、Liquid Glass の API を使うため Xcode 26 以降でビルドする。ユーザーとのやり取りは日本語で行う。

## ビルド

Xcode プロジェクトは XcodeGen で生成する。`Geode.xcodeproj` と `Config/` は生成物で git 管理外なので、直接編集しない。設定は `project.yml` を変える。

```bash
xcodegen
```

```bash
xcodebuild -project Geode.xcodeproj -scheme Geode -destination 'generic/platform=iOS Simulator' build
```

- ファイルを追加・削除・改名したとき、`project.yml` を変えたときは `xcodegen` を再実行する
- 実機の署名は `Local.xcconfig`（git 管理外）の `DEVELOPMENT_TEAM` から読む。無い・空だと Team が None になり署名エラーになる。`./tools/update.sh` が git pull、Team ID の自動検出と保存、`xcodegen` をまとめて行うので、通常はこれを使う
- Bundle ID は `com.oshabery.geode` / `com.oshabery.geode.widget`、App Group は `group.com.oshabery.geode`。App Group は `project.yml` と `Shared/Models.swift` の `SharedStorage.appGroup` を必ず一致させる
- 無料の Apple ID（Personal Team）で署名している。実機のアプリは 7 日で期限切れになる

## 経緯と注意

このコードは当初、Swift ツールチェーンの無い環境で、ビルドせずに書かれた。ユーザーが Xcode でビルドと実機確認を行い、動作は確認済みだが、次は未検証のまま残っている。

- `App/AppCatalog.swift` の URL スキームと Bundle ID は記憶ベース。特に Leica FOTOS、VOX、アークナイツ、エンドフィールド、ポケポケのスキームは推定値
- `tools/import_installed_apps.py` は `xcrun devicectl` の JSON 出力形式を記憶で書いており、実行確認していない
- ウィジェット（`Widget/LaunchWidget.swift`）の実機での見た目と動作

変更したらビルドして確認すること。シミュレータでは他アプリの URL スキームをほとんど開けない（「起動エラー」になるのは正常）ので、起動の確認は実機で行う。

## 構成

| パス | 役割 |
|---|---|
| `Shared/Models.swift` | `LaunchItem` / `Board` / `GridLayout` と、App Group への保存（アプリとウィジェット共通） |
| `Shared/ItemIcon.swift` | アイコン表示、Liquid Glass のヘルパー（`glass` は UI 用、`iconGlass` はアイコン専用の強調版） |
| `App/BoardStore.swift` | 盤面の状態、URL 起動、ウィジェットからの `geode://run?id=` 処理、レイアウト変更 |
| `App/GridViews.swift` | `GridMetrics`（寸法計算）、通常モードのグリッド、グループ階層、グリッド線 |
| `App/EditGridView.swift` | 編集モード（追加・削除・ドラッグ移動） |
| `App/ItemEditor.swift` | アクション / グループの編集シート |
| `App/AppCatalog.swift` | 内蔵のアプリ辞書（URL スキーム） |
| `App/CatalogStore.swift` | 辞書全体（内蔵 + ユーザー登録 + 実機一覧）、非表示の管理 |
| `App/AppPicker.swift` | アプリ選択、非表示の項目、辞書への登録フォーム |
| `App/IconService.swift` | iTunes Search API からアイコン取得 |
| `App/ContentView.swift` | 上部バー（歯車 / 鉛筆）と設定画面 |
| `App/DockBar.swift` | 画面下部の 3 つのボタン |
| `Shared/HSBColor.swift` | HSB カラー（アプリとウィジェット共通） |
| `App/Theme.swift` | 色の初期値、文字の太さ、HSB 編集 UI |
| `Widget/LaunchWidget.swift` | ウィジェット（small / medium / large） |

## 設計上の決まり

- **グリッド**: スロット番号は `row * columns + column`。アイコンは正方形で、格子を表示領域（上部バーと下部ボタンの間）の中央に置く。横・縦の間隔（`gridGap` / `gridGapY`）は隣のアイコンとの距離で設定値そのまま、外側の余白（`outerMargin`）は端から最低限あける距離でアイコンの最大サイズを決める。余裕のある方向では端までの距離が設定より広くなる（仕様）。位置・当たり判定・グリッド線はすべて `GridMetrics` の値を使う
- **当たり判定**: `GridMetrics.slot(at:)` は格子の外で nil を返す。格子の外でのタップや指を離す操作では何も起動しない
- **グリッド線**: 各アイコンを同じ大きさのボックス（アイコン + 間隔の半分ずつ）で囲み、外枠も引く。アプリ名を表示しているときは「アイコン + 名前」のまとまりがボックスの中央に来る
- **ドック**: 画面下部の 3 つのボタン（`App/DockBar.swift`）。`Board.dock`（Optional）に保存し、アクションのみ置ける。盤面全体をたどる処理は `Board.topLevelItems` を使い、ドックを漏らさない（`cleanUpIcons` がアイコン画像を消してしまうため）
- **ベース色**: `LaunchItem.baseColor`（HSB 文字列、Optional）。画像の無いシンボルアイコンの下地に使う。`HSBColor` はウィジェットからも使うので `Shared/HSBColor.swift` に置く
- **グループ**: 指で触れている間だけ階層を表示する。アプリのあるマスで離すと起動、グループ自身のマスや空きマスで離すとホームに戻る。階層に入るとき `.rigid` の触覚を返す
- **保存**: 盤面は App Group の `board.json`。`Board` / `LaunchItem` に必須のフィールドを足すと既存データが読めなくなるので、足すならオプショナルにするか、設定は `@AppStorage` に置く（外観・色・サイズなどの設定はすべて `@AppStorage`）
- **アプリ検出**: iOS はインストール済みアプリを列挙できない。`canOpenURL` で判定できるのは `project.yml` の `LSApplicationQueriesSchemes` に宣言したスキームだけで、上限は 50 件（現在 41 件）。内蔵辞書にサードパーティのスキームを足したら両方に追加する
- **公開リポジトリ**: `Oshabery/Geode` は public。Team ID（`Local.xcconfig`）と実機のアプリ一覧（`App/InstalledApps.json`）は git 管理外のままにし、コミットしない
- **強調ガラス**: 虹色の縁などの強調表現（`GlassRim` / `GlassVolume`）はアプリアイコンだけに使う。ボタンなどの UI は標準の Liquid Glass

## 作業の進め方

- 変更は `main` に直接コミットしてプッシュしている（プルリクエストは使っていない）
- ユーザーは設定で調整できることを好む。見た目の値を決め打ちにする前に、設定項目にするか検討する
