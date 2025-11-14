#!/usr/bin/env bash
set -euo pipefail

FRAME="NoesisNoema/Frameworks/xcframeworks/llama_macos.xcframework/macos-arm64/llama.framework"

echo "== Inspect =="
ls -la "$FRAME" || true
[ -d "$FRAME" ] || { echo "not found: $FRAME"; exit 1; }

# 判定: 既に Versions/A が正しく存在するか
if [ -d "$FRAME/Versions/A" ] && [ -f "$FRAME/Versions/A/llama" ]; then
  echo "Looks like a valid bundle layout already. Skipping layout fix."
else
  echo "== Normalize bundle layout =="
  TMP="$(mktemp -d)"
  # 既存中身を退避
  shopt -s dotglob
  mv "$FRAME"/* "$TMP"/

  # 必須ディレクトリ構成
  mkdir -p "$FRAME/Versions/A/Headers" "$FRAME/Versions/A/Modules" "$FRAME/Versions/A/Resources"

  # バイナリ候補を探す（名前が llama の Mach-O を優先）
  BIN_CANDIDATE=""
  if [ -f "$TMP/llama" ]; then BIN_CANDIDATE="$TMP/llama"; fi
  if [ -z "${BIN_CANDIDATE}" ]; then
    # 退避した中から実行可能Mach-Oを探す
    for f in "$TMP"/*; do
      if [ -f "$f" ] && file "$f" | grep -q "Mach-O.*arm64"; then
        BIN_CANDIDATE="$f"; break
      fi
    done
  fi
  [ -n "${BIN_CANDIDATE}" ] || { echo "binary not found in $TMP"; exit 1; }
  mv "$BIN_CANDIDATE" "$FRAME/Versions/A/llama"

  # 既存の Headers / Modules / Resources を取り込み（あれば）
  [ -d "$TMP/Headers" ]    && cp -a "$TMP/Headers/."    "$FRAME/Versions/A/Headers/"
  [ -d "$TMP/Modules" ]    && cp -a "$TMP/Modules/."    "$FRAME/Versions/A/Modules/"
  [ -d "$TMP/Resources" ]  && cp -a "$TMP/Resources/."  "$FRAME/Versions/A/Resources/"
  [ -f "$TMP/Info.plist" ] && mv    "$TMP/Info.plist"   "$FRAME/Versions/A/Resources/Info.plist" || true

  # 最低限のヘッダ（llama.h）が無ければダミーを作る
  if [ ! -f "$FRAME/Versions/A/Headers/llama.h" ]; then
    cat > "$FRAME/Versions/A/Headers/llama.h" <<'EOF'
#pragma once
// minimal public header for llama
#ifdef __cplusplus
extern "C" {
#endif
int llama_runtime_ping(void);
#ifdef __cplusplus
}
#endif
EOF
  fi

  # Modules/module.modulemap を整備（単一ヘッダ用）
  if [ ! -f "$FRAME/Versions/A/Modules/module.modulemap" ]; then
    cat > "$FRAME/Versions/A/Modules/module.modulemap" <<'EOF'
framework module llama {
  header "llama.h"
  export *
}
EOF
  fi

  # Info.plist が無ければ生成
  if [ ! -f "$FRAME/Versions/A/Resources/Info.plist" ]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.ragfish.llama' \
                            -c 'Add :CFBundleName string llama' \
                            -c 'Add :CFBundleVersion string 1.0' \
                            -c 'Add :CFBundleShortVersionString string 1.0' \
                            -c 'Add :CFBundlePackageType string FMWK' \
                            -c 'Add :CFBundleExecutable string llama' \
                            "$FRAME/Versions/A/Resources/Info.plist"
  fi

  # ルートにシンボリックリンクを用意
  ln -snf "A"                               "$FRAME/Versions/Current"
  ln -snf "Versions/Current/llama"          "$FRAME/llama"
  ln -snf "Versions/Current/Headers"        "$FRAME/Headers"
  ln -snf "Versions/Current/Modules"        "$FRAME/Modules"
  ln -snf "Versions/Current/Resources"      "$FRAME/Resources"

  # 退避ディレクトリ除去
  rm -rf "$TMP"
fi

echo "== Final layout =="
/bin/ls -la "$FRAME"
/bin/ls -la "$FRAME/Versions" || true
