# Geode

URL スキームでアプリを起動する iPhone 用ランチャー（SwiftUI + WidgetKit / iOS 17+）。

## ビルド

Mac + Xcode 26 以降が必要です（Liquid Glass の API を使うため）。

```bash
brew install xcodegen
```

```bash
cd Geode && xcodegen && open Geode.xcodeproj
```

実機で動かす場合は、Team ID を `Local.xcconfig`（git 管理外）に書いてから `xcodegen` を実行します。

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Bundle ID は `com.oshabery.geode`、App Group は `group.com.oshabery.geode` です。変える場合は `project.yml` と `Shared/Models.swift` の `SharedStorage.appGroup` を揃えてください。

## 使い方

- 右上の **鉛筆** で編集モード → 空きマスの **＋** → 「グループ / アクション」を選択（チェックマークで終了）
- アクション編集画面の **アプリから選ぶ** で、名前・URL スキーム・アイコンを自動入力
- 編集中はドラッグで移動・入れ替え、× で削除、タップで再編集
- **グループ**: 触れている間だけ中身が 1 レイヤー上に展開。アプリの上まで指を滑らせて離すと起動（その場や空きマスで離すとホームに戻る）
- 左上の **歯車** で設定: 外観（自動 / ライト / ダーク）、ガラス風アイコン、背景色と UI の色（HSB）、アプリ名の太さ、グリッド線、アイコンサイズと余白、アプリ名の表示、列 2〜5・行 3〜8、検出したアプリの一括配置
- **ウィジェット**: small（1件）/ medium（8件）/ large（16件）。長押し→編集で表示するグループを選択

## Mac 上の Claude Code で開発する

Mac の Claude デスクトップアプリで Claude Code の新しいセッションを開始し、作業フォルダにこのリポジトリのフォルダを選びます。
そのセッションでは、`git pull`、`xcodegen`、ビルド、実機のアプリ一覧の取り込みまで Claude が直接実行できます。

プロジェクトの経緯・構成・決まりごとは `CLAUDE.md` にまとめてあり、新しいセッションが自動で読み込みます。

## 構成

| パス | 役割 |
|---|---|
| `Shared/` | モデル・App Group 保存・アイコン表示（アプリ/ウィジェット共通） |
| `App/AppCatalog.swift` / `App/CatalogStore.swift` | アプリ辞書（内蔵 + ユーザー登録 + 実機一覧）と非表示の管理 |
| `App/IconService.swift` | iTunes Search API からアイコン取得 |
| `App/GridViews.swift` | 通常モードのグリッドとグループ階層 |
| `App/EditGridView.swift` | 編集モード |
| `App/ContentView.swift` / `App/Theme.swift` | 設定画面、色・文字の設定 |
| `Widget/LaunchWidget.swift` | ウィジェット |
| `tools/import_installed_apps.py` | 実機のアプリ一覧の取り込み |

## 実機のアプリ一覧を取り込む

iOS はアプリ内からインストール済みアプリの一覧を取得できないため、Mac 経由で取り込みます。
iPhone をつないでロックを解除し、次を実行してからビルドし直します。

```bash
python3 tools/import_installed_apps.py && xcodegen
```

取り込めるのはアプリ名と Bundle ID です。URL スキームは取得できないので、辞書に無いアプリは
アプリ選択画面で「スキームを登録」（右スワイプ）から入力します。

## アプリ・スキームを増やす

`App/AppCatalog.swift` に 1 行追加し、同じスキームを `project.yml` の
`LSApplicationQueriesSchemes` に追加します（iOS の制限で最大 50 件）。
