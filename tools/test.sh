#!/bin/bash
# ビルドとテストを実行する。Mac でも CI でも同じ手順を使う。
#
#   ./tools/test.sh            Unit Test（既定）
#   ./tools/test.sh ui         UI Test（画面の撮影を含む）
#   ./tools/test.sh all        すべて
#   ./tools/test.sh build      ビルドだけ
#
# 結果は build/ に保存する（ログ、.xcresult、UI Test の画面）。
# シミュレータで、署名なしで実行する。実機や署名の設定には触れない。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-unit}"
mkdir -p build

# Team ID の設定ファイルが無いとプロジェクトを開けないので、無いときだけ空のものを作る（既存のものは触らない）
[ -f Local.xcconfig ] || touch Local.xcconfig

command -v xcodegen >/dev/null || { echo "xcodegen が必要です: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# 一番新しい iOS ランタイムの iPhone シミュレータを選ぶ
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)
for runtime in sorted(devices, key=version, reverse=True):
    if version(runtime)[0] < 0:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit("iPhone のシミュレータが見つかりません")
')
DEST="platform=iOS Simulator,id=$DEVICE_ID"
echo "シミュレータ: $DEVICE_ID"

# 先にシミュレータを起動しきっておく。起動途中に UI テストがアプリを立ち上げると、
# 「Timed out while launching application」で失敗することがある（CI の起動直後の端末で発生）
if [ "$MODE" = ui ] || [ "$MODE" = all ]; then
  xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE_ID" -b > /dev/null
fi

ACTION=test
ONLY=()
case "$MODE" in
  unit)  ONLY=(-only-testing:GeodeTests) ;;
  ui)    ONLY=(-only-testing:GeodeUITests) ;;
  all)   ;;
  build) ACTION=build ;;
  *) echo "使い方: $0 [unit|ui|all|build]"; exit 2 ;;
esac

RESULT="build/$MODE.xcresult"
rm -rf "$RESULT"
set +e
xcodebuild "$ACTION" \
  -project Geode.xcodeproj \
  -scheme Geode \
  -destination "$DEST" \
  -resultBundlePath "$RESULT" \
  ${ONLY[@]+"${ONLY[@]}"} \
  CODE_SIGNING_ALLOWED=NO \
  > "build/$MODE.log" 2>&1
STATUS=$?
set -e

# 要点だけ表示する（全文は build/<mode>.log）
grep -E "error:|Test Case .*(passed|failed|skipped)|Executed [0-9]+ test|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*" "build/$MODE.log" || true

# 失敗したときは、原因を追えるようにログの末尾と使えるシミュレータを表示する
# （CI ではログファイルを開けないため、ここに出さないと詳細が分からない）
if [ $STATUS -ne 0 ]; then
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::xcodebuild のログ（末尾 80 行）"
  echo "---- build/$MODE.log の末尾 ----"
  tail -n 80 "build/$MODE.log"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::使えるシミュレータ"
  echo "---- 使えるシミュレータ（選んだもの: $DEVICE_ID）----"
  xcrun simctl list devices available | grep -E "^-- |iPhone" || true
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
fi

# UI Test の画面を取り出す
if [ "$MODE" = ui ] || [ "$MODE" = all ]; then
  rm -rf build/screenshots
  if xcrun xcresulttool export attachments --path "$RESULT" --output-path build/screenshots >/dev/null 2>&1; then
    echo "画面: build/screenshots/"
  fi
fi

exit $STATUS
