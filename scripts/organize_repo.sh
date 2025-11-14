#!/usr/bin/env bash
set -e

echo "🚀 Starting NoesisNoema repository organization..."

##############################
# 1. Create target directories
##############################
mkdir -p logs
mkdir -p docs
mkdir -p scripts

##############################
# 2. Move log files
##############################
echo "📦 Moving *.log to logs/"
find . -maxdepth 1 -type f \( -name "*.log" -o -name "*.txt" \) -print -exec mv {} logs/ \;

##############################
# 3. Move md files except README.md
##############################
echo "📦 Moving *.md (except README.md) to docs/"
find . -maxdepth 1 -type f -name "*.md" ! -name "README.md" -print -exec mv {} docs/ \;

##############################
# 4. Move scripts
##############################
echo "📦 Moving scripts (*.sh, *.rb) to scripts/"
find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.rb" \) -print -exec mv {} scripts/ \;

##############################
# 5. Git cleanup
##############################
echo "🧹 Updating git index..."

git add logs docs scripts
git rm --cached *.log 2>/dev/null || true
git rm --cached *.txt 2>/dev/null || true

# .md（README.md以外）
find docs -type f -name "*.md" -print | while read f; do
  git rm --cached "$(basename $f)" 2>/dev/null || true
done

echo "📝 Update .gitignore"
cat <<EOF >> .gitignore

# Auto-cleanup patterns (added by organize_repo.sh)
logs/
docs/
*.log
*.txt
EOF

git add .gitignore

echo "🎉 Organization complete! Run:"
echo "    git commit -m \"Cleanup: reorganize logs, docs, scripts\""
echo "    git push"
