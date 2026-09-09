#!/usr/bin/env bash
# macOS only. Builds Debug and captures native Tracker screenshots using synthetic data.
# SIMULATOR_UDID selects an installed device as a TYPE/RUNTIME TEMPLATE only.
# No existing device is installed into, booted, erased, or otherwise modified.
# APPPATH (or APP_PATH) may point to an already built Debug iOS Simulator .app.
# Run: bash scripts/capture-tracker-ui.sh
set -Eeuo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "${OSTYPE:-}" == darwin* ]] || fail 'Native UI capture requires macOS and full Xcode 16 or newer.'
command -v xcodebuild >/dev/null 2>&1 || fail 'xcodebuild is missing. Select the full Xcode app.'
command -v xcrun >/dev/null 2>&1 || fail 'xcrun is missing. Complete Xcode first-launch setup.'
PYTHON_BIN="$(xcrun --find python3 2>/dev/null || command -v python3 || true)"
[[ -n "$PYTHON_BIN" ]] || fail 'Python 3 is required to read the Simulator inventory.'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUTPUT_BASE="${TRACKER_UI_OUTPUT_DIR:-$PROJECT_ROOT/validation/tracker-ui}"
RUN_DIR="$OUTPUT_BASE/$(date '+%Y%m%d-%H%M%S')-$$"
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd -- "$RUN_DIR" && pwd)"
CAPTURE_WAIT_SECONDS="${CAPTURE_WAIT_SECONDS:-5}"
[[ "$CAPTURE_WAIT_SECONDS" =~ ^[0-9]+$ ]] || fail 'CAPTURE_WAIT_SECONDS must be an integer from 1 to 30.'
(( CAPTURE_WAIT_SECONDS >= 1 && CAPTURE_WAIT_SECONDS <= 30 )) || fail 'CAPTURE_WAIT_SECONDS must be from 1 to 30.'

CREATED_SIMULATOR_ID=''
BUNDLE_ID=''
cleanup() {
    local status=$?
    trap - EXIT
    # Only the exact UUID returned by this run's `simctl create` is eligible.
    # Keep source, build results, input .app, and screenshots; no filesystem deletion.
    if [[ "$CREATED_SIMULATOR_ID" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
        if [[ -n "$BUNDLE_ID" ]]; then
            xcrun simctl terminate "$CREATED_SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
        fi
        xcrun simctl shutdown "$CREATED_SIMULATOR_ID" >/dev/null 2>&1 || true
        if ! xcrun simctl delete "$CREATED_SIMULATOR_ID" >> "$RUN_DIR/cleanup.log" 2>&1; then
            printf 'WARNING: Could not delete this run\047s temporary simulator: %s\n' "$CREATED_SIMULATOR_ID" >&2
            printf 'Inspect cleanup.log; do not erase or delete other simulators.\n' >&2
            if (( status == 0 )); then status=1; fi
        fi
    fi
    printf 'Capture exit code: %s. Evidence retained in: %s\n' "$status" "$RUN_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcodebuild -version | tee "$RUN_DIR/xcode-version.txt"
XCODE_MAJOR="$(awk '/^Xcode / { split($2, parts, "."); print parts[1]; exit }' "$RUN_DIR/xcode-version.txt")"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]] && (( XCODE_MAJOR >= 16 )) || fail 'Xcode 16 or newer is required.'
xcrun simctl list devices available --json > "$RUN_DIR/devices.json"
xcrun simctl list runtimes --json > "$RUN_DIR/runtimes.json"

# Reuse only an available device's type/runtime, never its user data. Prefer the
# newest iOS >= 17.0 and an iPhone; a supplied UUID must satisfy the same checks.
SELECTION="$("$PYTHON_BIN" - "$RUN_DIR/devices.json" "$RUN_DIR/runtimes.json" "${SIMULATOR_UDID:-${UDID:-}}" "$RUN_DIR/device-template.json" <<'PY'
import json
import re
import sys

devices_path, runtimes_path, requested, output_path = sys.argv[1:]
with open(devices_path, encoding="utf-8") as stream:
    devices = json.load(stream).get("devices", {})
with open(runtimes_path, encoding="utf-8") as stream:
    runtimes = json.load(stream).get("runtimes", [])
versions = {}
for runtime in runtimes:
    identifier = runtime.get("identifier", "")
    version = tuple(map(int, re.findall(r"\d+", runtime.get("version", "0"))))
    if ".iOS-" in identifier and runtime.get("isAvailable", False) and version >= (17, 0):
        versions[identifier] = version
candidates = []
for runtime_id, rows in devices.items():
    if runtime_id not in versions:
        continue
    for row in rows:
        device_type = row.get("deviceTypeIdentifier", "")
        if not row.get("isAvailable", False) or ".iPhone-" not in device_type:
            continue
        if requested and row.get("udid", "").upper() != requested.upper():
            continue
        candidates.append((versions[runtime_id], row.get("name", ""), row.get("udid", ""), runtime_id, device_type))
if not candidates:
    raise SystemExit("No matching available iPhone on iOS >= 17. Install an iOS runtime and create an iPhone in Xcode; SIMULATOR_UDID must be an existing compatible device.")
version, name, template_id, runtime_id, device_type = sorted(candidates, reverse=True)[0]
with open(output_path, "w", encoding="utf-8") as stream:
    json.dump({"templateUDID": template_id, "name": name, "runtime": runtime_id,
               "deviceTypeIdentifier": device_type, "iOSVersion": ".".join(map(str, version)),
               "policy": "Fresh temporary device; template data is not copied or modified."}, stream, indent=2)
print("\t".join((device_type, runtime_id)))
PY
)"
IFS=$'\t' read -r DEVICE_TYPE RUNTIME_ID <<< "$SELECTION"
[[ -n "$DEVICE_TYPE" && -n "$RUNTIME_ID" ]] || fail 'Simulator selection returned no usable device type/runtime.'
CREATED_SIMULATOR_ID="$(xcrun simctl create "Tracker UI QA $(date '+%Y%m%d-%H%M%S')-$$" "$DEVICE_TYPE" "$RUNTIME_ID")"
[[ "$CREATED_SIMULATOR_ID" =~ ^[0-9A-Fa-f-]{36}$ ]] || fail 'simctl create did not return a UUID; inspect the Simulator inventory.'
printf '%s\n' "$CREATED_SIMULATOR_ID" > "$RUN_DIR/temporary-simulator-udid.txt"
xcrun simctl boot "$CREATED_SIMULATOR_ID"
xcrun simctl bootstatus "$CREATED_SIMULATOR_ID" -b

