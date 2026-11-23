# Geode

URL スキームでアプリを起動する iPhone / iPad 用ランチャー（Launch Center Pro 風）。SwiftUI + WidgetKit、iOS 17 以上、Liquid Glass の API を使うため Xcode 26 以降でビルドする。ユーザーとのやり取りは日本語で行う。

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
- 対応端末は iPhone と iPad（`TARGETED_DEVICE_FAMILY: "1,2"`）。iPhone は縦向きのみ、iPad は 4 方向すべてと Split View / Stage Manager に対応する（iPadOS 26 では縦に固定しても無視され、縮小・黒帯つきで表示されたため。CI の iPadOS 26.5 シミュレータで確認）。iPad を回したときの見せ方は下の「iPad の縦と横」。iPad では設定の列を 8、行を 10 まで増やせる
- **iPad の縦と横（ユーザーの指定）**: グリッド（マス目・行と列）と背景は、端末を回してもガラス面に貼り付いたように動かさない。行と列は縦横で共通（`Board.layout`）で、アイコンの並びだけが縦と横で別（`Board.landscapeSlots`、Optional。横で最初に編集するまでは縦と同じ並び）。アイコン（と名前）は持った向きで読めるように回る（環境値 `geodeIconAngle` を `GridCells` と編集画面のタイルが使う。ドラッグの移動量は回さない）。上の「設定」「編集」ボタンはウィンドウ側にあり、持った向きの上の角へ移る（グループを開いている間は隠す）。グリッドは、ボタンがどの辺にも来うるので四辺ともボタンとステータスバーの分を空ける。向きは `CanvasOrientation.isLandscape`（ウィンドウが端末に対して 90° 回っているか）で決め、表示・タッチ・編集・一括配置は `Board.slots(for:)` / `setSlots(_:for:)` を通す。行と列の変更（`Board.changeLayout`）は縦と横の両方の並びを移し、どちらかが収まらなければ変えない。ウィジェットは縦の並びを使う。向きが変わると編集中の状態は作り直し、開いているグループは閉じる。通常モードのアイコンはアイテムの ID で識別し、並びの切り替えで新しいマスへ動く。左右どちらの横向きでも同じ横の並びを使うので、ホームボタン（またはカメラ）の位置で見え方が 180° 変わる。以前の版（横画面で行と列を入れ替えていた頃）に保存した横の並びは `landscapeSharesGrid` が無いので使わない（データは消さずに残し、ユーザーの承認済み）
- **回転の仕組み**（`App/CanvasRotation.swift`）: ウィンドウの向きは iOS が変えるが、`FixedCanvasController.viewWillTransition` で `UIView.setAnimationsEnabled(false)` にして回転のアニメーションを止め、一瞬で切り替える（終わったら戻す）。グリッドと背景は `FixedCanvas`（UIKit の UIHostingController）に入れ、端末を縦に持ったときの大きさで描いて、ウィンドウの回転の逆向きに回して置くので、切り替わっても画面上の位置が変わらない。回転の間（`viewWillTransition` から完了まで）はアイコンを隠し（`CanvasOrientation.hideIcons`）、完了時にキャンバスを置き直してアイコンの向きと縦 / 横の並びを変え、UIView のアニメーションを戻した後の次の周回で、アイコンを弾ませて出し直す（`revealIcons` → `OrientationReveal`。ユーザーの指定: 一度消えてから、イーズインアウトのカーブで横にふくらむ → 縦に伸びる → 落ち着く、と弾むように出る。グリッドの中央から外へ最大 0.12 秒ずつ遅らせる）。アニメーションを止めている間に始めた SwiftUI のアニメーションは一瞬で終わってしまうので、出し直しは必ず回転の後に始める（CI の録画で確認）。`setAnimationsEnabled(false)` では iOS の回転のアニメーションを確実には止められず、回し始めに 0.1〜0.3 秒傾いた画面が見えることがある（CI の録画で回によって違う）。端末の向きの通知で先に止める方式も試したが改善せず、アプリ全体のアニメーションを止めてしまうのでやめた。編集モードでは上に「縦画面の並びを編集中 / 横画面の並びを編集中」を出す。編集モードの削除ボタン（×）はタイルより上の層に置く（タイルの中だと、アイコンを回したとき × が隣のマスにかかり、隣のタイルのタップが先に反応した）。試してやめた方式: Info.plist で縦固定（iPadOS 26 で無視され縮小・黒帯）、`prefersInterfaceOrientationLocked`（シミュレータで効かず、実機で 2 回回って見えた）、iOS の回転アニメーションに合わせて `animate(alongsideTransition:)` で逆に回す（iPadOS 26 ではウィンドウごと回る様子が見え、グリッドが大きく傾いた）。`FixedCanvas` の中は別の UIHostingController なので、`environmentObject`・tint・配色はそこで渡し直す。安全領域は Geode が空ける（`safeAreaRegions = []`）。グローの傾きは、iPad では端末の座標のまま使う。UI テスト（iPad）: `testPadGridStaysFixedWhenRotated`（キャンバスの角の目印 `geode-canvas-origin` が回しても画面上の同じ場所に残る、設定ボタンが持った向きの左上へ移って押せる）、`testPadLaunchInLandscapeMatchesRotation`（横に持ったまま起動しても同じ置き方）、`testPadLandscapeArrangementIsSeparate`（横で消したアイコンが縦には残る）、`testPadRevealAnimation`（起動引数 `-GeodeRevealLoop` で、回さずに 3 秒ごとに出し直す。動きを録画で見る）、`testPadSystemRotationBaseline`（起動引数 `-GeodeSystemRotation` で従来の iOS の回転。比較用で判定しない）。見本の盤面は起動引数 `-GeodeSampleBoard`（縦と横で並びの違うアイコン 3 つ）。`tools/test.sh` は iPad では iPad の回転のテストだけを行って録画し（`build/ui-ipad.mp4` と開始時刻 `build/ui-ipad-video-start.txt`、CI の成果物）、テストは回す直前に `GEODE-ROTATE` と時刻を出す。回転中の見え方は録画のコマで確かめる
- 無料の Apple ID（Personal Team）で署名している。実機のアプリは 7 日で期限切れになる

