#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FRAMEWORKS_DIR="$ROOT/NoesisNoema/Frameworks"

# Remove legacy top-level xcframeworks so only Frameworks/xcframeworks/* remain
for name in llama_macos.xcframework llama_ios.xcframework; do
  if [ -d "$FRAMEWORKS_DIR/$name" ]; then
    if [ -d "$FRAMEWORKS_DIR/xcframeworks/$name" ]; then
      echo "Removing legacy $FRAMEWORKS_DIR/$name (duplicate of xcframeworks/$name)"
      rm -rf "$FRAMEWORKS_DIR/$name"
    else
      echo "Note: $FRAMEWORKS_DIR/xcframeworks/$name missing; leaving $FRAMEWORKS_DIR/$name intact"
    fi
  fi
done

echo "Done. If Xcode still shows both paths in project.pbxproj, remove any references to Frameworks/llama_*.xcframework there and keep only Frameworks/xcframeworks/*."
