#!/usr/bin/env bash
# Run with: bash scripts/validate-on-macos.sh
# Optional: SIMULATOR_UDID=<installed iPhone UUID>
# Optional: VALIDATION_OUTPUT_DIR=<directory for per-run logs and xcresult bundles>
# Optional: VALIDATION_TEST_SCOPE=loading for all unit tests and three relevant UI flows.
set -Eeuo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "This validation requires macOS with Xcode 16 or newer."
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is missing. Install Xcode and select it with xcode-select."
command -v xcrun >/dev/null 2>&1 || fail "xcrun is missing. Complete the Xcode first-launch setup."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/PelicanSaveEditor.xcodeproj"
SCHEME="PelicanSaveEditor"
[[ -d "$PROJECT_PATH" ]] || fail "The Xcode project is missing: $PROJECT_PATH"

XCODE_INFO="$(xcodebuild -version)" || fail "Cannot read the selected Xcode version. Select the full Xcode app, not Command Line Tools."
XCODE_VERSION="$(printf '%s\n' "$XCODE_INFO" | awk '/^Xcode / { print $2; exit }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]] || fail "Could not identify the selected Xcode version: $XCODE_INFO"
(( XCODE_MAJOR >= 16 )) || fail "Xcode 16 or newer is required; the selected version is $XCODE_VERSION."
PYTHON_BIN="$(xcrun --find python3 2>/dev/null || command -v python3 || true)"
[[ -n "$PYTHON_BIN" ]] || fail "Python 3 is needed to read Simulator's JSON inventory. Install Xcode's command-line tools."

OUTPUT_BASE="${VALIDATION_OUTPUT_DIR:-$PROJECT_ROOT/artifacts/macos-validation}"
RUN_DIR="$OUTPUT_BASE/$(date '+%Y%m%d-%H%M%S')-$$"
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd -- "$RUN_DIR" && pwd)"
trap 'status=$?; printf "Validation failed (exit %s). Logs and any xcresult bundles remain in: %s\n" "$status" "$RUN_DIR" >&2; exit "$status"' ERR

printf '%s\n' "$XCODE_INFO" | tee "$RUN_DIR/xcode-version.txt"
xcrun simctl list devices available --json > "$RUN_DIR/devices.json"
xcrun simctl list runtimes --json > "$RUN_DIR/runtimes.json"

# Select an available iPhone from the newest installed iOS runtime >= 17.0.
# Within that runtime, prefer an already booted device. An explicit UUID must
# still refer to an available iPhone on a compatible installed runtime.
SIMULATOR_SELECTION="$("$PYTHON_BIN" - "$RUN_DIR/devices.json" "$RUN_DIR/runtimes.json" "${SIMULATOR_UDID:-}" "$RUN_DIR/selected-simulator.json" <<'PY'
import json
import re
import sys

devices_path, runtimes_path, requested_id, selected_path = sys.argv[1:]
with open(devices_path, encoding="utf-8") as stream:
    devices = json.load(stream).get("devices", {})
with open(runtimes_path, encoding="utf-8") as stream:
    runtimes = json.load(stream).get("runtimes", [])

versions = {}
for runtime in runtimes:
    identifier = runtime.get("identifier", "")
    if ".iOS-" not in identifier or not runtime.get("isAvailable", False):
        continue
    version = tuple(int(piece) for piece in re.findall(r"\d+", runtime.get("version", "0")))
    if version >= (17, 0):
        versions[identifier] = version

candidates = []
for runtime_id, rows in devices.items():
    if runtime_id not in versions:
        continue
    for device in rows:
        if not device.get("isAvailable", False):
            continue
        is_iphone = ".iPhone-" in device.get("deviceTypeIdentifier", "") or device.get("name", "").startswith("iPhone")
        if not is_iphone or (requested_id and device.get("udid") != requested_id):
            continue
        candidates.append((versions[runtime_id], device.get("state") == "Booted", device.get("name", ""), runtime_id, device))

