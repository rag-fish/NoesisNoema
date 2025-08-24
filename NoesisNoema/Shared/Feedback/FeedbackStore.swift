// filepath: NoesisNoema/Shared/Feedback/FeedbackStore.swift
// Description: Local-only encrypted feedback storage using CryptoKit + Keychain.
// License: MIT

import Foundation
import CryptoKit
import Security

// MARK: - Models
enum FeedbackVerdict: String, Codable {
    case up
    case down
}

struct FeedbackRecord: Codable, Hashable {
    let id: UUID
    let qaId: UUID
    let question: String
    let verdict: FeedbackVerdict
    let tags: [String]
    let timestamp: Date
}

// MARK: - Keychain helper
private enum KeychainHelper {
    static func loadOrCreateKey(tag: String) throws -> SymmetricKey {
        let keyTag = tag.data(using: .utf8)!
        // Query existing
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        // Create new 256-bit key
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw NSError(domain: "Keychain", code: Int(addStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to store key in Keychain"])
        }
        return key
    }
}

// MARK: - Store
final class FeedbackStore {
    static let shared = FeedbackStore()
    private let fileURL: URL
    private let key: SymmetricKey
    private let queue = DispatchQueue(label: "feedback.store.queue")

    private init() {
        // Resolve Application Support/NoesisNoema/feedback.enc
        let fm = FileManager.default
        let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport?.appendingPathComponent("NoesisNoema", isDirectory: true)
        if let dir, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = (dir ?? fm.temporaryDirectory).appendingPathComponent("feedback.enc")
        // Load or create key
        self.key = (try? KeychainHelper.loadOrCreateKey(tag: "NoesisNoema.Feedback.Key")) ?? SymmetricKey(size: .bits256)
    }

    func save(_ record: FeedbackRecord) {
        queue.async {
            var all = (try? self.loadAll()) ?? []
            all.append(record)
            do {
                try self.persist(all)
            } catch {
                print("[FeedbackStore] persist error: \(error)")
            }
        }
    }

    func loadAll() throws -> [FeedbackRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return [] }
        let enc = try Data(contentsOf: fileURL)
        let box = try AES.GCM.SealedBox(combined: enc)
        let dec = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode([FeedbackRecord].self, from: dec)
    }

    private func persist(_ items: [FeedbackRecord]) throws {
        let data = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw NSError(domain: "FeedbackStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to combine AES-GCM box"]) }
        try combined.write(to: fileURL, options: [.atomic])
    }
}
