// filepath: NoesisNoema/Tests/CitationPopoverSnapshotTests/CitationPopoverSnapshotTests_macOS.swift
// Comments: English

// Disabled in app target to avoid XCTest link errors
#if false
#if canImport(XCTest)
#if os(macOS)
import XCTest
import SwiftUI
@testable import NoesisNoema

@MainActor
final class CitationPopoverSnapshotTests_macOS: XCTestCase {
    func testSnapshotRendersNonEmptyImage_macOS() throws {
        if #available(macOS 13.0, *) {
            let cat = [
                CitationInfo(index: 1, title: "Ethics", path: "/tmp/ethics.pdf", page: 12),
                CitationInfo(index: 2, title: "Letters", path: nil, page: nil)
            ]
            let per = [[1,2], [2]]
            let view = CitationPopoverView(citations: ParagraphCitations(perParagraph: per, catalog: cat))
                .frame(width: 380, height: 260)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            let image = renderer.nsImage
            XCTAssertNotNil(image, "Snapshot image should not be nil")
            if let rep = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: rep) {
                let width = bitmap.pixelsWide
                let height = bitmap.pixelsHigh
                XCTAssertGreaterThan(width, 0)
                XCTAssertGreaterThan(height, 0)
            }
        } else {
            throw XCTSkip("Requires macOS 13+")
        }
    }
}
#endif
#endif
#endif
