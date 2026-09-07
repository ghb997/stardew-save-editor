#!/usr/bin/env bash
# Build only the app target for a physical arm64 iOS device, without signing.
# No signing identities, provisioning credentials, dependencies, or tests are used.
# Run: bash scripts/build-unsigned-ipa.sh
# Optional output base: IPA_OUTPUT_DIR=/absolute/path
set -Eeuo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == "Darwin" ]] || fail "macOS and Xcode 16 or newer are required."
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is unavailable. Select a full Xcode installation."
command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable. Complete the Xcode first-launch setup."
PYTHON_BIN="$(command -v python3 || true)"
[[ -n "$PYTHON_BIN" ]] || fail "Python 3 is required for plist and IPA structure validation."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/PelicanSaveEditor.xcodeproj"
[[ -d "$PROJECT_PATH" ]] || fail "Missing project: $PROJECT_PATH"
OUTPUT_BASE="${IPA_OUTPUT_DIR:-$PROJECT_ROOT/artifacts/unsigned-ipa}"
RUN_DIR="$OUTPUT_BASE/run-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd -- "$RUN_DIR" && pwd)"
INFO_PATH="$RUN_DIR/build-info.json"
BUILD_STAGE="toolchain"

"$PYTHON_BIN" - "$INFO_PATH" <<'PY'
import datetime
import json
import os
import sys
info = {
    'schemaVersion': 1,
    'status': 'started',
    'artifactKind': 'unsigned-ios-ipa',
    'codeSigningAllowed': False,
    'requiresSigningBeforeInstallation': True,
    'configuration': 'Release',
    'target': 'PelicanSaveEditor',
    'testsRun': False,
    'sourceCommit': os.environ.get('GITHUB_SHA'),
    'sourceRef': os.environ.get('GITHUB_REF'),
    'githubRunId': os.environ.get('GITHUB_RUN_ID'),
    'startedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
with open(sys.argv[1], 'w', encoding='utf-8') as stream:
    json.dump(info, stream, ensure_ascii=False, indent=2)
PY

finish() {
    status=$?
    if (( status != 0 )); then
        "$PYTHON_BIN" - "$INFO_PATH" "$BUILD_STAGE" "$status" <<'PY'
import json
import sys
path, stage, status = sys.argv[1:]
try:
    with open(path, encoding='utf-8') as stream:
        info = json.load(stream)
    info.update(status='failed', failedStage=stage, exitCode=int(status))
    with open(path, 'w', encoding='utf-8') as stream:
        json.dump(info, stream, ensure_ascii=False, indent=2)
except (OSError, ValueError) as error:
    print(f'Could not update failure metadata: {error}', file=sys.stderr)
PY
        printf 'Build failed during %s. Logs and metadata remain in: %s\n' "$BUILD_STAGE" "$RUN_DIR" >&2
    fi
}
trap finish EXIT

XCODE_INFO="$(xcodebuild -version)"
printf '%s\n' "$XCODE_INFO" | tee "$RUN_DIR/xcode-version.txt"
XCODE_VERSION="$(printf '%s\n' "$XCODE_INFO" | awk '/^Xcode / {print $2; exit}')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]] || fail "Could not identify Xcode version."
(( XCODE_MAJOR >= 16 )) || fail "Xcode 16 or newer is required; found $XCODE_VERSION."
if [[ -n "${EXPECTED_XCODE_VERSION:-}" && "$XCODE_VERSION" != "$EXPECTED_XCODE_VERSION" ]]; then
    fail "The active Xcode version changed after selection: expected $EXPECTED_XCODE_VERSION, found $XCODE_VERSION."
fi
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
printf 'Device SDK: %s\nSigning: disabled\n' "$SDK_VERSION" | tee "$RUN_DIR/build-settings-summary.txt"

# Work products stay outside the uploaded artifact folder. A fresh directory
# prevents stale simulator apps or signed products from entering this package.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sheaflight-unsigned-ipa.XXXXXX")"
PRODUCTS_DIR="$WORK_DIR/products"
mkdir -p "$PRODUCTS_DIR"
BUILD_STAGE="build"
printf 'Building Release iphoneos arm64 app target…\n'
if xcodebuild \
    -project "$PROJECT_PATH" \
    -target PelicanSaveEditor \
    -configuration Release \
    -sdk iphoneos \
    -arch arm64 \
    -resultBundlePath "$RUN_DIR/build.xcresult" \
    "SYMROOT=$WORK_DIR/sym" \
    "OBJROOT=$WORK_DIR/obj" \
    "CONFIGURATION_BUILD_DIR=$PRODUCTS_DIR" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
    build 2>&1 | tee "$RUN_DIR/build.log"; then
    :
else
    fail "xcodebuild failed; review build.log and build.xcresult. No IPA was declared successful."
fi

BUILD_STAGE="app-validation"
APP_PATH="$PRODUCTS_DIR/SheaflightAmberVault.app"
[[ -d "$APP_PATH" ]] || fail "Expected app product is missing: $APP_PATH"
/usr/bin/plutil -lint "$APP_PATH/Info.plist" | tee "$RUN_DIR/plist-validation.txt"
"$PYTHON_BIN" - "$APP_PATH" "$INFO_PATH" "$XCODE_VERSION" "$SDK_VERSION" <<'PY'
import json
import os
import pathlib
import plistlib
import re
import sys
app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as stream:
    plist = plistlib.load(stream)
for key in ('CFBundleExecutable', 'CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion'):
    value = plist.get(key)
    if not isinstance(value, str) or not value or '$(' in value:
        sys.exit(f'ERROR: Missing or unresolved app plist field: {key}')
name = plist['CFBundleExecutable']
if pathlib.PurePosixPath(name).name != name or name in ('.', '..') or '\\' in name:
    sys.exit('ERROR: CFBundleExecutable must be a plain filename.')
executable = app / name
if not executable.is_file() or not os.access(executable, os.X_OK):
    sys.exit('ERROR: The declared bundle executable is missing or not executable.')
if plist.get('CFBundlePackageType') != 'APPL' or 'iPhoneOS' not in plist.get('CFBundleSupportedPlatforms', []):
    sys.exit('ERROR: The product is not a physical-device iOS application.')
if (app / 'embedded.mobileprovision').exists():
    sys.exit('ERROR: Unexpected provisioning profile in unsigned app product.')
if not (app / 'Assets.car').is_file():
    sys.exit('ERROR: Compiled game image assets are missing from the app bundle.')
safe = lambda value: re.sub(r'[^A-Za-z0-9._-]', '_', value)
with open(sys.argv[2], encoding='utf-8') as stream:
    info = json.load(stream)
info.update(
    status='built', xcodeVersion=sys.argv[3], sdkVersion=sys.argv[4],
    appName=app.name, bundleIdentifier=plist['CFBundleIdentifier'], executable=name,
    version=plist['CFBundleShortVersionString'], buildNumber=plist['CFBundleVersion'],
    minimumOSVersion=plist.get('MinimumOSVersion'),
    ipaFile=f"SheaflightAmberVault-v{safe(plist['CFBundleShortVersionString'])}-build{safe(plist['CFBundleVersion'])}-unsigned.ipa",
)
with open(sys.argv[2], 'w', encoding='utf-8') as stream:
    json.dump(info, stream, ensure_ascii=False, indent=2)
PY

EXECUTABLE_NAME="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["executable"])' "$INFO_PATH")"
IPA_BASENAME="$("$PYTHON_BIN" -c 'import json,sys; print(json.load(open(sys.argv[1]))["ipaFile"])' "$INFO_PATH")"
EXECUTABLE_PATH="$APP_PATH/$EXECUTABLE_NAME"
ARCHITECTURES="$(xcrun lipo -archs "$EXECUTABLE_PATH")"
printf '%s\n' "$ARCHITECTURES" | tee "$RUN_DIR/architectures.txt"
[[ "$ARCHITECTURES" == "arm64" ]] || fail "Expected only arm64; found: $ARCHITECTURES"
/usr/bin/file "$EXECUTABLE_PATH" | tee "$RUN_DIR/executable-format.txt"
xcrun vtool -show-build "$EXECUTABLE_PATH" > "$RUN_DIR/macho-platform.txt"
"$PYTHON_BIN" - "$EXECUTABLE_PATH" "$RUN_DIR/macho-platform.txt" <<'PY'
import pathlib
import re
import sys
with open(sys.argv[1], 'rb') as stream:
    if stream.read(4) != b'\xcf\xfa\xed\xfe':
        sys.exit('ERROR: Executable is not a thin 64-bit little-endian Mach-O file.')
platform = pathlib.Path(sys.argv[2]).read_text(encoding='utf-8')
if not re.search(r'\bplatform\s+IOS\b', platform) or 'IOSSIMULATOR' in platform:
    sys.exit('ERROR: Mach-O platform is not a physical iOS device.')
PY
/usr/bin/codesign -dv --verbose=4 "$APP_PATH" > "$RUN_DIR/code-signature.txt" 2>&1 || true

BUILD_STAGE="packaging"
PACKAGE_DIR="$WORK_DIR/package"
mkdir -p "$PACKAGE_DIR/Payload"
/usr/bin/ditto "$APP_PATH" "$PACKAGE_DIR/Payload/$(basename "$APP_PATH")"
IPA_PATH="$RUN_DIR/$IPA_BASENAME"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$PACKAGE_DIR/Payload" "$IPA_PATH"

BUILD_STAGE="ipa-validation"
"$PYTHON_BIN" - "$IPA_PATH" "$INFO_PATH" "$EXECUTABLE_PATH" <<'PY'
import datetime
import hashlib
import json
import pathlib
import plistlib
import stat
import sys
import zipfile

ipa, info_path, executable_path = map(pathlib.Path, sys.argv[1:])
with info_path.open(encoding='utf-8') as stream:
    info = json.load(stream)
app_prefix = 'Payload/' + info['appName'] + '/'
with zipfile.ZipFile(ipa) as archive:
    if archive.testzip() is not None:
        sys.exit('ERROR: IPA ZIP integrity check failed.')
    entries = archive.infolist()
    for entry in entries:
        path = pathlib.PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
            sys.exit('ERROR: Unsafe ZIP entry path.')
        if entry.filename != 'Payload/' and not entry.filename.startswith(app_prefix):
            sys.exit('ERROR: IPA must contain exactly one app inside Payload/.')
    plist_path = app_prefix + 'Info.plist'
    executable_entry = archive.getinfo(app_prefix + info['executable'])
    packaged_plist = plistlib.loads(archive.read(plist_path))
    if packaged_plist.get('CFBundleIdentifier') != info['bundleIdentifier']:
        sys.exit('ERROR: Packaged Info.plist does not match the built app.')
    if not (executable_entry.external_attr >> 16) & stat.S_IXUSR:
        sys.exit('ERROR: IPA did not preserve the executable permission.')
    archive.getinfo(app_prefix + 'Assets.car')
    with archive.open(executable_entry) as packaged, executable_path.open('rb') as original:
        def digest(stream):
            result = hashlib.sha256()
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                result.update(block)
            return result.hexdigest()
        if digest(packaged) != digest(original):
            sys.exit('ERROR: IPA executable differs from the validated app executable.')

with ipa.open('rb') as stream:
    sha = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        sha.update(block)
checksum = sha.hexdigest()
(ipa.parent / (ipa.name + '.sha256')).write_text(f'{checksum}  {ipa.name}\n', encoding='utf-8')
info.update(status='succeeded', architectures=['arm64'], platform='iOS',
            sha256=checksum, ipaBytes=ipa.stat().st_size,
            completedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat())
info_path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'IPA structure, executable, device platform, and SHA-256 validated: {ipa.name}')
PY

BUILD_STAGE="complete"
printf '\nUnsigned IPA: %s\nChecksum: %s.sha256\nBuild information: %s\n' "$IPA_PATH" "$IPA_PATH" "$INFO_PATH"
printf 'This IPA requires your own signing before installation. No simulator tests or public release were performed.\n'
