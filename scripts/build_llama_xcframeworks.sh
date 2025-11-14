#!/usr/bin/env bash
#
# build_llama_xcframeworks.sh
# Purpose: Build separate llama_macos.xcframework and llama_ios.xcframework
#          for NoesisNoema project
#
# Usage:
#   ./scripts/build_llama_xcframeworks.sh
#
# This script:
# 1. Builds llama.cpp using official build-xcframework.sh
# 2. Splits the universal xcframework into platform-specific ones
# 3. Installs them to NoesisNoema/Frameworks/xcframeworks/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLAMA_DIR="$REPO_ROOT/.build/llama.cpp"
DST_DIR="$REPO_ROOT/NoesisNoema/Frameworks/xcframeworks"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building llama.cpp xcframeworks for NoesisNoema"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Repo root: $REPO_ROOT"
echo "llama.cpp: $LLAMA_DIR"
echo "Destination: $DST_DIR"
echo ""

# Check if llama.cpp exists
if [[ ! -d "$LLAMA_DIR" ]]; then
    echo "❌ ERROR: llama.cpp not found at $LLAMA_DIR"
    echo ""
    echo "Please clone llama.cpp first:"
    echo "  mkdir -p .build"
    echo "  cd .build"
    echo "  git clone https://github.com/ggerganov/llama.cpp.git"
    exit 1
fi

# Check for required tools
command -v cmake >/dev/null 2>&1 || { echo "❌ ERROR: cmake required. Install: brew install cmake"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "❌ ERROR: xcodebuild required. Install Xcode Command Line Tools"; exit 1; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 1: Building universal xcframework"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$LLAMA_DIR"

# Run official llama.cpp build script
if [[ ! -x "./build-xcframework.sh" ]]; then
    echo "❌ ERROR: build-xcframework.sh not found or not executable"
    exit 1
fi

echo "Running llama.cpp build-xcframework.sh..."
echo ""
./build-xcframework.sh

UNIVERSAL_XCF="$LLAMA_DIR/build-apple/llama.xcframework"

if [[ ! -d "$UNIVERSAL_XCF" ]]; then
    echo "❌ ERROR: Universal xcframework not created at $UNIVERSAL_XCF"
    exit 1
fi

echo ""
echo "✅ Universal xcframework built successfully"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 2: Extracting platform-specific xcframeworks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create destination directory
mkdir -p "$DST_DIR"

# Extract macOS xcframework (arm64 + x86_64)
echo "Creating llama_macos.xcframework..."
xcodebuild -create-xcframework \
    -framework "$UNIVERSAL_XCF/macos-arm64_x86_64/llama.framework" \
    -output "$DST_DIR/llama_macos.xcframework" \
    2>&1 | grep -v "note:" || true

echo "✅ llama_macos.xcframework created"
echo ""

# Extract iOS xcframework (arm64 device + arm64/x86_64 simulator)
echo "Creating llama_ios.xcframework..."

# Check which iOS slices are available
IOS_DEVICE_PATH=""
IOS_SIM_PATH=""

if [[ -d "$UNIVERSAL_XCF/ios-arm64/llama.framework" ]]; then
    IOS_DEVICE_PATH="$UNIVERSAL_XCF/ios-arm64/llama.framework"
fi

if [[ -d "$UNIVERSAL_XCF/ios-arm64_x86_64-simulator/llama.framework" ]]; then
    IOS_SIM_PATH="$UNIVERSAL_XCF/ios-arm64_x86_64-simulator/llama.framework"
elif [[ -d "$UNIVERSAL_XCF/ios-arm64-simulator/llama.framework" ]]; then
    IOS_SIM_PATH="$UNIVERSAL_XCF/ios-arm64-simulator/llama.framework"
fi

if [[ -z "$IOS_DEVICE_PATH" ]]; then
    echo "❌ ERROR: iOS device framework not found in universal xcframework"
    ls -la "$UNIVERSAL_XCF"
    exit 1
fi

if [[ -z "$IOS_SIM_PATH" ]]; then
    echo "⚠️  WARNING: iOS simulator framework not found, creating device-only xcframework"
    xcodebuild -create-xcframework \
        -framework "$IOS_DEVICE_PATH" \
        -output "$DST_DIR/llama_ios.xcframework" \
        2>&1 | grep -v "note:" || true
else
    xcodebuild -create-xcframework \
        -framework "$IOS_DEVICE_PATH" \
        -framework "$IOS_SIM_PATH" \
        -output "$DST_DIR/llama_ios.xcframework" \
        2>&1 | grep -v "note:" || true
fi

echo "✅ llama_ios.xcframework created"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Step 3: Verifying symbol presence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "macOS xcframework:"
echo "----------------------------------------"
MACOS_BIN=$(find "$DST_DIR/llama_macos.xcframework" -type f -name "llama" | head -1)
if [[ -f "$MACOS_BIN" ]]; then
    echo "Binary: $MACOS_BIN"
    echo "Architectures: $(lipo -archs "$MACOS_BIN")"
    echo ""
    echo "Checking for ggml symbols:"
    nm "$MACOS_BIN" | grep -E "ggml_add|ggml_backend_dev_init|ggml_flash_attn" | head -5 || echo "⚠️  No ggml symbols found!"
else
    echo "❌ Binary not found!"
fi
echo ""

echo "iOS xcframework:"
echo "----------------------------------------"
IOS_BIN=$(find "$DST_DIR/llama_ios.xcframework/ios-arm64" -type f -name "llama" 2>/dev/null | head -1)
if [[ -f "$IOS_BIN" ]]; then
    echo "Binary: $IOS_BIN"
    echo "Architectures: $(lipo -archs "$IOS_BIN")"
    echo ""
    echo "Checking for ggml symbols:"
    nm "$IOS_BIN" | grep -E "ggml_add|ggml_backend_dev_init|ggml_flash_attn" | head -5 || echo "⚠️  No ggml symbols found!"
else
    echo "❌ Binary not found!"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Output location: $DST_DIR"
ls -lh "$DST_DIR"
echo ""
echo "Next steps:"
echo "  1. Verify Xcode project links to the correct xcframeworks"
echo "  2. Build macOS target: xcodebuild -scheme NoesisNoema -destination 'platform=macOS'"
echo "  3. Build iOS target: xcodebuild -scheme NoesisNoemaMobile -destination 'platform=iOS Simulator'"
echo ""
