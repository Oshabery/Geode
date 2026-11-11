#!/bin/bash
# 最新を取り込み、署名の Team ID を Local.xcconfig に用意してから xcodegen を実行する。
# これ以降は `xcodegen` を直接叩く代わりに、常にこのスクリプトを使う:
#     ./tools/update.sh
# Team ID は次の順で探し、見つかったものを Local.xcconfig（git 管理外）に保存する。
#   1. Local.xcconfig に既に書いてある値
#   2. 既存の Geode.xcodeproj で選択されている Team（Xcode の画面で選んで保存した値）
#   3. キーチェーンの「Apple Development」証明書に記録されている Team
set -euo pipefail
cd "$(dirname "$0")/.."

git pull --ff-only || echo "⚠️  git pull できませんでした（未コミットの変更など）。手元の内容のまま続けます。"

team=""
source=""
if [ -f Local.xcconfig ]; then
  team=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]\{10\}\).*/\1/p' Local.xcconfig | head -1)
  [ -n "$team" ] && source="Local.xcconfig"
fi
if [ -z "$team" ] && [ -f Geode.xcodeproj/project.pbxproj ]; then
  team=$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\);.*/\1/p' Geode.xcodeproj/project.pbxproj | head -1)
  [ -n "$team" ] && source="Xcode で選択した Team"
fi
if [ -z "$team" ]; then
  team=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
  [ -n "$team" ] && source="キーチェーンの証明書"
fi

if [ -n "$team" ]; then
  echo "DEVELOPMENT_TEAM = $team" > Local.xcconfig
  echo "✅ Team ID: ${team}（${source}）"
else
  echo "⚠️  Team ID が見つかりませんでした。"
  echo "    Xcode で Geode ターゲットの Team を一度選んで保存（⌘S）し、もう一度このスクリプトを実行してください。"
fi

xcodegen
