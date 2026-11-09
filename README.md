# LaunchGrid

URL スキームでアプリを起動する iPhone 用ランチャー（SwiftUI + WidgetKit / iOS 17+）。

## ビルド

Mac + Xcode 15 以降が必要です。

```bash
brew install xcodegen
```

```bash
cd LaunchGrid && xcodegen && open LaunchGrid.xcodeproj
```

1. `project.yml` の `DEVELOPMENT_TEAM`、`com.example.launchgrid`（Bundle ID）、`group.com.example.launchgrid`（App Group）を自分のものに変更
2. App Group を変えたら `Shared/Models.swift` の `SharedStorage.appGroup` も同じ値に
3. `xcodegen` を再実行して実機でビルド

## 使い方

- **編集** → 空きマスの **＋** → 「グループ / アクション」を選択
- アクション編集画面の **アプリから選ぶ** で、名前・URL スキーム・アイコンを自動入力
- 編集メニュー（…）の **検出したアプリを一括配置** で、検出できたアプリをまとめて配置
- 編集中はドラッグで移動・入れ替え、× で削除、タップで再編集
- **グループ**: 触れた瞬間に中身が 1 レイヤー上に展開。指を滑らせて離すと起動（その場で離すと展開したまま）
- **レイアウト**: 編集メニューから列 2〜5・行 3〜8 を変更
- **ウィジェット**: small（1件）/ medium（8件）/ large（16件）。長押し→編集で表示するグループを選択

## 構成

| パス | 役割 |
|---|---|
| `Shared/` | モデル・App Group 保存・アイコン表示（アプリ/ウィジェット共通） |
| `App/AppCatalog.swift` | 既知アプリの URL スキーム辞書と検出 |
| `App/IconService.swift` | iTunes Search API からアイコン取得 |
| `App/GridViews.swift` | 通常モードのグリッドとグループ展開 |
| `App/EditGridView.swift` | 編集モード |
| `Widget/LaunchWidget.swift` | ウィジェット |

## アプリ・スキームを増やす

`App/AppCatalog.swift` に 1 行追加し、同じスキームを `project.yml` の
`LSApplicationQueriesSchemes` に追加します（iOS の制限で最大 50 件）。
