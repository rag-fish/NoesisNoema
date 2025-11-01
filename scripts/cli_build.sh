#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="${1:-NoesisNoema}"
CONFIG="${2:-Debug}"

# Prefer a deterministic destination for macOS arm64
DEST="platform=macOS,arch=arm64"

# Build without xcpretty if not installed
if command -v xcpretty >/dev/null 2>&1; then
  xcodebuild -project "NoesisNoema.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" -destination "$DEST" clean build | xcpretty
else
  echo "xcpretty not found; showing raw xcodebuild output (install with: brew install xcpretty)" >&2
  xcodebuild -project "NoesisNoema.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" -destination "$DEST" clean build
fi
