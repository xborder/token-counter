#!/bin/bash
# Build TokenCounter and launch it as a proper .app bundle.
# Usage: ./run.sh [--release]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    CONFIG="release"
fi

echo "▶ Building TokenCounter ($CONFIG)..."
swift build -c "$CONFIG"

# Locate the built binary (arm64 or x86_64)
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BINARY="$SCRIPT_DIR/.build/arm64-apple-macosx/$CONFIG/TokenCounter"
else
    BINARY="$SCRIPT_DIR/.build/x86_64-apple-macosx/$CONFIG/TokenCounter"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "✗ Binary not found at $BINARY"
    exit 1
fi

APP_DIR="/tmp/TokenCounter.app"
CONTENTS="$APP_DIR/Contents"

# Kill any existing instance before replacing the bundle
echo "▶ Stopping any running instance..."
pkill -x "TokenCounter" 2>/dev/null && sleep 0.5 || true

# Build the .app bundle structure
echo "▶ Creating app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY"                              "$CONTENTS/MacOS/TokenCounter"
cp "$SCRIPT_DIR/Info.plist"               "$CONTENTS/Info.plist"

if [[ -f "$SCRIPT_DIR/Sources/Resources/pricing.json" ]]; then
    cp "$SCRIPT_DIR/Sources/Resources/pricing.json" "$CONTENTS/Resources/pricing.json"
fi

echo "▶ Launching TokenCounter.app..."
open "$APP_DIR"

echo "✓ Done — look for the  icon in your menu bar."
