Request: Fix macOS launch crash (“_abort_with_payload”) and wire xcframeworks correctly

Repository: rag-fish/NoesisNoema
Current branch: feature/macos-launch-fix (do all work here)
Xcode: 26.x
Targets:
	•	NoesisNoema (macOS app) ← in scope
	•	NoesisNoemaMobile (iOS app) ← out of scope; don’t modify
	•	LlamaBridgeTest (CLI) ← out of scope for now

Context & facts (do not contradict):
	•	We do not build xcframeworks inside Xcode. They are built externally from llama.cpp via our CLion shell script and then imported.
	•	Frameworks live in the project as files, not SwiftPM:
	•	NoesisNoema/Frameworks/llama_macos.xcframework
	•	NoesisNoema/Frameworks/llama_ios.xcframework (exists for iOS; don’t touch)
	•	The macOS app crashes on launch with _abort_with_payload. Prior logs showed loader searching for libggml*.dylib and failing; we do not use ggml dylibs directly anymore—only the llama.framework inside the xcframework.
	•	Swift wrapper is used (import llama in Shared/Llama/LibLlama.swift). iOS builds now succeed; macOS builds succeed but crash at launch.
	•	We want a pure-Swift app; no Obj-C or C glue added to the Xcode project.
	•	Keep code signing working and do not regress the iOS target.

⸻

Goals
	1.	Fix macOS launch crash (remove/resolve any stale loader settings expecting libggml*.dylib; use the llama.framework slice from llama_macos.xcframework properly).
	2.	Ensure the macOS target finds, links, copies, and codesigns llama.framework at runtime.
	3.	Keep iOS target and CLI target untouched.
	4.	Produce a single PR from feature/macos-launch-fix with a clean, minimal diff.

⸻

Exact tasks

A. Project settings (macOS target only)
	•	In NoesisNoema (macOS) Build Settings:
	•	Framework Search Paths add (non-recursive):
$(PROJECT_DIR)/Frameworks/
$(PROJECT_DIR)/Frameworks/llama_macos.xcframework/macos-arm64/
	•	Header Search Paths (if needed by Swift wrapper, non-recursive):
$(PROJECT_DIR)/Frameworks/llama_macos.xcframework/macos-arm64/llama.framework/Headers
	•	Library Search Paths: remove any paths pointing to libggml*.dylib or build-macos/*.dylib.
	•	Runpath Search Paths must include:
@executable_path/../Frameworks
@loader_path/../Frameworks
	•	Enable Modules (C and Objective-C): YES (modulemap is present).
	•	Valid Architectures: arm64 only (no x86_64).
	•	In Build Phases (macOS target):
	•	Link Binary With Libraries: ensure llama.framework (the slice inside llama_macos.xcframework/macos-arm64) is linked, not any *.dylib.
	•	Embed Frameworks: add llama.framework with Embed & Sign.
	•	Remove any “Copy Files” step that tries to copy libggml*.dylib.
	•	In General ▸ Frameworks, Libraries, and Embedded Content (macOS):
	•	llama_macos.xcframework should appear; ensure the embedded artifact is llama.framework with Embed & Sign.
	•	Confirm module.modulemap exists at
NoesisNoema/Frameworks/llama_macos.xcframework/macos-arm64/llama.framework/Modules/module.modulemap
and that the umbrella header is llama.h.

B. Swift wrapper sanity
	•	In Shared/Llama/LibLlama.swift and related files, ensure imports are just import llama (no import ggml).
	•	If any references to ggml symbols linger, remove them and stick to the llama C API exposed by the module header.

C. Runtime verification
	•	Create a temporary smoke test in the macOS app launch path (e.g., inside @main or first ViewModel init) that:
	•	Loads a tiny local model file path from Resources/Models (do not add large files or change resources; just try a “stat”/existence check and skip if not present).
	•	Calls a minimal llama_backend_init() / context create-destroy via the Swift wrapper to verify the dynamic loader can resolve symbols. If a model is missing, skip gracefully but ensure the call to the library succeeds (or guard behind an #if DEBUG).
	•	Remove or comment out the smoke test before final commit if it risks long startup; otherwise keep it behind a debug flag.

D. Tooling to edit project safely
	•	Prefer editing project.pbxproj using a small Ruby script with the xcodeproj gem placed under scripts/fix_macos_launch.rb.
	•	The script should idempotently:
	•	Add/ensure the above Framework Search Paths and Runpath Search Paths.
	•	Ensure llama.framework is linked and embedded for the macOS target.
	•	Remove any build settings referencing libggml*.dylib.
	•	Log a dry-run diff, then apply. Commit both the script and the change.

⸻

Constraints
	•	Don’t touch iOS target (NoesisNoemaMobile) or LlamaBridgeTest.
	•	Don’t add SPM packages or pods.
	•	Don’t move the xcframeworks; their paths are as stated.
	•	Keep commits small and descriptive. No mass reformatting.
	•	If you must create a helper file, place it under scripts/ and document it in docs/.

⸻

Acceptance criteria
	•	xcodebuild -project NoesisNoema.xcodeproj -scheme NoesisNoema -configuration Debug -destination 'platform=macOS' build succeeds.
	•	Running the app no longer aborts at launch; main window appears.
	•	Runtime loader errors about libggml*.dylib disappear.
	•	import llama compiles; no No such module 'llama'.
	•	iOS target still builds and runs as before (spot-check compile only).
	•	PR created from feature/macos-launch-fix with title:
“fix(macOS): resolve launch crash by correct llama.xcframework linkage & runtime paths”
and a checklist in the description referencing this task.

⸻

What to output
	1.	A short plan of detected problems and the changes you’ll apply.
	2.	The scripts/fix_macos_launch.rb (or equivalent) if you choose that route.
	3.	The exact xcodebuild commands you ran and their logs saved under build-macos-*.log.
	4.	A final summary and open a PR.

If something blocks you (e.g., path mismatch), stop and print the exact blocking setting and the file you need me to confirm.
