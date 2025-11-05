# Default LLM Selection, Sandbox-Safe Access, and Double-Submit Guard - Fix Summary

## Issues Addressed

### 1. Invalid Picker Selection/Tag Mismatch
**Problem**: SwiftUI Picker showed "Jan-V1-4B" as invalid selection without associated tag, causing UI errors.

**Root Cause**: Picker was using String-based selection without proper type safety. The `selectedLLMModel` State variable was a String, but models in registry use IDs, creating a mismatch.

**Solution**:
- Created strongly-typed `ModelID` struct with `Hashable`, `Codable`, and `Identifiable` conformance
- Updated Picker to use `ModelID?` with explicit `.tag(ModelID(spec.id) as ModelID?)` for each option
- Implemented proper binding that connects UI selection to `ModelManager.selectedModelID`

### 2. Sandbox Error (NSCocoaErrorDomain Code=257)
**Problem**: App attempted to scan `~/Downloads` at launch, violating macOS sandbox permissions.

**Error Message**:
```
[ModelRegistry] Error scanning directory /Users/.../Downloads:
NSCocoaErrorDomain Code=257 "The file 'Downloads' couldn't be opened
because you don't have permission to view it."
```

**Root Cause**: `ModelRegistry.getModelSearchPaths()` included:
- `~/Downloads`
- `~/Documents/Models`
- `/usr/local/share/noesisnoema/models`
- `/opt/noesisnoema/models`

All these paths require explicit user permission under App Sandbox.

**Solution**: Removed all non-container directory scanning:
```swift
// BEFORE: Scanned user directories
paths.append("\(homeDir)/Downloads")
paths.append("\(homeDir)/Documents/Models")

// AFTER: Container-only scanning
if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
    paths.append(appSupport.appendingPathComponent("NoesisNoema/models").path)
}
```

Now scans only:
- App bundle `Resources/` (read-only models shipped with app)
- Application Support container directories
- User-selected files/folders via NSOpenPanel (handled separately)

### 3. Double-Submit Guard / Ask Button Lock
**Problem**: After Xcode 26 migration, Ask button could be pressed multiple times rapidly, triggering concurrent generation requests leading to crashes or "killed" messages.

**Root Cause**: No guard against concurrent calls to `generateAsyncAnswer()`.

**Solution**:
- Added `@Published var isGenerating = false` to `ModelManager`
- Guard at start of `generateAsyncAnswer()`:
```swift
guard !isGenerating else {
    return "[ERROR] Generation already in progress"
}
isGenerating = true
defer {
    Task { @MainActor in
        self.isGenerating = false
    }
}
```
- Updated UI to disable Ask button when `isGenerating` is true
- Show progress indicator during generation
- Added `defer` blocks to ensure state always resets even on errors

### 4. No Default Model Selection
**Problem**: On first launch, no model was automatically selected, leaving Picker empty or with invalid selection.

**Solution**:
- Added `setDefaultModel()` method called after model scan completes
- Attempts to restore last selection from UserDefaults
- Falls back to first available model if no saved preference
- Persists selection on each change for next launch

```swift
private func setDefaultModel() async {
    // Try restore from UserDefaults
    if let lastModelIDString = UserDefaults.standard.string(forKey: "lastSelectedModelID"),
       availableModels.contains(where: { $0.id == lastModelIDString }) {
        selectedModelID = ModelID(lastModelIDString)
    } else {
        // Pick first available
        if let firstModel = availableModels.first {
            selectedModelID = ModelID(firstModel.id)
        }
    }
}
```

## Files Modified

### 1. `NoesisNoema/ModelRegistry/Core/ModelID.swift` (NEW)
Strongly-typed model identifier for SwiftUI Picker binding:
- `Hashable`, `Codable`, `Identifiable` conformance
- `ExpressibleByStringLiteral` for convenience
- Type-safe alternative to raw String IDs

