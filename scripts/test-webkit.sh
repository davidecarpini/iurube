#!/bin/bash
# Compiles the production BrowserSession and runs integration checks in macOS WebKit.
# This does NOT run an iOS simulator. A live YouTube check also needs the Internet.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/WebKitChecks.app/Contents/MacOS work/WebKitChecks.app/Contents/Resources
cp iurub/Resources/YouTubeBridge.js iurub/Resources/YouTubeFixture.html work/WebKitChecks.app/Contents/Resources/
cat > work/WebKitChecks.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>it.davidecarpini.iurub.webchecks</string><key>CFBundleName</key><string>iurub WebKit checks</string><key>CFBundleExecutable</key><string>WebKitChecks</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
sdk="${MACOS_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
swiftc -swift-version 5 -D DEBUG -parse-as-library -sdk "$sdk" -target "$(uname -m)-apple-macosx14.0" \
  iurub/Models/*.swift iurub/Web/BrowserSession.swift scripts/tests/WebKitChecks.swift \
  -o work/WebKitChecks.app/Contents/MacOS/WebKitChecks
work/WebKitChecks.app/Contents/MacOS/WebKitChecks "$PWD/work/youtube-webkit.png"
