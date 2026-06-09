import XCTest
import SwiftUI
import UIKit
@testable import Echo

final class DominantColorExtractorTests: XCTestCase {

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 16, height: 16)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testVividCoverYieldsNonNilAccentAndThreeColorBackground() {
        let palette = DominantColorExtractor.extractPalette(from: solidImage(.systemRed))
        XCTAssertNotNil(palette.rawAccent)
        XCTAssertEqual(palette.background.count, 3)
        XCTAssertFalse(palette.candidates.isEmpty)
    }

    func testGreyscaleCoverYieldsNilAccent() {
        let palette = DominantColorExtractor.extractPalette(from: solidImage(.gray))
        XCTAssertNil(palette.rawAccent)
        XCTAssertTrue(palette.candidates.isEmpty)
    }

    func testExtractColorsReturnsRequestedCount() {
        let colors = DominantColorExtractor.extractColors(from: solidImage(.systemBlue), count: 3)
        XCTAssertEqual(colors.count, 3)
    }

    func testExistingExtractAPIStillWorks() {
        let accent = DominantColorExtractor.extract(from: solidImage(.systemOrange))
        XCTAssertNotNil(accent)
    }

    func testGreyscaleReturnsNilFromExtract() {
        let accent = DominantColorExtractor.extract(from: solidImage(.gray))
        XCTAssertNil(accent)
    }
}
