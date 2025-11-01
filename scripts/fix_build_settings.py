#!/usr/bin/env python3
import sys
import re
from pathlib import Path

PROJECT_PBXPROJ = Path(__file__).resolve().parents[1] / "NoesisNoema.xcodeproj" / "project.pbxproj"

# Build configuration IDs extracted from the project
CONFIGS = {
    # Project-level
    "F41FD0242E2A467000909132": {"name": "Project Debug", "swift": True, "infoplist": False},
    "F41FD0252E2A467000909132": {"name": "Project Release", "swift": True, "infoplist": False},
    # NoesisNoema (macOS app)
    "F41FD0272E2A467000909132": {"name": "NoesisNoema Debug", "swift": True, "infoplist": True},
    "F41FD0282E2A467000909132": {"name": "NoesisNoema Release", "swift": True, "infoplist": True},
    # LlamaBridgeTest (tool)
    "F460884E2E2CD45000D4C555": {"name": "LlamaBridgeTest Debug", "swift": True, "infoplist": False},
    "F460884F2E2CD45000D4C555": {"name": "LlamaBridgeTest Release", "swift": True, "infoplist": False},
    # NoesisNoemaMobile (iOS app)
    "F4C581062E4F006800E64194": {"name": "NoesisNoemaMobile Debug", "swift": True, "infoplist": True},
    "F4C581072E4F006800E64194": {"name": "NoesisNoemaMobile Release", "swift": True, "infoplist": True},
}

SWIFT_VERSION_LINE = "\t\t\t\tSWIFT_VERSION = 5.0;\n"
GENERATE_INFOPLIST_LINE = "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"


def patch_block(text: str, config_id: str, set_swift: bool, set_infoplist: bool) -> str:
    # Find the config block start
    start_pat = re.compile(rf"\n\t\t{re.escape(config_id)} \/\* .+? \*\/ = \{{", re.DOTALL)
    m = start_pat.search(text)
    if not m:
        return text
    block_start = m.start()
    # Find buildSettings = { ... } within this block
    bs_start = text.find("buildSettings = {", m.end())
    if bs_start == -1:
        return text
    # Find the end of buildSettings block by locating the matching '};' that closes it
    # We'll search for the first "\n\t\t\t};" after bs_start
    bs_end = text.find("\n\t\t\t};", bs_start)
    if bs_end == -1:
        return text
    bs_content_start = bs_start + len("buildSettings = {")
    bs_content = text[bs_content_start:bs_end]

    # Ensure settings
    if set_swift and "SWIFT_VERSION" not in bs_content:
        # Insert just before the closing
        bs_content = bs_content + "\n" + SWIFT_VERSION_LINE
    if set_infoplist and "GENERATE_INFOPLIST_FILE" not in bs_content:
        bs_content = bs_content + "\n" + GENERATE_INFOPLIST_LINE

    new_text = text[:bs_content_start] + bs_content + text[bs_end:]
    return new_text


def main():
    data = PROJECT_PBXPROJ.read_text()
    orig = data
    for cid, meta in CONFIGS.items():
        data = patch_block(data, cid, meta["swift"], meta["infoplist"])
    if data != orig:
        PROJECT_PBXPROJ.write_text(data)
        print("Patched:")
        for cid, meta in CONFIGS.items():
            print(f" - {meta['name']} ({cid})")
    else:
        print("No changes applied (already up to date?)")

if __name__ == "__main__":
    main()