if not candidates:
    detail = f" for requested UUID {requested_id}" if requested_id else ""
    sys.exit("ERROR: No available iPhone Simulator with iOS 17 or newer" + detail + ". Install an iOS Simulator runtime in Xcode Settings > Components, and create an iPhone in Devices and Simulators.")

version, _, name, runtime_id, device = sorted(candidates, key=lambda item: item[:3], reverse=True)[0]
selected = {"udid": device["udid"], "name": name, "state": device.get("state", "Shutdown"), "runtime": runtime_id, "iOSVersion": ".".join(map(str, version))}
with open(selected_path, "w", encoding="utf-8") as stream:
    json.dump(selected, stream, ensure_ascii=False, indent=2)
print("\t".join((selected["udid"], selected["name"], selected["state"], selected["iOSVersion"])))
PY
)"
IFS=$'\t' read -r SIMULATOR_ID SIMULATOR_NAME SIMULATOR_STATE SIMULATOR_IOS <<< "$SIMULATOR_SELECTION"
[[ -n "$SIMULATOR_ID" ]] || fail "Simulator selection returned no device UUID. Inventory files are in $RUN_DIR."
printf 'Using %s, iOS %s (%s)\nResults: %s\n' "$SIMULATOR_NAME" "$SIMULATOR_IOS" "$SIMULATOR_ID" "$RUN_DIR"

if [[ "$SIMULATOR_STATE" != "Booted" ]]; then
    xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b

BUILD_ARGUMENTS=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration Debug
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID"
    -destination-timeout 120
    -derivedDataPath "$RUN_DIR/DerivedData"
    CODE_SIGNING_ALLOWED=NO
)

printf '\nBuilding the app and its test bundle…\n'
if xcodebuild "${BUILD_ARGUMENTS[@]}" \
    -resultBundlePath "$RUN_DIR/build.xcresult" \
    build-for-testing 2>&1 | tee "$RUN_DIR/build.log"; then
    :
else
    fail "Build failed. Review $RUN_DIR/build.log and $RUN_DIR/build.xcresult. Tests were not run."
fi

printf '\nRunning the shared scheme test suite…\n'
TEST_SELECTION=()
case "${VALIDATION_TEST_SCOPE:-full}" in
    full) ;;
    repair)
        TEST_SELECTION=(
            -only-testing:PelicanSaveEditorUITests/RepairEditorUITests
        )
        ;;
    comprehensive)
        TEST_SELECTION=(
            -only-testing:PelicanSaveEditorTests
            -only-testing:PelicanSaveEditorUITests/ExpandedEditorUITests
        )
        ;;
    loading)
        TEST_SELECTION=(
            -only-testing:PelicanSaveEditorTests
            -only-testing:PelicanSaveEditorUITests/AdaptiveLayoutUITests/testEachDocumentPickerCanOpenCancelAndReopen
            -only-testing:PelicanSaveEditorUITests/TrackerSmokeUITests/testOverviewFiltersAndGroupExpansion
            -only-testing:PelicanSaveEditorUITests/TrackerSmokeUITests/testMapScopedWaterPreviewPendingLocateAndUndo
        )
        ;;
    *) fail "Unknown VALIDATION_TEST_SCOPE; use full, comprehensive, loading or repair." ;;
esac
printf 'Test scope: %s\n' "${VALIDATION_TEST_SCOPE:-full}" | tee "$RUN_DIR/test-scope.txt"
if xcodebuild "${BUILD_ARGUMENTS[@]}" \
    ${TEST_SELECTION[@]+"${TEST_SELECTION[@]}"} \
    -resultBundlePath "$RUN_DIR/tests.xcresult" \
    -parallel-testing-enabled NO \
    test-without-building 2>&1 | tee "$RUN_DIR/tests.log"; then
    :
else
    fail "Tests failed. Review $RUN_DIR/tests.log and $RUN_DIR/tests.xcresult."
fi

printf '\nValidation passed.\nBuild result: %s\nTest result: %s\n' \
    "$RUN_DIR/build.xcresult" "$RUN_DIR/tests.xcresult"
