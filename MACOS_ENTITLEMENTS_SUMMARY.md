# macOS Sandbox Entitlements Implementation Summary

## Task
Enable macOS sandbox entitlements to allow NSOpenPanel RAGpack (.zip) import without security errors.

## Problem
Without proper entitlements, NSOpenPanel could fail with:
- "Unable to display open panel... missing User Selected File Read" error
- Sandbox violations when trying to read user-selected files
- Potential access issues when processing .zip RAGpack files

## Solution Implemented

### 1. Created macOS Entitlements File
**File**: `NoesisNoema/NoesisNoema.macOS.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
</dict>
</plist>
```

**Rationale**:
- `com.apple.security.app-sandbox`: Enables App Sandbox for security
- `com.apple.security.files.user-selected.read-only`: Grants read access to files chosen via NSOpenPanel
- **No broad folder exceptions**: Unlike typical sandboxing that might add Documents/Downloads access, we only need user-selected file access

### 2. Wired Entitlements to Xcode Project
**File**: `NoesisNoema.xcodeproj/project.pbxproj`

Added to both Debug and Release configurations for the macOS target (NoesisNoema):
```
CODE_SIGN_ENTITLEMENTS = NoesisNoema/NoesisNoema.macOS.entitlements;
```

This ensures:
- Entitlements are embedded during code signing
- Both development and release builds have proper sandbox configuration
- No additional capabilities needed beyond what's specified

### 3. Platform-Specific File Access
**File**: `NoesisNoema/Shared/DocumentManager.swift`

```swift
private func processRAGpackImport(fileURL: URL) async {
    var didStartAccessing = false
    #if os(iOS)
    // iOS needs security-scoped resource access
    didStartAccessing = fileURL.startAccessingSecurityScopedResource()
    defer { if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() } }
    #elseif os(macOS)
    // NSOpenPanel + user-selected-file entitlement is sufficient; no scoped access required
    #endif
    // ... rest of import logic
}
```

**Key Points**:
- iOS: Uses `startAccessingSecurityScopedResource()` for Files app / iCloud files
- macOS: NSOpenPanel with user-selected entitlement handles security automatically
- Background thread processing maintained via `Task.detached`
- UI updates still on main thread via `MainActor.run`

## Verification

### Entitlements Check
```bash
$ codesign -d --entitlements - NoesisNoema.app
[Dict]
[Key] com.apple.security.app-sandbox
[Value] [Bool] true
[Key] com.apple.security.files.user-selected.read-only
[Value] [Bool] true
```

### Test Results
✅ **Build**: Succeeds without errors
✅ **Launch**: App starts and runs normally
✅ **NSOpenPanel**: Opens file picker for .zip selection
✅ **File Access**: Can read user-selected .zip files without errors
✅ **Import**: RAGpack processing works (unzip, parse, add to VectorStore)
✅ **iOS Unchanged**: iOS target behavior remains the same

## Benefits

1. **Security**: App is properly sandboxed following macOS security best practices
2. **Minimal Permissions**: Only requests access to files user explicitly selects
3. **No Errors**: Eliminates "missing User Selected File Read" errors
4. **Platform-Appropriate**: Each platform uses its native security model
5. **Future-Proof**: Follows Apple's recommended sandboxing approach

## Technical Details

### Sandbox Behavior
- App cannot access arbitrary files on the system
- Files selected via NSOpenPanel are automatically granted read access
- Temporary directory writes (for ZIP extraction) remain unrestricted within app container
- VectorStore and uploadHistory updates happen in app's sandboxed storage

### Code Signing
- Entitlements are embedded in the app binary during code signing
- Developer certificate includes sandbox entitlements
- No manual codesigning steps required

### Threading Model (Maintained)
- Heavy work: Background thread via `Task.detached`
- UI updates: Main thread via `MainActor.run`
- No blocking on main thread during import

## Next Steps

The macOS app now has proper sandbox entitlements. Users can:
1. Click "Choose File" button
2. NSOpenPanel opens without errors
3. Select any .zip RAGpack file from any location
4. App reads and processes the file securely
5. Chunks appear in VectorStore for RAG queries

All acceptance criteria met. No further configuration needed.
