#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="${LAYOUT_OUTPUT_DIR:-artifacts/ipad-layout}"
mkdir -p "$output_dir"
xcodebuild -version | tee "$output_dir/xcode.log"
xcrun simctl list devices available --json > "$output_dir/devices.json"
python3 - "${LAYOUT_DEVICE:-mini}" "$output_dir" <<'PY'
import json, re, sys
from pathlib import Path
root = Path(sys.argv[2])
family = sys.argv[1]
candidates = []
for runtime, devices in json.loads((root / 'devices.json').read_text())['devices'].items():
    if '.iOS-' not in runtime: continue
    version = tuple(map(int, re.findall(r'\d+', runtime.split('.iOS-')[1])))
    if version < (17,): continue
    for device in devices:
        name = device['name']
        matches = ('iPad mini' in name if family == 'mini' else
                   'iPad' in name and ('13-inch' in name or '12.9-inch' in name) if family == 'large' else
                   name.startswith('iPhone'))
        if device.get('isAvailable') and matches:
            candidates.append((version, 'SE' in name, name, runtime, device))
if not candidates: raise SystemExit('No compatible installed Simulator for ' + family)
version, _, name, runtime, device = max(candidates, key=lambda row: row[:3])
selection = {'name': name, 'udid': device['udid'], 'runtime': runtime, 'family': family}
(root / 'selected-simulator.json').write_text(json.dumps(selection, indent=2))
print(selection)
PY
simulator_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["udid"])' "$output_dir/selected-simulator.json")"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
args=(
    -project PelicanSaveEditor.xcodeproj -scheme PelicanSaveEditor -configuration Debug
    -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 120
    -derivedDataPath "${LAYOUT_DERIVED_DIR:-artifacts/ipad-layout/DerivedData}" -parallel-testing-enabled NO
    -resultBundlePath "$output_dir/tests.xcresult" CODE_SIGNING_ALLOWED=NO
)
if [[ "${LAYOUT_SCOPE:-layout}" == valley-preview ]]; then
    args+=(-only-testing:PelicanSaveEditorUITests/ValleyThemeUITests)
elif [[ "${LAYOUT_SCOPE:-layout}" == valley ]]; then
    args+=(-skip-testing:PelicanSaveEditorUITests/ValleyThemeUITests)
    if [[ "${LAYOUT_DEVICE:-mini}" != iphone ]]; then
        args+=(-only-testing:PelicanSaveEditorUITests/PelicanBrandUITests)
        args+=(-only-testing:PelicanSaveEditorUITests/AdaptiveLayoutUITests)
        args+=(-only-testing:PelicanSaveEditorUITests/PersistenceUITests)
    fi
elif [[ "${LAYOUT_SCOPE:-layout}" == brand ]]; then
    args+=(-only-testing:PelicanSaveEditorUITests/PelicanBrandUITests)
    args+=(-only-testing:PelicanSaveEditorUITests/AdaptiveLayoutUITests/testImportOptionsSurviveRotation)
    args+=(-only-testing:PelicanSaveEditorUITests/AdaptiveLayoutUITests/testEachDocumentPickerCanOpenCancelAndReopen)
    if [[ "${LAYOUT_DEVICE:-mini}" == iphone ]]; then
        args+=(-only-testing:PelicanSaveEditorTests)
    fi
elif [[ "${LAYOUT_SCOPE:-layout}" == expanded ]]; then
    args+=(-only-testing:PelicanSaveEditorUITests/ExpandedEditorUITests)
elif [[ "${LAYOUT_SCOPE:-layout}" == repair ]]; then
    args+=(-only-testing:PelicanSaveEditorUITests/RepairEditorUITests)
    args+=(-only-testing:PelicanSaveEditorUITests/ExpandedEditorUITests)
elif [[ "${LAYOUT_DEVICE:-mini}" != iphone ]]; then
    args+=(-only-testing:PelicanSaveEditorTests -only-testing:PelicanSaveEditorUITests/AdaptiveLayoutUITests)
    args+=(-only-testing:PelicanSaveEditorUITests/TrackerSmokeUITests/testAllElevenModulesOpenAndClose)
    args+=(-only-testing:PelicanSaveEditorUITests/TrackerSmokeUITests/testOverviewFiltersAndGroupExpansion)
    args+=(-only-testing:PelicanSaveEditorUITests/TrackerSmokeUITests/testDetailSwitchingRecipeFiltersAndSearchEmptyState)
fi
xcodebuild "${args[@]}" "${LAYOUT_BUILD_ACTION:-test}" 2>&1 | tee "$output_dir/tests.log"
