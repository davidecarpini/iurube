#!/bin/bash
# Usage: ./scripts/simulator.sh [test|live|run] [optional-simulator-UDID]
set -euo pipefail
cd "$(dirname "$0")/.."
action="${1:-test}"
if [[ "$action" != "test" && "$action" != "live" && "$action" != "run" ]]; then
  echo "Uso: $0 [test|live|run] [UDID]" >&2
  exit 2
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode completo non disponibile. Installa Xcode dall’App Store, aprilo e completa la configurazione iniziale." >&2
  echo "Poi rilancia questo script. I Command Line Tools da soli non includono il simulatore iOS." >&2
  exit 1
fi
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "Apri Xcode e completa la configurazione iniziale (licenza e componenti)." >&2
  exit 1
fi
mkdir -p build
if ! xcrun simctl list runtimes -j | python3 -c 'import json,sys; sys.exit(not any(r.get("isAvailable") and "iOS" in r["name"] for r in json.load(sys.stdin)["runtimes"]))'; then
  xcodebuild -downloadPlatform iOS
fi
simulator="${2:-}"
if [[ -z "$simulator" ]]; then
  simulator=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; data=json.load(sys.stdin); devices=[d for runtime,items in data["devices"].items() if "iOS" in runtime for d in items if "iPhone" in d["name"] and d.get("isAvailable")]; devices.sort(key=lambda d: (d["state"] == "Booted", d["name"]), reverse=True); print(devices[0]["udid"] if devices else "")')
fi
if [[ -z "$simulator" ]]; then
  read -r runtime runtime_version < <(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]]; r.sort(key=lambda r:tuple(map(int,r["version"].split("."))),reverse=True); print(r[0]["identifier"], r[0]["version"])')
  device=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; parts=[int(p) for p in sys.argv[1].split(".")]; parts += [0]*(3-len(parts)); v=(parts[0]<<16)+(parts[1]<<8)+parts[2]; d=[d for d in json.load(sys.stdin)["devicetypes"] if d.get("productFamily")=="iPhone" and d.get("minRuntimeVersion",0)<=v<=d.get("maxRuntimeVersion",4294967295)]; print(d[0]["identifier"])' "$runtime_version")
  simulator=$(xcrun simctl create "iurub iPhone" "$device" "$runtime")
fi
if ! xcrun simctl list devices booted -j | python3 -c 'import json,sys; uid=sys.argv[1]; sys.exit(not any(d["udid"] == uid for ds in json.load(sys.stdin)["devices"].values() for d in ds))' "$simulator"; then
  xcrun simctl boot "$simulator"
fi
xcrun simctl bootstatus "$simulator" -b
# Ad-hoc simulator signing supplies application-identifier for Keychain access.
args=(-project iurub.xcodeproj -scheme iurub -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
if [[ "$action" == "test" || "$action" == "live" ]]; then
  # Give XCTest a clean launch, including after a previous normal simctl run.
  xcrun simctl terminate "$simulator" it.davidecarpini.iurub >/dev/null 2>&1 || true
  results="build/Tests-$(date +%Y%m%d-%H%M%S).xcresult"
  if [[ "$action" == "live" ]]; then
    export TEST_RUNNER_IURUB_LIVE=1
    args+=(-only-testing:iurubUITests/IurubLiveUITests)
  else
    args+=(-skip-testing:iurubUITests/IurubLiveUITests)
  fi
  xcodebuild "${args[@]}" -parallel-testing-enabled NO -resultBundlePath "$results" test
  echo "Risultati: $PWD/$results"
fi
# Install and launch without fixture arguments, so the user sees the real app.
xcodebuild "${args[@]}" build
xcrun simctl terminate "$simulator" it.davidecarpini.iurub >/dev/null 2>&1 || true
xcrun simctl install "$simulator" build/DerivedData/Build/Products/Debug-iphonesimulator/iurub.app
xcrun simctl launch "$simulator" it.davidecarpini.iurub
xcrun simctl io "$simulator" screenshot build/iurub-simulator.png
echo "iurub avviata sul simulatore $simulator"
