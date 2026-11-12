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
- 本体の操作（`App/SystemActions.swift`）: ショートカット App のアクション名（日本語）と消音モードのアクションの有無は記憶ベース。ショートカット経由のライトが点いたままになるか。Geode で上げた画面の明るさが Geode を離れても保たれるか。ミュージックの操作で許可を求められるか、再生状態の通知が届くか
- グローのライト（`glowLight`）: 文字・記号・縁・下のボタンの見やすさ、オン / オフの分かりやすさ、明るい画面の上でグループ階層の背景が暗く見えるか（初回の配色）
- グローの傾き: 光が動く向きが自然か（`GlowLight.direction` の符号）、滑らかさ、寝転んだときの挙動、発熱や電池の減り

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
| `App/SystemActions.swift` | 本体の操作（ライト・明るさ・ミュージックなどは Geode で直接、消音・Wi-Fi などはショートカット経由）と選択画面 |
| `Shared/HSBColor.swift` | HSB カラー（アプリとウィジェット共通） |
| `App/GlowStyle.swift` | 2 つ目のデザイン「グロー」（黒地に青い光、すりガラスのタイル、虹色の縁）の描画 |
| `App/Theme.swift` | 色の初期値、文字の太さ、HSB 編集 UI |
| `Widget/LaunchWidget.swift` | ウィジェット（small / medium / large） |

## 設計上の決まり

