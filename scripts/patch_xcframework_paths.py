#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "NoesisNoema.xcodeproj" / "project.pbxproj"

text = PBXPROJ.read_text()
orig = text

# 1) Update attributesByRelativePath keys to use xcframeworks/ path
text = re.sub(r"(\bFrameworks/)llama_macos\.xcframework(\s*=)", r"\1xcframeworks/llama_macos.xcframework\2", text)
text = re.sub(r"(\bFrameworks/)llama_ios\.xcframework(\s*=)", r"\1xcframeworks/llama_ios.xcframework\2", text)

# 2) Remove old-membership lines for legacy top-level paths in membershipExceptions arrays
lines = text.splitlines()
keep = []
for line in lines:
    l = line.strip()
    if l in {"Frameworks/llama_macos.xcframework,", "Frameworks/llama_ios.xcframework,"}:
        continue
    keep.append(line)
text = "\n".join(keep)

if text != orig:
    PBXPROJ.write_text(text)
    print("Patched project.pbxproj: removed old llama_* xcframework references and updated attributes to xcframeworks/* paths")
else:
    print("No changes made (already clean)")
