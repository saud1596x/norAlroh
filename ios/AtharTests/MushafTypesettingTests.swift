import XCTest
import UIKit
import CoreText
@testable import Athar

final class MushafTypesettingTests: XCTestCase {
    func testShortLineSpacingIsBoundedRatherThanExpandedToScreenWidth() {
        XCTAssertEqual(MushafTypesetter.justificationWidth(advance: 100, available: 360), 114, accuracy: 0.001)
        XCTAssertEqual(MushafTypesetter.justificationWidth(advance: 350, available: 360), 360, accuracy: 0.001)
    }
    @MainActor func testAll604PagesFitInkBoundsAtPhoneAndTabletWidths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = QCFV2ContentCache(file: directory.appendingPathComponent("snapshot.json"),
            endpoint: URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!)
        let entry = try await cache.refresh()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: entry.snapshot)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let database = try QCFV2PageLayout.database(snapshot: snapshot, corpus: corpus)
        XCTAssertTrue(QuranTypography.available)
        let fonts = MushafFonts()
        for page in database.pages {
            await fonts.load(page: page)
            XCTAssertNil(fonts.error, "The bundled font for page \(page.page) must be present and hash verified")
            let bodyName = try XCTUnwrap(fonts.names[page.font])
            let rows = page.page <= 2 ? 8 : 15
            for row in 1...rows {
                let layout = page.layout[String(row)]
                let words = page.words.filter { $0.line == row }
                let text: String; let name: String
                if layout?.type == "header", let chapter = layout?.chapter {
                    text = corpus[chapter - 1].name; name = QuranTypography.postScriptName
                } else if layout?.type == "bismillah" {
                    text = layout?.code ?? ""; name = QuranTypography.postScriptName
                } else { text = words.map(\.code).joined(separator: " "); name = bodyName }
                if text.isEmpty { continue }
                for width: CGFloat in [296, 366, 640] {
                    let bounds = CGRect(x: 0, y: 0, width: width, height: width * (page.page <= 2 ? 0.145 : 0.112))
                    let size: CGFloat = layout?.type == "header" ? width * 0.07 : layout?.type == "bismillah" ? 21 : width * 0.115
                    let result = try XCTUnwrap(MushafTypesetter.make(text: text, fontName: name,
                        size: size, bounds: bounds, justify: page.page > 2 && layout == nil), "Page \(page.page), line \(row)")
                    XCTAssertTrue(bounds.insetBy(dx: -0.1, dy: -0.1).contains(result.inkBounds), "Clipped glyph on page \(page.page), line \(row)")
                    XCTAssertTrue(MushafTypesetter.usesExpectedFont(result.line, postScriptName: name, text: text))
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
