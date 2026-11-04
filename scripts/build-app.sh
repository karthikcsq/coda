#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A stable certificate identity is required; never silently fall back to ad-hoc signing.
SIGNING_IDENTITY="${CODA_SIGNING_IDENTITY:-22571B293DDEED6B20DB834884A208BFDADDEDD7}"
BUILD_NUMBER="${CODA_BUILD_NUMBER:-1}"
if [[ "$SIGNING_IDENTITY" == "-" || -z "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' 'Coda requires a certificate signing identity.' >&2
    exit 1
fi
swift build -c release
ROOT="$PWD"
APP="${CODA_APP_OUTPUT:-$ROOT/build/Coda.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release --show-bin-path)"
cp "$BIN/Coda" "$APP/Contents/MacOS/Coda"
# Include dependency privacy/resource bundles used by SwiftPM's runtime bundle lookup.
for bundle in "$BIN"/*.bundle; do
    if [ -d "$bundle" ]; then cp -R "$bundle" "$APP/Contents/Resources/"; fi
done
cp scripts/smart-cleanup/worker.py "$APP/Contents/Resources/smart_cleanup_worker.py"
cp scripts/smart-cleanup/cleanup_rules.py "$APP/Contents/Resources/cleanup_rules.py"
cp scripts/smart-cleanup/punctuation.py "$APP/Contents/Resources/punctuation.py"
cp scripts/smart-cleanup/spoken_numbers.py "$APP/Contents/Resources/spoken_numbers.py"
cp scripts/smart-cleanup/model_cleanup.py "$APP/Contents/Resources/model_cleanup.py"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp Vendor/Who/LICENSE.md "$APP/Contents/Resources/Who-LICENSE.md"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string app.coda.notebook' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Coda' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Coda' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.4.14' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 15.0' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string Coda records your microphone only when you start a recording.' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSScreenCaptureUsageDescription string Coda captures system audio for meetings only when you start a recording. No screen video is saved.' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CodaProjectDirectory string $ROOT" "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$ROOT/build/Coda.iconset"
iconutil -c icns "$ROOT/build/Coda.iconset" -o "$APP/Contents/Resources/Coda.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Coda.icns' "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
