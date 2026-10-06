import XCTest
import UIKit
@testable import Athar

@MainActor final class InteractiveMushafTests: XCTestCase {
    func testAll604ShapedPagesAndActualWordHitRegions() async throws {
        try OriginalMushafCompanion.register()
        let metadata = try OriginalMushafRows.load()
        let url = URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: data).validated()
        try metadata.validate(snapshot)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let fonts = MushafFonts()
        // Start with the acceptance reference and still validate every page.
        for number in [560,603,604] + Array(1...602).filter({ $0 != 560 }) {
            await fonts.load(String(format: "QCF2%03d", number))
            XCTAssertNil(fonts.error, "Page \(number)")
            let page = OriginalPageData.page(number, snapshot: snapshot, rows: metadata, keys: keys)
            let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
            canvas.configure(page: page, corpus: corpus)
            XCTAssertTrue(canvas.renderedSuccessfully, "Page \(number): \(canvas.failureReason ?? "unknown")")
            XCTAssertEqual(canvas.regions.count, page.words.count, "Every logical word maps to its shaped glyph ink")
            XCTAssertNil(canvas.verse(at: CGPoint(x: 0, y: 0)), "Blank page must not select nearest verse")
            for region in canvas.regions {
                XCTAssertEqual(canvas.verse(at: CGPoint(x: region.rect.midX, y: region.rect.midY)), region.verse, "Wrong hit page \(number) record \(region.word)")
            }
            XCTAssertTrue(canvas.headerClearances.allSatisfy { $0 >= 3 }, "Heading clearance page \(number)")
            for row in canvas.rowGeometry {
                XCTAssertGreaterThanOrEqual(row.ink.minX, 0)
                XCTAssertLessThanOrEqual(row.ink.maxX, OriginalMushafCanvas.pageSize.width)
            }
            // Capture every page with the exact native renderer, not a web mockup.
            do {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                    UIColor.systemBackground.setFill(); context.fill(canvas.bounds)
                    canvas.drawInk()
                }
                let attachment = XCTAttachment(image: image); attachment.name = String(format: "QCF-V2-shaped-page-%03d", number); attachment.lifetime = .keepAlways; add(attachment)
                if number == 604, let firstVerse = page.words.first?.verse {
                    let originalRegions = canvas.regions.map(\.rect)
                    let originalPNG = try XCTUnwrap(image.pngData())
                    canvas.hiddenWordIDs = Set(page.words.filter { $0.verse == firstVerse }.map(\.id))
                    let hiddenImage = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                        UIColor.systemBackground.setFill(); context.fill(canvas.bounds); canvas.drawInk()
                    }
                    XCTAssertNotEqual(try XCTUnwrap(hiddenImage.pngData()), originalPNG, "Training must actually suppress target glyphs")
                    XCTAssertEqual(canvas.regions.map(\.rect), originalRegions, "Hiding must not reflow any word or change hit regions")
                    let elements = canvas.accessibilityElements as? [UIAccessibilityElement] ?? []
                    let hiddenElement = try XCTUnwrap(elements.first { $0.accessibilityIdentifier == "reader.verse.\(firstVerse)" })
                    XCTAssertTrue(hiddenElement.accessibilityLabel?.contains("مخفي") == true, "VoiceOver must not reveal hidden verse text")
                    let hiddenAttachment = XCTAttachment(image: hiddenImage); hiddenAttachment.name = "QCF-V2-page-604-training-hidden"; hiddenAttachment.lifetime = .keepAlways; add(hiddenAttachment)
                    canvas.hiddenWordIDs = []
                    let restored = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                        UIColor.systemBackground.setFill(); context.fill(canvas.bounds); canvas.drawInk()
                    }
                    XCTAssertEqual(restored.pngData(), originalPNG, "Revealing restores the exact original rendering")
                    XCTAssertFalse(hiddenElement.accessibilityLabel?.contains("مخفي") == true)
                }
            }
        }
    }
}
