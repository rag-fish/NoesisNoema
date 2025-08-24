// filepath: NoesisNoema/Tests/CitationPopoverSnapshotTests/CitationPopoverSnapshotTests_iOS.swift
// Comments: English

#if os(iOS)
import XCTest
import SwiftUI
@testable import NoesisNoema

final class CitationPopoverSnapshotTests_iOS: XCTestCase {
    func testSnapshotRendersNonEmptyImage_iOS() throws {
        if #available(iOS 16.0, *) {
            let cat = [
                CitationInfo(index: 1, title: "Ethics", path: "https://example.com/ethics.pdf", page: 12),
                CitationInfo(index: 2, title: "Letters", path: nil, page: nil)
            ]
            let per = [[1,2], [2]]
            let view = CitationPopoverView(citations: ParagraphCitations(perParagraph: per, catalog: cat))
                .frame(width: 380, height: 260)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            let image = renderer.uiImage
            XCTAssertNotNil(image, "Snapshot image should not be nil")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
            XCTAssertGreaterThan(image?.size.height ?? 0, 0)
        } else {
            throw XCTSkip("Requires iOS 16+")
        }
    }
}
#endif
