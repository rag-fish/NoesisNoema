#!/bin/bash
set -euo pipefail

LIST_FILE="deleted_files.txt"

if [[ ! -f "$LIST_FILE" ]]; then
    echo "❌ deleted_files.txt が存在しません。まず以下を実行してください:"
    echo "   git ls-files --deleted > deleted_files.txt"
    exit 1
fi

echo "🧹 Git index から不要ファイルを削除開始..."

while IFS= read -r file; do
    if [[ -n "$file" && -e "$file" ]]; then
        # ファイルが存在する＝誤爆防止
        echo "⚠️ 物理ファイルがまだ存在するためスキップ: $file"
    else
        echo "🗑️ git rm --cached \"$file\""
        git rm --cached "$file" || true
    fi
done < "$LIST_FILE"

echo "📦 コミット中..."
git add -A
git commit -m "chore: remove deleted repo files from Git index"
echo "✅ 完了。push する場合は: git push"
