# Google Drive RAGpack Import - Implementation Guide

## Overview
Add Google Drive integration to allow users to import RAGpack .zip files directly from their Google Drive, with full OAuth authentication and platform-specific UI.

## Prerequisites
- Google Cloud Console project with Drive API enabled
- OAuth 2.0 Client IDs (iOS + macOS)
- Google Sign-In Swift SDK

## Phase 1: Add Dependencies (30 min)

### 1.1 Add Google Sign-In SDK via SPM

In Xcode:
1. File → Add Package Dependencies
2. Add: `https://github.com/google/GoogleSignIn-iOS`
3. Version: 7.0.0 or later
4. Add to both NoesisNoema (macOS) and NoesisNoemaMobile (iOS) targets

### 1.2 Update project.pbxproj

After adding via Xcode, the project.pbxproj should include:
```
XCRemoteSwiftPackageReference "GoogleSignIn-iOS"
XCSwiftPackageProductDependency "GoogleSignIn"
XCSwiftPackageProductDependency "GoogleSignInSwift"
```

## Phase 2: Configure OAuth (30 min)

### 2.1 Get OAuth Credentials

1. Go to https://console.cloud.google.com
2. Create/select project
3. Enable Google Drive API
4. Create OAuth 2.0 Client IDs:
   - **iOS**: Bundle ID = `fish.rag.NoesisNoema`
   - **macOS**: Bundle ID = `fish.rag.NoesisNoema`
5. Download configuration files

### 2.2 Update Info.plist

**For macOS** (`NoesisNoema/Info.plist` - may need to create):
```xml
<key>GIDClientID</key>
<string>YOUR_MACOS_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

**For iOS** (`NoesisNoemaMobile/Info.plist`):
```xml
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

### 2.3 Update Entitlements

**NoesisNoema.macOS.entitlements**:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

## Phase 3: Implement Google Drive Service (60 min)

### 3.1 Create GoogleDriveService.swift

File: `NoesisNoema/Shared/GoogleDriveService.swift`

```swift
import Foundation
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum DriveError: Error {
    case notSignedIn
    case downloadFailed
    case invalidFileType
}

@MainActor
class GoogleDriveService: ObservableObject {
    static let shared = GoogleDriveService()

    @Published var isSignedIn = false
    @Published var currentUser: GIDGoogleUser?

    private init() {
        restorePreviousSignIn()
    }

    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            Task { @MainActor in
                if let user = user {
                    self.currentUser = user
                    self.isSignedIn = true
                } else {
                    self.isSignedIn = false
                }
            }
        }
    }

    func signIn() async throws {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw DriveError.notSignedIn
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/drive.readonly"]
        )
        #elseif os(macOS)
        guard let window = NSApplication.shared.windows.first else {
            throw DriveError.notSignedIn
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/drive.readonly"]
        )
        #endif

        await MainActor.run {
            self.currentUser = result.user
            self.isSignedIn = true
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isSignedIn = false
    }

    func listZipFiles() async throws -> [DriveFile] {
        guard let user = currentUser else {
            throw DriveError.notSignedIn
        }

        let accessToken = user.accessToken.tokenString

        // Google Drive API: List files
        var urlComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: "mimeType='application/zip' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name,size,createdTime)"),
            URLQueryItem(name: "pageSize", value: "100")
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DriveFileListResponse.self, from: data)

        return response.files
    }

    func downloadFile(fileId: String, fileName: String, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let user = currentUser else {
            throw DriveError.notSignedIn
        }

        let accessToken = user.accessToken.tokenString

        // Download URL
        let downloadURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!

        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-drive-imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destination = tempDir.appendingPathComponent(fileName)

        // Download with progress
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        // Move to destination
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        return destination
    }
}

struct DriveFile: Identifiable, Codable {
    let id: String
    let name: String
    let size: String?
    let createdTime: String?
}

struct DriveFileListResponse: Codable {
    let files: [DriveFile]
}
```

## Phase 4: Add Import Status (15 min)

### 4.1 Update DocumentManager.swift

Add near top of DocumentManager class:

```swift
enum ImportStatus: Equatable {
    case idle
    case downloading(progress: Double)
    case processing
    case success(fileName: String)
    case failure(message: String)
}

@Published var lastImportStatus: ImportStatus = .idle
```

## Phase 5: Implement Drive Import (45 min)

### 5.1 Add Method to DocumentManager

Add to `DocumentManager` class:

