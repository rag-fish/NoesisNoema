#!/bin/bash
set -euxo pipefail

echo "🧹 Cleaning repository..."

# Remove log files
find . -type f -name "*.log" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove txt dumps
find . -type f -name "*.txt" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove markdown except README.md and CHANGELOG.md
find . -type f -name "*.md" ! -name "README.md" ! -name "CHANGELOG.md" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove diff files
find . -type f -name "*.diff" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove backup files
find . -type f -name "*.bak*" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove dylibs
find . -type f -name "*.dylib" -print0 | xargs -0 git rm -f --ignore-unmatch

# Remove build artifacts
find . -type f -name "build-*" -print0 | xargs -0 git rm -f --ignore-unmatch
git rm -rf .build --ignore-unmatch || true

echo "✨ Cleanup done!"

echo "Next:"
echo "  git add .gitignore"
echo "  git commit -m 'chore: cleanup repo and improve .gitignore'"
echo "  git push"
