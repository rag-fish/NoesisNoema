Title: Enable macOS sandbox entitlements for NSOpenPanel RAGpack import

Context / Constraints
	•	Project: NoesisNoema (macOS target name: NoesisNoema)
	•	Keep architecture as-is: Swift-only app; llama.cpp xcframeworks are imported externally; fully local RAG.
	•	Do not rebuild xcframeworks. Do not change iOS target.
	•	Goal: On macOS, allow selecting a local .zip RAGpack via NSOpenPanel and importing it without crashes.

Tasks
	1.	Add macOS entitlements file
Create NoesisNoema/NoesisNoema.macOS.entitlements with the following keys:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <!-- We only read the user-selected .zip; writes go to app container / tmp -->
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict>
</plist>
```

Do not add broad folder exceptions (Documents/Downloads). We only need user-selected read.

	2.	Wire entitlements to the macOS target
Edit NoesisNoema.xcodeproj/project.pbxproj:
	•	Under buildSettings for the macOS target (NoesisNoema) set:

CODE_SIGN_ENTITLEMENTS = NoesisNoema/NoesisNoema.macOS.entitlements;

for Debug/Release (and any custom configs that exist).

	•	Ensure the target has App Sandbox capability (this is implied by the entitlements; no other capabilities needed).

	3.	DocumentManager: tidy platform guards (no security scoped for macOS)
In NoesisNoema/Shared/DocumentManager.swift:
	•	Keep the existing #if os(iOS) block that uses startAccessingSecurityScopedResource.
	•	Add a corresponding #elseif os(macOS) path that does not attempt security-scoped bookmarks (not needed when the file is returned by NSOpenPanel under the user-selected entitlement).
	•	Ensure heavy work still runs off the main thread (Task.detached) and that UI mutations remain on MainActor.run.
Example sketch (adjust to current code):
```swift
#if os(iOS)
  var didStartAccessing = fileURL.startAccessingSecurityScopedResource()
  defer { if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() } }
#elseif os(macOS)
  // NSOpenPanel + user-selected-file entitlement is sufficient; no scoped access required.
#endif
```

	4.	Graceful error if entitlements absent (optional safety)
In ContentView’s RAGpack upload button action (macOS path), if NSOpenPanel().runModal() throws due to entitlement issues, surface a user-friendly alert suggesting to enable User Selected File Read entitlement. This is a soft guard and should not break normal flow.

Acceptance Criteria
	•	Build succeeds for macOS target.
	•	Launch app → Choose File opens a native NSOpenPanel.
	•	Selecting a local .zip successfully imports: DocumentManager processes it, updates VectorStore.shared.chunks, and appends to uploadHistory without UI freeze.
	•	No “Unable to display open panel… missing User Selected File Read” error.
	•	No new capabilities added beyond App Sandbox + user-selected read-only.
	•	iOS behavior unchanged.

Files to create/modify
	•	NoesisNoema/NoesisNoema.macOS.entitlements (new)
	•	NoesisNoema.xcodeproj/project.pbxproj (set CODE_SIGN_ENTITLEMENTS for macOS target)
	•	NoesisNoema/Shared/DocumentManager.swift (platform-guarded access; no security-scoped calls on macOS)

Post-fix runbook (for me)
	•	Clean build folder for macOS scheme.
	•	Run the macOS app, click Choose File, select a .zip RAGpack in any folder.
	•	Confirm chunks appear and can be retrieved by the RAG flow.
