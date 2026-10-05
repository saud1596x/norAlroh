import XCTest
import UIKit
import CoreText
@testable import Athar

final class MushafTypesettingTests: XCTestCase {
    func testShortLineSpacingIsBoundedRatherThanExpandedToScreenWidth() {
        XCTAssertEqual(MushafTypesetter.justificationWidth(advance: 100, available: 360), 114, accuracy: 0.001)
        XCTAssertEqual(MushafTypesetter.justificationWidth(advance: 350, available: 360), 360, accuracy: 0.001)
    }
    @MainActor func testAll604PagesFitInkBoundsAtPhoneAndTabletWidths() throws {
        let database = try XCTUnwrap(MushafDatabase.shared)
        let bundle = Bundle.main
        var names: [String: String] = [:]
        for family in Set(database.pages.map(\.font)).union(["MushafHeader"]) {
            let resource = family == "MushafHeader" ? "QCF_SurahHeader_COLOR-Regular" : family + "_W"
            guard let url = bundle.url(forResource: resource, withExtension: "ttf") else {
                throw XCTSkip("Licensed offline fonts must be installed to run native glyph layout validation.")
            }
            let bytes = try Data(contentsOf: url)
            XCTAssertTrue(QuranResources.verified(bytes, resource: resource + ".ttf"))
            let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
            let font = try XCTUnwrap(CGFont(provider)); CTFontManagerRegisterGraphicsFont(font, nil)
            names[family] = try XCTUnwrap(font.postScriptName) as String
        }
        for page in database.pages {
            let rows = page.page <= 2 ? 8 : 15
            for row in 1...rows {
                let layout = page.layout[String(row)]
                let words = page.words.filter { $0.line == row }
                let text: String; let family: String
                if let chapter = layout?.chapter {
                    text = String(try XCTUnwrap(UnicodeScalar(MushafDatabase.headers[chapter - 1]))); family = "MushafHeader"
                } else if layout?.type == "bismillah" { text = layout?.code ?? ""; family = "QCF4_Hafs_01" }
                else { text = words.map(\.code).joined(separator: " "); family = page.font }
                if text.isEmpty { continue }
                for width: CGFloat in [296, 366, 640] {
                    let bounds = CGRect(x: 0, y: 0, width: width, height: width * (page.page <= 2 ? 0.145 : 0.112))
                    let size: CGFloat = layout?.type == "header" ? 105 : layout?.type == "bismillah" ? 21 : width * 0.115
                    let result = try XCTUnwrap(MushafTypesetter.make(text: text, fontName: try XCTUnwrap(names[family]),
                        size: size, bounds: bounds, justify: page.page > 2 && layout == nil), "Page \(page.page), line \(row)")
                    XCTAssertTrue(bounds.insetBy(dx: -0.1, dy: -0.1).contains(result.inkBounds), "Clipped glyph on page \(page.page), line \(row)")
                    if words.count > 1 {
                        let first = CTLineGetOffsetForStringIndex(result.line, 0, nil)
                        let last = CTLineGetOffsetForStringIndex(result.line, (text as NSString).length - 1, nil)
                        XCTAssertGreaterThan(first, last, "Incorrect RTL glyph order on page \(page.page), line \(row)")
                    }
                }
            }
        }
    }
}
