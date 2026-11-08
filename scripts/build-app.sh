#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A stable certificate identity is required; never silently fall back to ad-hoc signing.
SIGNING_IDENTITY="${CODA_SIGNING_IDENTITY:-22571B293DDEED6B20DB834884A208BFDADDEDD7}"
BUILD_NUMBER="${CODA_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
if [[ "$SIGNING_IDENTITY" == "-" || -z "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' 'Coda requires a certificate signing identity.' >&2
    exit 1
fi
CHANNEL="${CODA_CHANNEL:-development}"
case "$CHANNEL" in
    development) APP_NAME="Coda Dev"; BUNDLE_ID="app.coda.notebook.dev" ;;
    production) APP_NAME="Coda"; BUNDLE_ID="app.coda.notebook" ;;
    *) echo 'CODA_CHANNEL must be development or production.' >&2; exit 1 ;;
esac
ROOT="$PWD"
APP="${CODA_APP_OUTPUT:-$ROOT/build/$APP_NAME.app}"
# Never overwrite an executable while it is running, including development.
if /usr/bin/pgrep -f "^$APP/Contents/MacOS/Coda$" >/dev/null; then
    echo "Quit $APP_NAME normally before building into $APP." >&2; exit 1
fi
swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release --show-bin-path)"
cp "$BIN/Coda" "$APP/Contents/MacOS/Coda"
cp "$BIN/CodaVozTool" "$APP/Contents/MacOS/CodaVozTool"
codesign --force --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/CodaVozTool"
# Include dependency privacy/resource bundles used by SwiftPM's runtime bundle lookup.
for bundle in "$BIN"/*.bundle; do
    if [ -d "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
cp scripts/smart-cleanup/worker.py "$APP/Contents/Resources/smart_cleanup_worker.py"
cp scripts/smart-cleanup/cleanup_rules.py "$APP/Contents/Resources/cleanup_rules.py"
cp scripts/smart-cleanup/punctuation.py "$APP/Contents/Resources/punctuation.py"
cp scripts/smart-cleanup/spoken_numbers.py "$APP/Contents/Resources/spoken_numbers.py"
cp scripts/smart-cleanup/model_cleanup.py "$APP/Contents/Resources/model_cleanup.py"
cp scripts/smart-cleanup/finetune/tuning.py scripts/smart-cleanup/finetune/auto_tune.py scripts/smart-cleanup/finetune/regression.jsonl "$APP/Contents/Resources/"
cp scripts/personal-audio/voz.py "$APP/Contents/Resources/voz.py"
cp scripts/personal-audio/worker.py "$APP/Contents/Resources/personal_audio_worker.py"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp Vendor/Who/LICENSE.md "$APP/Contents/Resources/Who-LICENSE.md"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Coda' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $(cat VERSION)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 15.0' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string Coda records your microphone only when you start a recording.' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSScreenCaptureUsageDescription string Coda captures system audio for meetings only when you start a recording. No screen video is saved.' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CodaProjectDirectory string $ROOT" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CodaChannel string $CHANNEL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CodaSourceRevision string $(git rev-parse HEAD)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CodaSourceDirty bool $(if [[ -n "$(git status --porcelain)" ]]; then echo true; else echo false; fi)" "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$ROOT/build/Coda.iconset" "$CHANNEL"
iconutil -c icns "$ROOT/build/Coda.iconset" -o "$APP/Contents/Resources/Coda.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Coda.icns' "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