## 経緯と注意

このコードは当初、Swift ツールチェーンの無い環境で、ビルドせずに書かれた。ユーザーが Xcode でビルドと実機確認を行い、動作は確認済みだが、次は未検証のまま残っている。

- `App/AppCatalog.swift` の URL スキームと Bundle ID は記憶ベース。特に Leica FOTOS、VOX、アークナイツ、エンドフィールド、ポケポケのスキームは推定値
- `tools/import_installed_apps.py` は `xcrun devicectl` の JSON 出力形式を記憶で書いており、実行確認していない
- ウィジェット（`Widget/LaunchWidget.swift`）の実機での見た目と動作
- 本体の操作（`App/SystemActions.swift`）: ショートカット App のアクション名（日本語）と消音モードのアクションの有無は記憶ベース。ショートカット経由のライトが点いたままになるか。Geode で上げた画面の明るさが Geode を離れても保たれるか。ミュージックの操作で許可を求められるか、再生状態の通知が届くか
- グローのライト（`glowLight`）: 文字・記号・縁・下のボタンの見やすさ、オン / オフの分かりやすさ、明るい画面の上でグループ階層の背景が暗く見えるか（初回の配色）
- iPad: 実機での回転の見え方（グリッドが動かないか、黒い部分が出ないか、逆さ向き）、横向きでのグリッドのタッチ位置と編集のドラッグ、Split View / Stage Manager の小さなウィンドウ、ボタン（上の角）とグリッドの重なり
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
- **画面下端**: iOS は下端付近のタッチをホームへのスワイプか見分けるために遅らせる。設定「下端のタッチを優先する」（`preferBottomTouches`、既定オフ）で `.defersSystemGestures(on: .bottom)` を有効にできる（代わりにホームへ戻るのは 2 回スワイプ）
- **当たり判定**: `GridMetrics.slot(at:)` は格子の外で nil を返す（格子の外周から `edgeHitSlop` = 24pt までは一番近いマスに当てる。外周のアイコンだけ反応しにくかったため）。それより外でのタップや指を離す操作では何も起動しない
- **グリッド線**: 各アイコンを同じ大きさのボックス（アイコン + 間隔の半分ずつ）で区切る。一番外側の枠線は引かない（ユーザーの指定）。濃さは `gridLineOpacity`（0.05...1、1 が既定）を色指定あり・なしの両方に掛ける。アプリ名を表示しているときは「アイコン + 名前」のまとまりがボックスの中央に来る
- **ドック**: ユーザーの指定で一旦外している（`DockBar.enabled = false`。画面にも設定にも出さないが、コードと `Board.dock` のデータは残してあり、true に戻せば元どおり）。画面下部の 3 つのボタン（`App/DockBar.swift`）。`Board.dock`（Optional）に保存し、アクションのみ置ける。未割り当てのボタンは通常モードでは表示せず（位置は空けておく）、編集モードでだけ灰色の「＋」を出す（ユーザーの指定）。編集モードの操作はグリッドとそろえる（× で削除、タップで編集、ドラッグで入れ替え）。盤面全体をたどる処理は `Board.topLevelItems` を使い、ドックを漏らさない（`cleanUpIcons` がアイコン画像を消してしまうため）
- **通知バッジ**: ユーザーの指定で外している（`BadgeRing.enabled = false`）。オフの間は、画面にも編集画面にも出さず、起動時にバッジを外す処理も動かさない（保存済みの `showBadge` はそのまま残るので、true に戻せば元どおり）。オンのときの仕様: `LaunchItem.showBadge`（Optional）を編集画面で付け外しし、アイコンを薄く透き通った赤いガラスの細い縁（`BadgeRing`）で囲む。Geode から起動すると外れる（`Board.clearBadge`）。iOS はほかのアプリの未読を読み取れないので自動では付かない
- **ベース色**: `LaunchItem.baseColor`（HSB 文字列、Optional）。画像の無いシンボルアイコンの下地に使う。`HSBColor` はウィジェットからも使うので `Shared/HSBColor.swift` に置く
- **グループ**: 指で触れている間だけ階層を表示する。指がグループの上に来た時点で開き（置いた位置が少しずれていても、滑らせて乗せても開く）、離すかタッチが取り消されるまで開いたまま。タッチは SwiftUI のジェスチャーではなく `TouchSurface`（UIKit の touchesBegan/Moved/Ended/Cancelled）で直接受け取る。SwiftUI の DragGesture では、指を置いたまま動かさないと開くまで数秒かかることがあったため。タッチの始まりは `TouchSession` でも判断する。アプリのあるマスで離すと起動、グループ自身のマスや空きマスで離すとホームに戻る。階層に入るとき `.rigid` の触覚を返す。階層の背景（`GroupBackdrop`）は画面全体を覆い（グリッドの枠で切ると四角い境界が見えるため）、押しているグループの周りだけ薄くする。開いている間は `store.groupLayerOpen` で `LauncherGridView` を最前面にし、背景は触っても反応しない。中身のアイコンはグループのマスから外へ、近いものから順に出る（`GroupChildAppear`）。距離は上下左右 1 マスを 1、斜め 1 マスを 1.5 として数え、3 で頭打ち。隣のマス（距離 1）は遅れなしで、それより遠いものは距離 1 増えるごとに 0.035 秒遅れる。移動量はマスの間隔の 9% × 距離（`entranceDelayPerUnit` / `entranceTravelPerUnit`）。大きく動かすと定位置に着くまで遅く見えるため、移動距離は小さく保つ（押しているグループ自身は別の層で薄く出すだけ）。入るときの動きは、出だしが速く終わりに余韻が残るカーブ（`LauncherGridView.openAnimation`、0.3 秒）。出だしを遅くしないこと（ユーザーがもたつきを嫌う）。戻るときは短く（0.22 秒）
- **保存**: 盤面は App Group の `board.json`。`Board` / `LaunchItem` に必須のフィールドを足すと既存データが読めなくなるので、足すならオプショナルにするか、設定は `@AppStorage` に置く（外観・色・サイズなどの設定はすべて `@AppStorage`）
- **アプリ検出**: iOS はインストール済みアプリを列挙できない。`canOpenURL` で判定できるのは `project.yml` の `LSApplicationQueriesSchemes` に宣言したスキームだけで、上限は 50 件（現在 41 件）。内蔵辞書にサードパーティのスキームを足したら両方に追加する
- **公開リポジトリ**: `Oshabery/Geode` は public。Team ID（`Local.xcconfig`）と実機のアプリ一覧（`App/InstalledApps.json`）は git 管理外のままにし、コミットしない
- **実機で確認済み**: Geode で直接点けたライトは Geode を離れると消える（そのためショートカット経由のライトも用意）。ライトの使用でカメラの許可は求められない。ショートカット実行後は `x-success=geode://` で Geode に戻る
- **スイッチ**: オン / オフの操作は、オンの間アイコンをネガポジ反転して示す（シンボルは記号と下地の色を入れ替え、画像は色を反転。小さなスイッチ表示はユーザーの指定でやめた）。押すと `.rigid` の触覚を返す（`BoardStore.launch` だけで行う）。Geode で直接の操作（`DirectKind.isSwitch`）は URL から判定し、実際の状態を読む（`directActionPerformed` 通知、前面復帰時、ミュージックの再生状態通知で `refreshDirectStates`）。ショートカット経由は `isToggle == true` で、状態を読めないので推定値。`geode://` への成功の戻りで切り替え、設定画面で手動補正できる。推定値は `UserDefaults` の `toggleStates`（盤面とは別）
- **本体の操作**: Geode 自身が実行する操作は `geode://<操作名>` の URL で表し（`DirectKind`: torch / brightness / awake / music-playpause / music-next / music-previous / copy?text=）、知らない操作名はエラーにする。電話・メッセージ・メール・FaceTime・Web・経路は通常の URL（tel: など）を組み立てる。`SystemActions.performIfBuiltIn` を `BoardStore.launch` とテスト起動の両方から通す。消音・Wi-Fi など iOS が公開 API を持たない操作は、ショートカット App のショートカットを `shortcuts://x-callback-url/run-shortcut?name=` で実行する
- **デザイン**: 設定の「デザイン」（`@AppStorage("uiStyle")`）で「標準」と「グロー」を切り替える。標準を選んでいる間はこれまでの見た目を一切変えないこと（ユーザーの条件。グローの描画は `App/GlowStyle.swift` に置き、各所は `if/else` で分岐）。グローの色は `@AppStorage("glowHue")`（色相 0–360、プリセットは `GlowPalette.presets`）で、ベース色を指定したアイテムはその色相を優先する。「グラデ」（`glowGradient`）はアプリアイコンの配色（中心の色相からのずれ `GlowPalette.gradientOffsets`: コーラル・ピンク・パープル・ブルー・シアン）で、背景の下からの光の色を左から右へ 3 色（ピンク → パープル → ブルー）に移り変わらせ、タイルとボタンを上ピンク寄り → 下ブルー寄りにする。色相のスライダーで全体がそろってずれる。「モノトーン」（`glowMono`）は、グローの色から作る背景・タイル・記号・下の光・丸いボタンだけ `.saturation(0)` で色を抜く（ベース色のアイコンと画像は色のまま）。グローの明るさは `glowLight`（既定はダーク）で、グローの各ビューは `colorScheme` を見てライト用の配色に分岐する（ダークの見た目は変えないこと）。グローのライトではグループ階層の背景も明るいすりガラス（中心は透け、離れるほど白い霧）にし、中身もライトの配色で描く。グローは表示時だけ配色を固定し、保存済みの外観・背景色・ガラス風アイコンの設定は書き換えない。グローのタイルではぼかしと影を使わない（グループ表示を重くしないため）。傾き（`GlowMotion`、CoreMotion の重力）で光の向き（`GlowLight`）を動かす。傾き 0 では真下からの光。ライトの強さは `glowIntensity`（1...10、5 が基準）で、背景の色の光の濃さと広がり、タイルの外にこぼれる光、シンボルのタイルと丸いボタンの色の濃さ・明るさ（`GlowPalette.tileScale`、オンの状態は変えない）に効く。地の色は真っ黒ではなく `Color(white: 0.04)`（ユーザーの指定）。タイルの外の光は傾きで動く幅を小さくしてある（`GlowUnderLight.travel`）。グローのライトでは、この光の代わりに同じ形の影を落とす（傾きでは光と反対側へ動く）。視差: 通常モードのグリッド（グループ内を含む）のアイコンは傾きと逆へ最大 `glowParallax` pt ずれる（`GlowParallax`、見た目だけで当たり判定は動かさない。編集中は動かさない）。傾きは重力から角度（左右 asin、前後は y-z 面の角度）に直して縦横同じ感度にし、ベクトルの長さで 1 までに抑える。120 回/秒で読み（`CADisableMinimumFrameDurationOnPhone` で 120Hz 表示を許可）、視差は速い `GlowParallaxMotion`（ほぼ遅れなし）、光・反射・影は `GlowMotion.tilt`（少しなめらか、60 回/秒。全アイコン分の描き直しでタッチへの反応が遅れないよう間引く）と分けている。向きは `GlowMotion.signX/signY` と `GlowLight.direction`。重力は画面の向き（横向き・逆さ）に合わせて画面の座標に直してから使い（`GlowMotion.screenGravity`）、向きが変わったら基準の姿勢を取り直す。傾きは末端の小さなビュー（`GlowEdges` / `GlowSurfaceLight` / `GlowUnderLight` / `GlowBackground`）だけが購読し、`ContentView` や `TileView` では購読しない（毎回グリッド全体が描き直されるため）。アイコンの表面には傾きですべる丸い照明の映り込み（`GlowSpecular`、端がなだらかに消える放射グラデーション）を乗せる（画像・シンボルの両方）。縁の屈折の色は下の色相（グローの色 / ベース色 / 画像の代表色）に合わせ、加算（`.plusLighter`）で重ねる。導入前の状態はコミット `793cda4`
- **ガラス風アイコン**: 標準デザインの「アイコンをガラス風にする」設定はユーザーの指定で削除した（`ItemIcon` の `glass` 引数と `GlassRim` / `GlassVolume` は使われていない）。ボタンなどの UI は標準の Liquid Glass

