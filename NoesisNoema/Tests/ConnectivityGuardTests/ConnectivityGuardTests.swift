// filepath: NoesisNoema/Tests/ConnectivityGuardTests/ConnectivityGuardTests.swift
// Comments: English

#if canImport(XCTest)
import XCTest
@testable import NoesisNoema

final class ConnectivityGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure known state
        AppSettings.shared.offline = false
    }

    func testCanPerformRemoteCallOnline() {
        AppSettings.shared.offline = false
        XCTAssertTrue(ConnectivityGuard.canPerformRemoteCall())
        XCTAssertNoThrow(try ConnectivityGuard.requireOnline())
    }

    func testCanPerformRemoteCallOffline() {
        AppSettings.shared.offline = true
        XCTAssertFalse(ConnectivityGuard.canPerformRemoteCall())
        XCTAssertThrowsError(try ConnectivityGuard.requireOnline()) { error in
            guard case ConnectivityGuardError.offline = error else {
                return XCTFail("Expected ConnectivityGuardError.offline, got: \(error)")
            }
        }
    }
}
#endif