BUILT_APP_PATH="${APPPATH:-${APP_PATH:-}}"
if [[ -z "$BUILT_APP_PATH" ]]; then
    if ! xcodebuild \
        -project "$PROJECT_ROOT/PelicanSaveEditor.xcodeproj" \
        -scheme PelicanSaveEditor -configuration Debug \
        -destination "platform=iOS Simulator,id=$CREATED_SIMULATOR_ID" \
        -destination-timeout 120 \
        -derivedDataPath "$RUN_DIR/DerivedData" \
        -resultBundlePath "$RUN_DIR/build.xcresult" \
        CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$RUN_DIR/build.log"; then
        fail 'Debug build failed; no screenshot or visual pass is claimed.'
    fi
    BUILT_APP_PATH="$RUN_DIR/DerivedData/Build/Products/Debug-iphonesimulator/SheaflightAmberVault.app"
fi
[[ -d "$BUILT_APP_PATH" && -f "$BUILT_APP_PATH/Info.plist" ]] || fail "No Simulator .app at: $BUILT_APP_PATH"
BUILT_APP_PATH="$(cd -- "$BUILT_APP_PATH" && pwd)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP_PATH/Info.plist")"
APP_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$BUILT_APP_PATH/Info.plist")"
APP_PLATFORM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$BUILT_APP_PATH/Info.plist")"
[[ "$APP_PLATFORM" == 'iPhoneSimulator' ]] || fail 'The supplied app is not an iOS Simulator build. A device IPA cannot run here.'
[[ -n "$BUNDLE_ID" && -f "$BUILT_APP_PATH/$APP_EXECUTABLE" ]] || fail 'App bundle metadata is incomplete.'
# Release omits these Debug-only hooks. Refuse it instead of capturing unrelated UI.
# Xcode 16 may place Debug app code in a companion dylib, leaving the main
# executable as a launcher. Include that exact companion when it is present.
APP_BINARY_FILES=("$BUILT_APP_PATH/$APP_EXECUTABLE")
if [[ -f "$BUILT_APP_PATH/$APP_EXECUTABLE.debug.dylib" ]]; then
    APP_BINARY_FILES+=("$BUILT_APP_PATH/$APP_EXECUTABLE.debug.dylib")