```swift
@MainActor
func importRAGpackFromGoogleDrive() async throws {
    lastImportStatus = .idle

    // 1. Sign in if needed
    if !GoogleDriveService.shared.isSignedIn {
        try await GoogleDriveService.shared.signIn()
    }

    // 2. List zip files
    let files = try await GoogleDriveService.shared.listZipFiles()

    guard !files.isEmpty else {
        lastImportStatus = .failure(message: "No .zip files found in Google Drive")
        return
    }

    // 3. Show picker (simplified - pick first for now, or implement picker UI)
    // TODO: Show DriveFilePickerView here
    guard let selectedFile = files.first else { return }

    // 4. Download with progress
    lastImportStatus = .downloading(progress: 0.0)

    let localURL = try await GoogleDriveService.shared.downloadFile(
        fileId: selectedFile.id,
        fileName: selectedFile.name
    ) { progress in
        Task { @MainActor in
            self.lastImportStatus = .downloading(progress: progress)
        }
    }

    // 5. Process the downloaded file
    lastImportStatus = .processing
    await processRAGpackImport(fileURL: localURL)

    // 6. Update status
    lastImportStatus = .success(fileName: selectedFile.name)

    // 7. Trigger UI update
    self.objectWillChange.send()

    // 8. Cleanup
    try? FileManager.default.removeItem(at: localURL)
}
```

### 5.2 Update processRAGpackImport

Add at the end of `processRAGpackImport` method (in the `MainActor.run` block):

```swift
self.objectWillChange.send()
```

## Phase 6: Update UI (30 min)

### 6.1 Update ContentView RAGpack Section

Find the `ragpackUploadSection` in ContentView.swift and update:

```swift
private var ragpackUploadSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("RAGpack(.zip) Upload:")
            .font(.title3)
            .bold()

        HStack(spacing: 12) {
            // Existing local file button
            Button(action: {
                #if os(macOS)
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [UTType.zip]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if panel.runModal() == .OK {
                    documentManager.importDocument(file: panel.url!)
                }
                #endif
            }) {
                Label("Choose File", systemImage: "doc.zipper")
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)

            // NEW: Google Drive button
            Button(action: {
                Task {
                    isLoading = true
                    defer { isLoading = false }
                    try? await documentManager.importRAGpackFromGoogleDrive()
                }
            }) {
                Label("Google Drive", systemImage: "cloud")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }

        // Status indicator
        importStatusView
    }
    .padding(.horizontal)
}

private var importStatusView: some View {
    Group {
        switch documentManager.lastImportStatus {
        case .idle:
            EmptyView()
        case .downloading(let progress):
            HStack {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
            }
        case .processing:
            HStack {
                ProgressView()
                Text("Processing...")
                    .font(.caption)
            }
        case .success(let fileName):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Imported: \(fileName)")
                    .font(.caption)
            }
        case .failure(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
            }
        }
    }
}
```

### 6.2 Add ObservedObject for DocumentManager

In ContentView, ensure DocumentManager is observed:

```swift
@StateObject private var documentManager = DocumentManager()
```

## Phase 7: Handle OAuth Redirect (15 min)

### 7.1 Update App Delegate (macOS)

Create `NoesisNoema/Shared/AppDelegate.swift`:

```swift
#if os(macOS)
import AppKit
import GoogleSignIn

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}
#endif
```

### 7.2 Update iOS Scene Delegate

Update `NoesisNoemaMobile/NoesisNoemaMobileApp.swift`:

```swift
#if os(iOS)
import GoogleSignIn

@main
struct NoesisNoemaMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
#endif
```

## Phase 8: Testing Checklist

### Build Test
- [ ] macOS target builds without errors
- [ ] iOS target builds without errors
- [ ] Google Sign-In SDK imported correctly

### Functional Test
- [ ] Click "Google Drive" button opens OAuth browser
- [ ] Sign in completes and returns to app
- [ ] File list loads (if implemented)
- [ ] Download shows progress
- [ ] RAGpack processes and adds to VectorStore
- [ ] UI updates immediately after import
- [ ] "Choose File" (local) still works

### Offline Test
- [ ] Disconnect network
- [ ] Reopen app
- [ ] Local RAG queries still work
- [ ] Existing chunks accessible

## Known Issues & TODOs

1. **File Picker UI**: Currently picks first file - need to implement DriveFilePickerView
2. **Progress Tracking**: URLSession.download doesn't provide granular progress by default
3. **Error Handling**: Need more detailed error messages
4. **Token Refresh**: Google tokens expire - need refresh logic
5. **Cancel Operation**: No way to cancel ongoing download

## Security Considerations

- OAuth tokens stored in Keychain by Google SDK
- Only requests `drive.readonly` scope
- Downloads to temporary directory (auto-cleaned by OS)
- No persistent storage of Drive credentials
- Network client entitlement required (macOS only)

## Estimated Effort

- **Core Implementation**: 4 hours
- **UI Polish**: 1 hour
- **Testing & Debugging**: 1-2 hours
- **Total**: 6-7 hours

## Alternative: Simplified Approach

If full Drive integration is too complex, consider:

1. **Manual Download**: User downloads .zip from Drive browser
2. **Drag & Drop**: Implement drop target for .zip files
3. **iCloud Drive**: Use native file picker (already works)
4. **Share Sheet**: Import via iOS Share Extension

This avoids OAuth complexity while still enabling cloud imports.