### 2. `NoesisNoema/ModelRegistry/Core/ModelRegistry.swift`
Sandbox-safe model search paths:
- Removed `~/Downloads`, `~/Documents/Models`, `/usr/local/share`, `/opt`
- Added container-only directories
- Platform-specific handling (iOS vs macOS containers)
- Added documentation explaining security-scoped bookmarks for user-selected paths

### 3. `NoesisNoema/Shared/ModelManager.swift`
Default selection and generation guard:
- Added `@Published var isGenerating = false`
- Added `@Published var selectedModelID: ModelID?`
- Implemented `setDefaultModel()` with UserDefaults persistence
- Added `switchLLMModelByID(_ modelID: ModelID)` for type-safe switching
- Guard in `generateAsyncAnswer()` against concurrent requests
- Proper defer blocks to ensure state cleanup

### 4. `NoesisNoema/Shared/ContentView.swift`
UI updates for type-safe Picker and state management:
- Removed `@State private var selectedLLMModel: String`
- Added `selectedModelIDBinding: Binding<ModelID?>` computed property
- Updated Picker to use `ModelID` with explicit tags
- Added guards in `askRAG()` for nil model and concurrent requests
- Updated Ask button to show progress indicator when generating
- Disable Ask button when `modelManager.selectedModelID == nil`

## Testing Checklist

### ✅ No Sandbox Errors
- App launches without NSCocoaErrorDomain Code=257 errors
- No attempts to access ~/Downloads or other restricted paths
- Model registry scans only permitted locations

### ✅ Default Model Selected
- On first launch, first available model is automatically selected
- Picker shows valid selection (not "invalid" or blank)
- Selection persists across app restarts

### ✅ No Double-Submit
- Pressing Ask button rapidly (double-click) triggers only one generation
- Button shows "Generating..." with progress indicator during inference
- Button re-enables only after generation completes
- No "killed" or crash after rapid button presses

### ✅ Proper Error Handling
- Attempting to Ask without model selection shows inline error
- Generation errors reset UI state properly (isGenerating = false)
- defer blocks ensure cleanup even on exceptions

## Acceptance Criteria Status

| Criterion | Status |
|-----------|--------|
| No sandbox errors (NSCocoaErrorDomain 257) | ✅ PASS |
| Model Picker shows valid default | ✅ PASS |
| Picker tags work correctly | ✅ PASS |
| Ask button prevents double-submit | ✅ PASS |
| Progress indicator shows during generation | ✅ PASS |
| No crashes from rapid button presses | ✅ PASS |
| Selection persists across launches | ✅ PASS |
| Build succeeds for macOS | ✅ PASS |
| Build succeeds for iOS | ⏳ TODO (not tested) |

## Security Notes

### Security-Scoped Bookmarks (Future Enhancement)
For user-selected files outside container (e.g., via NSOpenPanel), implement:

```swift
func persistBookmark(for url: URL) throws {
    let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    UserDefaults.standard.set(bookmarkData, forKey: "model_path_\(url.lastPathComponent)")
}

func resolveBookmark(data: Data) -> URL? {
    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else { return nil }

    return isStale ? nil : url
}
```

Currently not needed as models are shipped in app bundle Resources.

## Known Limitations

1. **iOS Testing**: Changes not yet tested on iOS target (should work identically)
2. **Model Discovery**: Only scans container directories; external model folders require manual addition via file picker
3. **Progress Granularity**: Generation shows binary state (generating/done); no percentage progress
4. **Token Refresh**: No automatic refresh if model becomes unavailable after selection

## Next Steps

1. Test iOS target to verify identical behavior
2. Consider adding security-scoped bookmarks for user-added model directories
3. Add unit tests for `ModelID` and `setDefaultModel()` logic
4. Implement model availability health check before allowing Ask

## Commit

```
239adbb fix: default LLM selection, sandbox-safe RAGpack access, double-submit guard
```

All acceptance criteria met for macOS target.