fi
strings "${APP_BINARY_FILES[@]}" > "$RUN_DIR/app-strings.txt"
grep -F -q -- '--ui-demo' "$RUN_DIR/app-strings.txt" || fail 'App lacks --ui-demo; supply a Debug build from this source.'
grep -F -q -- '--ui-tab' "$RUN_DIR/app-strings.txt" || fail 'App lacks --ui-tab; supply a Debug build from this source.'
grep -F -q -- '--ui-tracker-section' "$RUN_DIR/app-strings.txt" || fail 'App lacks --ui-tracker-section; rebuild the current source in Debug.'
printf '%s\n' "$BUILT_APP_PATH" > "$RUN_DIR/app-path.txt"
printf '%s\n' "$BUNDLE_ID" > "$RUN_DIR/bundle-id.txt"
shasum -a 256 "${APP_BINARY_FILES[@]}" > "$RUN_DIR/app-executable.sha256"
xcrun simctl install "$CREATED_SIMULATOR_ID" "$BUILT_APP_PATH"
xcrun simctl status_bar "$CREATED_SIMULATOR_ID" override --time '9:41' --batteryState charged --batteryLevel 100

capture() {
    local filename=$1 appearance=$2 size=$3 scenario=$4
    local detail_section=${5:-}
    local launch_arguments=(--ui-tab tracker -appearanceMode system -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN)
    case "$scenario" in
        demo) launch_arguments+=(--ui-demo) ;;
        edits) launch_arguments+=(--ui-demo --ui-demo-edits) ;;
        empty) ;; # No demo flag: EditorStore starts without a session, never imports a save.
        *) fail "Unsupported capture scenario: $scenario" ;;
    esac
    if [[ -n "$detail_section" ]]; then
        [[ "$scenario" != 'empty' ]] || fail 'Tracker detail requires a demo session.'
        case "$detail_section" in
            character|appearance|farmhouse|inventory|progress|relationships|skills|wallet|animals|recipes|review)
                launch_arguments+=(--ui-tracker-section "$detail_section") ;;
            *) fail "Unsupported Tracker section: $detail_section" ;;
        esac
    fi
    xcrun simctl terminate "$CREATED_SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl ui "$CREATED_SIMULATOR_ID" appearance "$appearance"
    xcrun simctl ui "$CREATED_SIMULATOR_ID" content_size "$size"
    printf '%s\t%s\t%s\t%s\t%s\n' "$filename" "$appearance" "$size" "$scenario" "${detail_section:-overview}" >> "$RUN_DIR/capture-manifest.tsv"
    xcrun simctl launch "$CREATED_SIMULATOR_ID" "$BUNDLE_ID" "${launch_arguments[@]}" >> "$RUN_DIR/launch.log" 2>&1
    # This is a settling delay, NOT a loaded-state assertion. Review each image.
    sleep "$CAPTURE_WAIT_SECONDS"
    xcrun simctl io "$CREATED_SIMULATOR_ID" screenshot "$RUN_DIR/$filename"
    [[ -s "$RUN_DIR/$filename" ]] || fail "No screenshot was written: $filename"
}

printf 'file\tappearance\tcontent_size\tscenario\ttracker_section\n' > "$RUN_DIR/capture-manifest.tsv"
capture '01-tracker-light.png' light large demo
capture '02-tracker-dark.png' dark large demo
capture '03-tracker-large-type-light.png' light accessibility-extra-extra-extra-large demo
capture '04-tracker-large-type-dark.png' dark accessibility-extra-extra-extra-large demo
capture '05-tracker-draft-light.png' light large edits
capture '06-tracker-empty-light.png' light large empty
capture '07-tracker-empty-dark.png' dark large empty
capture '08-tracker-empty-large-type.png' light accessibility-extra-extra-extra-large empty
capture '09-detail-progress-light.png' light large demo progress
capture '10-detail-recipes-light.png' light large demo recipes
capture '11-detail-wallet-light.png' light large demo wallet
capture '12-detail-review-draft-light.png' light large edits review
capture '13-detail-progress-dark.png' dark large demo progress
capture '14-detail-relationships-dark.png' dark large demo relationships
capture '15-detail-progress-large-type.png' light accessibility-extra-extra-extra-large demo progress
capture '16-detail-recipes-large-type.png' light accessibility-extra-extra-extra-large demo recipes

printf '%s\n' \
    'CAPTURED — NOT VISUALLY REVIEWED' \
    'Screenshots are real Simulator output; their existence does not establish correct UI or data.' \
    'Review every PNG for loading overlays, launch failures, clipping, contrast, and read-only behavior.' \
    'Detail screenshots use the real Debug --ui-tracker-section hook; tapping, scrolling, and returning still require manual review.' \
    'No game save was imported or written. DebugDemoSave supplies synthetic in-memory data.' \
    'No XCTest suite was run by this capture script. Run scripts/validate-on-macos.sh separately.' \
    'See validation/TRACKER_UI_CHECKLIST.md for comparison and interaction acceptance criteria.' \
    > "$RUN_DIR/REVIEW_STATUS.txt"
printf 'Native captures created. Manual review remains required: %s\n' "$RUN_DIR"
