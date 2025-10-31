#!/bin/bash
# Static analysis guard: Check for forbidden llama.cpp binding imports
# Add this to Xcode Build Phases → Run Script

set -e

echo "🔍 Checking for unused llama.cpp bindings..."

FORBIDDEN_PATTERNS=(
    "import llama.swiftui"
    "from llama.cpp.bak"
    "examples/llama.swiftui"
)

SOURCE_DIRS=(
    "NoesisNoema/Shared"
    "NoesisNoema/ModelRegistry"
    "NoesisNoema/Tests"
)

FOUND_VIOLATIONS=0

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    for dir in "${SOURCE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            if grep -r "$pattern" "$dir" 2>/dev/null; then
                echo "❌ ERROR: Found forbidden pattern: '$pattern' in $dir"
                FOUND_VIOLATIONS=1
            fi
        fi
    done
done

if [ $FOUND_VIOLATIONS -eq 1 ]; then
    echo "❌ Static analysis failed: Forbidden imports found"
    exit 1
fi

echo "✅ No forbidden imports found"
echo "✅ Static analysis passed"
exit 0
