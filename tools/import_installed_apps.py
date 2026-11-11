#!/usr/bin/env python3
"""Mac につないだ iPhone のインストール済みアプリ一覧を取り込み、App/InstalledApps.json に書き出す。

使い方（リポジトリのルートで）:
    python3 tools/import_installed_apps.py            # 接続中の iPhone を自動選択
    python3 tools/import_installed_apps.py "Oshabery"  # デバイス名か識別子を指定

実行後に xcodegen を再実行してビルドすると、アプリ内の辞書に反映される。
InstalledApps.json は .gitignore 済み（アプリ一覧を公開リポジトリに載せないため）。
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "App", "InstalledApps.json")
OWN_PREFIX = "com.oshabery.geode"


def devicectl(*args):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "out.json")
        run = subprocess.run(["xcrun", "devicectl", *args, "--json-output", out],
                             capture_output=True, text=True)
        if run.returncode != 0 or not os.path.exists(out):
            sys.exit("devicectl が失敗しました:\n" + (run.stderr or run.stdout))
        with open(out, encoding="utf-8") as f:
            return json.load(f)


def pick_device():
    devices = devicectl("list", "devices").get("result", {}).get("devices", [])
    phones = [d for d in devices
              if d.get("hardwareProperties", {}).get("platform") == "iOS"]
    connected = [d for d in phones
                 if d.get("connectionProperties", {}).get("tunnelState") not in (None, "unavailable")]
    chosen = connected or phones
    if not chosen:
        sys.exit("iPhone が見つかりません。ケーブルで接続し、ロックを解除してから再実行してください。")
    if len(chosen) > 1:
        names = ", ".join(d.get("deviceProperties", {}).get("name", "?") for d in chosen)
        print(f"複数のデバイスがあります（{names}）。先頭を使います。引数で名前を指定できます。")
    device = chosen[0]
    print("デバイス:", device.get("deviceProperties", {}).get("name", "?"))
    return device["identifier"]


def main():
    device = sys.argv[1] if len(sys.argv) > 1 else pick_device()
    apps = devicectl("device", "info", "apps", "--device", device).get("result", {}).get("apps", [])
    seen, result = set(), []
    for app in apps:
        bundle_id = app.get("bundleIdentifier")
        name = app.get("name")
        if not bundle_id or not name or bundle_id in seen:
            continue
        if app.get("appClip") or app.get("hidden") or app.get("internalApp"):
            continue
        if bundle_id.startswith(OWN_PREFIX):
            continue
        seen.add(bundle_id)
        result.append({"name": name, "bundleId": bundle_id})
    result.sort(key=lambda a: a["name"].lower())
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"{len(result)} 件を {OUTPUT} に書き出しました。xcodegen を再実行してビルドしてください。")


if __name__ == "__main__":
    main()
