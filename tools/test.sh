#!/bin/bash
# ビルドとテストを実行する。Mac でも CI でも同じ手順を使う。
#
#   ./tools/test.sh            Unit Test（既定）
#   ./tools/test.sh ui         UI Test（画面の撮影を含む）
#   ./tools/test.sh all        すべて
#   ./tools/test.sh build      ビルドだけ
#
#   GEODE_DEVICE=ipad ./tools/test.sh ui   iPad のシミュレータで実行する（既定は iPhone）
#
# 結果は build/ に保存する（ログ、.xcresult、UI Test の画面）。iPad の結果は名前に -ipad が付く。
# シミュレータで、署名なしで実行する。実機や署名の設定には触れない。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-unit}"
mkdir -p build

# 使う端末（iPhone / iPad）と、結果のファイル名
case "${GEODE_DEVICE:-iphone}" in
  iphone|iPhone) FAMILY=iPhone; NAME="${MODE}" ;;
  ipad|iPad)     FAMILY=iPad;   NAME="${MODE}-ipad" ;;
  *) echo "GEODE_DEVICE は iphone か ipad です"; exit 2 ;;
esac

# Team ID の設定ファイルが無いとプロジェクトを開けないので、無いときだけ空のものを作る（既存のものは触らない）
[ -f Local.xcconfig ] || touch Local.xcconfig

command -v xcodegen >/dev/null || { echo "xcodegen が必要です: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# 一番新しい iOS ランタイムの iPhone（または iPad）シミュレータを選ぶ
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
        if d["name"].startswith(sys.argv[1]):
            print(d["udid"]); sys.exit(0)
sys.exit(sys.argv[1] + " のシミュレータが見つかりません")
' "${FAMILY}")
DEST="platform=iOS Simulator,id=${DEVICE_ID}"
echo "シミュレータ（${FAMILY}）: ${DEVICE_ID}"

# 先にシミュレータを起動しきっておく。起動途中に UI テストがアプリを立ち上げると、
# 「Timed out while launching application」で失敗することがある（CI の起動直後の端末で発生）
if [ "${MODE}" = ui ] || [ "${MODE}" = all ]; then
  xcrun simctl boot "${DEVICE_ID}" 2>/dev/null || true
  xcrun simctl bootstatus "${DEVICE_ID}" -b > /dev/null
fi

ACTION=test
ONLY=()
case "${MODE}" in
  unit)  ONLY=(-only-testing:GeodeTests) ;;
  ui)    ONLY=(-only-testing:GeodeUITests)
         # iPad では iPad の回転のテストだけを行う（共通の画面のテストは iPhone で行う。録画を短くし、シミュレータの時間切れを減らす）
         if [ "$FAMILY" = iPad ]; then
           ONLY=()
           for t in testPadGridStaysFixedWhenRotated testPadLandscapeArrangementIsSeparate \
                    testPadLaunchInLandscapeMatchesRotation testPadRevealAnimation testPadSystemRotationBaseline; do
             ONLY+=("-only-testing:GeodeUITests/GeodeUITests/$t")
           done
         fi ;;
  all)   ;;
  build) ACTION=build ;;
  *) echo "使い方: $0 [unit|ui|all|build]"; exit 2 ;;
esac

RESULT="build/${NAME}.xcresult"
rm -rf "$RESULT"

# iPad の UI テストは画面を録画する（回転の見え方を確かめるため。テストは回す直前に GEODE-ROTATE と時刻を出力する）
REC_PID=""
if [ "$FAMILY" = iPad ] && { [ "$MODE" = ui ] || [ "$MODE" = all ]; }; then
  rm -f "build/${NAME}.mp4"
  xcrun simctl io "$DEVICE_ID" recordVideo --codec=h264 --force "build/${NAME}.mp4" > "build/${NAME}-video.log" 2>&1 &
  REC_PID=$!
  sleep 2
  # 録画の開始時刻（UNIX 時間）。テストの GEODE-ROTATE の時刻から引くと、録画の中の位置が分かる（おおよそ）
  python3 -c "import time; print(time.time())" > "build/${NAME}-video-start.txt"
  echo "録画の開始: $(cat "build/${NAME}-video-start.txt")"
fi

set +e
xcodebuild "$ACTION" \
  -project Geode.xcodeproj \
  -scheme Geode \
  -destination "$DEST" \
  -resultBundlePath "$RESULT" \
  ${ONLY[@]+"${ONLY[@]}"} \
  CODE_SIGNING_ALLOWED=NO \
  > "build/${NAME}.log" 2>&1
STATUS=$?
set -e

if [ -n "$REC_PID" ]; then
  kill -INT "$REC_PID" 2>/dev/null || true
  wait "$REC_PID" 2>/dev/null || true
  echo "録画: build/${NAME}.mp4"
fi

# 要点だけ表示する（全文は build/<mode>.log）
grep -E "error:|Test Case .*(passed|failed|skipped)|Executed [0-9]+ test|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*|GEODE-ROTATE|横: ウィンドウ" "build/${NAME}.log" || true

# 失敗したときは、原因を追えるようにログの末尾と使えるシミュレータを表示する
# （CI ではログファイルを開けないため、ここに出さないと詳細が分からない）
if [ $STATUS -ne 0 ]; then
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::xcodebuild のログ（末尾 80 行）"
  echo "---- build/${NAME}.log の末尾 ----"
  tail -n 80 "build/${NAME}.log"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::使えるシミュレータ"
  echo "---- 使えるシミュレータ（選んだもの: ${DEVICE_ID}）----"
  xcrun simctl list devices available | grep -E "^-- |${FAMILY}" || true
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
fi

# UI Test の画面を取り出す
if [ "${MODE}" = ui ] || [ "${MODE}" = all ]; then
  SHOTS=build/screenshots
  [ "${FAMILY}" = iPad ] && SHOTS=build/screenshots-ipad
  rm -rf "${SHOTS}"
  if xcrun xcresulttool export attachments --path "$RESULT" --output-path "${SHOTS}" >/dev/null 2>&1; then
    echo "画面: ${SHOTS}/"
  fi
fi

exit $STATUS