## ブランチとマージ

ユーザーが指定した運用。以後のセッションでも必ず守る。

- 作業は 1 本の作業ブランチ（`claude/` で始まる名前。現在は `claude/work`）に積む。`main` へ直接 push しない
- 修正のたびにコミットして作業ブランチへ push する。ユーザーは Mac で作業ブランチをそのまま pull して確認するので、確認のためにマージは不要
- `main` へまとめるのは週 1 回だけ。テストが通るたびにまとめなくてよい
- まとめる時期の声かけはユーザーがする。「マージの準備をして」と言われたら、次の手順で PR を用意する
  1. 作業ブランチと `main` の差を確かめる。差がなければ「まとめるものはありません」と伝える
  2. 作業ブランチ → `main` の PR を作る（すでに開いていれば、説明を最新に更新する）
  3. PR の説明に日本語で書く: 前回のマージからの変更点、テスト結果（分からなければ「未確認」）、実機などで確認が必要な点、マージ方法は「Create a merge commit」
  4. PR のリンクと、マージ前に確認してほしい点を短く伝える
- マージはユーザーが GitHub で「Create a merge commit」で行う。Squash・Rebase は使わない（Mac 側の pull がつながらなくなるため）。**Claude は PR をマージしない**
- ビルドやテストが通っていない状態のときは、PR のリンクを渡す前にそのことを先に伝える
- マージされたら、作業ブランチを同じ名前のまま最新の `main` から作り直して作業を続ける（Mac はブランチを切り替えずに pull を続けられる）
- CI は作業ブランチ（`claude/**`）への push でも動く（`claude/` からの PR では二重に動かさない）。push のあとは CI の結果を確認し、失敗していればユーザーに伝える

## 作業の進め方

- 設定画面の各まとまりは `SettingsGroup`（折りたたみ、開閉状態は `settingsOpen.<id>` に保存、最初は閉じている）で作る

- 署名・証明書・プロビジョニング、Bundle ID、Entitlements・Capabilities、App Store / TestFlight への提出や配信、課金、保存データを消す・作り直す変更は、入れる前に内容を説明してユーザーの承認を得る
- ユーザーは設定で調整できることを好む。見た目の値を決め打ちにする前に、設定項目にするか検討する
