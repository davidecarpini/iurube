#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Some Command Line Tools releases keep TestingMacros in a subdirectory that
# SwiftPM does not search automatically. Xcode installations do not need this.
plugin="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
  swift test --disable-xctest --enable-swift-testing -Xswiftc -load-plugin-library -Xswiftc "$plugin"
else
  swift test --disable-xctest --enable-swift-testing
fi