- **グリッド**: スロット番号は `row * columns + column`。アイコンは正方形で、格子を表示領域（上部バーと下部ボタンの間）の中央に置く。横・縦の間隔（`gridGap` / `gridGapY`）は隣のアイコンとの距離で設定値そのまま、外側の余白（`outerMargin`）は端から最低限あける距離でアイコンの最大サイズを決める。余裕のある方向では端までの距離が設定より広くなる（仕様）。上下の位置（`gridOffsetY`）で格子全体をずらせるが、表示領域からはみ出さない範囲まで（空いている高さの分だけ）。位置・当たり判定・グリッド線はすべて `GridMetrics` の値を使う
- **当たり判定**: `GridMetrics.slot(at:)` は格子の外で nil を返す。格子の外でのタップや指を離す操作では何も起動しない
- **グリッド線**: 各アイコンを同じ大きさのボックス（アイコン + 間隔の半分ずつ）で区切る。一番外側の枠線は引かない（ユーザーの指定）。濃さは `gridLineOpacity`（0.05...1、1 が既定）を色指定あり・なしの両方に掛ける。アプリ名を表示しているときは「アイコン + 名前」のまとまりがボックスの中央に来る
- **ドック**: 画面下部の 3 つのボタン（`App/DockBar.swift`）。`Board.dock`（Optional）に保存し、アクションのみ置ける。未割り当てのボタンは通常モードでは表示せず（位置は空けておく）、編集モードでだけ灰色の「＋」を出す（ユーザーの指定）。編集モードの操作はグリッドとそろえる（× で削除、タップで編集、ドラッグで入れ替え）。盤面全体をたどる処理は `Board.topLevelItems` を使い、ドックを漏らさない（`cleanUpIcons` がアイコン画像を消してしまうため）
- **ベース色**: `LaunchItem.baseColor`（HSB 文字列、Optional）。画像の無いシンボルアイコンの下地に使う。`HSBColor` はウィジェットからも使うので `Shared/HSBColor.swift` に置く
- **グループ**: 指で触れている間だけ階層を表示する。アプリのあるマスで離すと起動、グループ自身のマスや空きマスで離すとホームに戻る。階層に入るとき `.rigid` の触覚を返す。階層の背景（`GroupBackdrop`）は画面全体を覆い（グリッドの枠で切ると四角い境界が見えるため）、押しているグループの周りだけ薄くする。開いている間は `store.groupLayerOpen` で `LauncherGridView` を最前面にし、背景は触っても反応しない。中身のアイコンは押した指の位置を中心に、わずかに（0.92 倍から）広がって出る。大きく動かすと定位置に着くまで遅く見えるため、移動距離は小さく保つ（押しているグループ自身は別の層で薄く出すだけ。ウィジェットから開いたときは中央から）。入るときの動きは、出だしが速く終わりに余韻が残るカーブ（`LauncherGridView.openAnimation`、0.3 秒）。出だしを遅くしないこと（ユーザーがもたつきを嫌う）。戻るときは短く（0.22 秒）
- **保存**: 盤面は App Group の `board.json`。`Board` / `LaunchItem` に必須のフィールドを足すと既存データが読めなくなるので、足すならオプショナルにするか、設定は `@AppStorage` に置く（外観・色・サイズなどの設定はすべて `@AppStorage`）
- **アプリ検出**: iOS はインストール済みアプリを列挙できない。`canOpenURL` で判定できるのは `project.yml` の `LSApplicationQueriesSchemes` に宣言したスキームだけで、上限は 50 件（現在 41 件）。内蔵辞書にサードパーティのスキームを足したら両方に追加する
- **公開リポジトリ**: `Oshabery/Geode` は public。Team ID（`Local.xcconfig`）と実機のアプリ一覧（`App/InstalledApps.json`）は git 管理外のままにし、コミットしない
- **実機で確認済み**: Geode で直接点けたライトは Geode を離れると消える（そのためショートカット経由のライトも用意）。ライトの使用でカメラの許可は求められない。ショートカット実行後は `x-success=geode://` で Geode に戻る
- **スイッチ**: オン / オフの操作は、オンの間アイコンをネガポジ反転して示す（シンボルは記号と下地の色を入れ替え、画像は色を反転。小さなスイッチ表示はユーザーの指定でやめた）。押すと `.rigid` の触覚を返す（`BoardStore.launch` だけで行う）。Geode で直接の操作（`DirectKind.isSwitch`）は URL から判定し、実際の状態を読む（`directActionPerformed` 通知、前面復帰時、ミュージックの再生状態通知で `refreshDirectStates`）。ショートカット経由は `isToggle == true` で、状態を読めないので推定値。`geode://` への成功の戻りで切り替え、設定画面で手動補正できる。推定値は `UserDefaults` の `toggleStates`（盤面とは別）
- **本体の操作**: Geode 自身が実行する操作は `geode://<操作名>` の URL で表し（`DirectKind`: torch / brightness / awake / music-playpause / music-next / music-previous / copy?text=）、知らない操作名はエラーにする。電話・メッセージ・メール・FaceTime・Web・経路は通常の URL（tel: など）を組み立てる。`SystemActions.performIfBuiltIn` を `BoardStore.launch` とテスト起動の両方から通す。消音・Wi-Fi など iOS が公開 API を持たない操作は、ショートカット App のショートカットを `shortcuts://x-callback-url/run-shortcut?name=` で実行する
- **デザイン**: 設定の「デザイン」（`@AppStorage("uiStyle")`）で「標準」と「グロー」を切り替える。標準を選んでいる間はこれまでの見た目を一切変えないこと（ユーザーの条件。グローの描画は `App/GlowStyle.swift` に置き、各所は `if/else` で分岐）。グローの色は `@AppStorage("glowHue")`（色相 0–360、プリセットは `GlowPalette.presets`）で、ベース色を指定したアイテムはその色相を優先する。「グラデ」（`glowGradient`）はアプリアイコンの配色（中心の色相からのずれ `GlowPalette.gradientOffsets`: コーラル・ピンク・パープル・ブルー・シアン）で、背景に左上の暖色と右下の寒色の光を足し、タイルとボタンを上ピンク寄り → 下ブルー寄りにする。色相のスライダーで全体がそろってずれる。グローの明るさは `glowLight`（既定はダーク）で、グローの各ビューは `colorScheme` を見てライト用の配色に分岐する（ダークの見た目は変えないこと）。グループ階層の中身は背景が暗いのでグローでは常にダークで描く。グローは表示時だけ配色を固定し、保存済みの外観・背景色・ガラス風アイコンの設定は書き換えない。グローのタイルではぼかしと影を使わない（グループ表示を重くしないため）。傾き（`GlowMotion`、CoreMotion の重力）で光の向き（`GlowLight`）を動かす。傾き 0 では真下からの光。ライトの強さは `glowIntensity`（1...10、5 が基準）で、背景の色の光の濃さと広がり、タイルの外にこぼれる光に効く。地の色は真っ黒ではなく `Color(white: 0.04)`（ユーザーの指定）。タイルの外の光は傾きで動く幅を小さくしてある（`GlowUnderLight.travel`）。視差: 通常モードのグリッド（グループ内を含む）のアイコンは傾きと逆へ最大 `glowParallax` pt ずれる（`GlowParallax`、見た目だけで当たり判定は動かさない。編集中は動かさない）。傾きは重力から角度（左右 asin、前後は y-z 面の角度）に直して縦横同じ感度にし、ベクトルの長さで 1 までに抑える。60 回/秒で読み、視差は速い `GlowParallaxMotion`（ほぼ遅れなし）、光は `GlowMotion.tilt`（なめらか、2 回に 1 回）と分けている。向きは `GlowMotion.signX/signY` と `GlowLight.direction`。傾きは末端の小さなビュー（`GlowEdges` / `GlowSurfaceLight` / `GlowUnderLight` / `GlowBackground`）だけが購読し、`ContentView` や `TileView` では購読しない（毎回グリッド全体が描き直されるため）。縁の屈折の色は下の色相（グローの色 / ベース色 / 画像の代表色）に合わせ、加算（`.plusLighter`）で重ねる。導入前の状態はコミット `793cda4`
- **強調ガラス**: 虹色の縁などの強調表現（`GlassRim` / `GlassVolume`）はアプリアイコンだけに使う。ボタンなどの UI は標準の Liquid Glass

## 作業の進め方

- 設定画面の各まとまりは `SettingsGroup`（折りたたみ、開閉状態は `settingsOpen.<id>` に保存、最初は閉じている）で作る

- 変更は `main` に直接コミットしてプッシュしている（プルリクエストは使っていない）
- ユーザーは設定で調整できることを好む。見た目の値を決め打ちにする前に、設定項目にするか検討する
