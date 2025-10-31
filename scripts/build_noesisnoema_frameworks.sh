#!/usr/bin/env bash
set -euo pipefail

# build_noesisnoema_frameworks.sh
# Purpose:
# - Normalize llama.* xcframework outputs into NoesisNoema/Frameworks/xcframeworks/
# - Remove legacy .framework bundles under NoesisNoema/Frameworks/
# - Ensure each slice has a Modules/module.modulemap exposing module "llama"
# - Keep script idempotent
#
# Usage:
#   ./scripts/build_noesisnoema_frameworks.sh
#   LLAMA_MACOS_XCFRAMEWORK=/path/to/llama_macos.xcframework \
#   LLAMA_IOS_XCFRAMEWORK=/path/to/llama_ios.xcframework \
#   ./scripts/build_noesisnoema_frameworks.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST_DIR="$REPO_ROOT/NoesisNoema/Frameworks/xcframeworks"
SRC_DIR_LEGACY="$REPO_ROOT/NoesisNoema/Frameworks"

mkdir -p "$DST_DIR"

echo "==> Destination: $DST_DIR"

declare -A WANT
WANT[llama_macos.xcframework]="${LLAMA_MACOS_XCFRAMEWORK:-}"
WANT[llama_ios.xcframework]="${LLAMA_IOS_XCFRAMEWORK:-}"

# Resolve sources for each expected xcframework
for name in "${!WANT[@]}"; do
  src="${WANT[$name]}"
  if [[ -z "$src" ]]; then
    # Fallback to legacy location if present
    if [[ -d "$SRC_DIR_LEGACY/$name" ]]; then
      src="$SRC_DIR_LEGACY/$name"
    fi
  fi
  if [[ -z "$src" ]]; then
    echo "[WARN] Source not found for $name (env var or legacy path). Skipping."
    continue
  fi
  if [[ ! -d "$src" ]]; then
    echo "[WARN] Source path is not a directory: $src (skipping)"
    continue
  fi
  echo "==> Installing $name from: $src"
  rsync -a --delete "$src/" "$DST_DIR/$name/"
  echo "    -> Installed to $DST_DIR/$name"

done

# Optional: remove legacy xcframeworks at root to prevent Xcode path confusion
for name in "llama_macos.xcframework" "llama_ios.xcframework"; do
  if [[ -d "$SRC_DIR_LEGACY/$name" && "$SRC_DIR_LEGACY/$name" != "$DST_DIR/$name" ]]; then
    echo "==> Removing legacy duplicate: $SRC_DIR_LEGACY/$name"
    rm -rf "$SRC_DIR_LEGACY/$name"
  fi
 done

# Optional: remove legacy dynamic framework bundle to avoid accidental linking
LEGACY_FW_DIR="$SRC_DIR_LEGACY/llama.framework"
if [[ -d "$LEGACY_FW_DIR" ]]; then
  echo "==> Removing legacy dynamic framework: $LEGACY_FW_DIR"
  rm -rf "$LEGACY_FW_DIR"
fi

# Inject module.modulemap for 'llama' framework slices if missing
inject_modulemap() {
  local fw_dir="$1" # path to .../llama.framework
  local modules_dir="$fw_dir/Modules"
  local headers_dir="$fw_dir/Headers"
  if [[ ! -d "$headers_dir" ]]; then
    return
  fi
  mkdir -p "$modules_dir"
  local mm="$modules_dir/module.modulemap"
  if [[ -f "$mm" ]]; then
    return
  fi
  echo "==> Injecting module.modulemap into: $fw_dir"
  cat >"$mm" <<'EOF'
module llama [system] {
  umbrella header "llama.h"
  export *
  module * { export * }
}
EOF
}

# Walk through installed xcframeworks and handle slices
for xc in "$DST_DIR"/*.xcframework; do
  [[ -d "$xc" ]] || continue
  # Iterate known slice dirs
  while IFS= read -r -d '' fw; do
    # fw is path to llama.framework inside a slice
    inject_modulemap "$fw"
  done < <(find "$xc" -maxdepth 3 -type d -name "llama.framework" -print0)

done

# Summary
echo "==> Contents of $DST_DIR:"
ls -1 "$DST_DIR" || true

# Report slices/architectures
report_archs() {
  local xc="$1"
  echo "-- $(basename "$xc")"
  while IFS= read -r -d '' bin; do
    local slice_dir
    slice_dir="$(dirname "$bin")/.." # .../llama.framework/Versions/A/llama -> .../llama.framework/Versions
    local ident
    ident="$(echo "$bin" | sed -E 's#^.*/(ios|ios-arm64|ios-arm64_x86_64-simulator|ios-arm64-simulator|macos|macos-arm64|macos-arm64_x86_64)/.*$#\1#')"
    echo -n "   [$ident] archs: "
    lipo -archs "$bin" 2>/dev/null || echo "unknown"
  done < <(find "$xc" -type f -path "*/llama.framework/Versions/*/llama" -print0)
}

for xc in "$DST_DIR"/*.xcframework; do
  [[ -d "$xc" ]] || continue
  report_archs "$xc"
 done

echo "==> Done."
