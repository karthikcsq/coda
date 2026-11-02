#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Some Command Line Tools releases omit this directory from SwiftPM's plugin search path.
SWIFT_BIN="$(dirname "$(xcrun --find swift)")"
PLUGIN="$SWIFT_BIN/../lib/swift/host/plugins/testing"
if [ -f "$PLUGIN/libTestingMacros.dylib" ]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN" "$@"
else
    swift test "$@"
fi
