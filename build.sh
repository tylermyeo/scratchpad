#!/bin/bash
set -e

APP="Scratchpad.app"
BINARY="$APP/Contents/MacOS/Scratchpad"

echo "Building $APP..."

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

swiftc Sources/*.swift \
    -framework Cocoa \
    -target "$(uname -m)-apple-macosx13.0" \
    -O \
    -o "$BINARY"

cp Info.plist "$APP/Contents/Info.plist"

echo "✓ Built $APP"
echo ""
echo "To run: open $APP"
echo "Or drag Scratchpad.app to /Applications"
