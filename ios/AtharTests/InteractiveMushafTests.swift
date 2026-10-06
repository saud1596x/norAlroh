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
        for number in 1...604 {
            await fonts.load(String(format: "QCF2%03d", number))
            XCTAssertNil(fonts.error, "Page \(number)")
            let page = OriginalPageData.page(number, snapshot: snapshot, rows: metadata, keys: keys)
            let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
            canvas.configure(page: page, corpus: corpus)
            XCTAssertTrue(canvas.renderedSuccessfully, "Font, bounds, or glyph failure page \(number)")
            XCTAssertEqual(canvas.regions.count, page.words.count, "Every logical word maps to its shaped glyph ink")
            XCTAssertNil(canvas.verse(at: CGPoint(x: 0, y: 0)), "Blank page must not select nearest verse")
            for region in canvas.regions {
                XCTAssertEqual(canvas.verse(at: CGPoint(x: region.rect.midX, y: region.rect.midY)), region.verse, "Wrong hit page \(number) record \(region.word)")
            }
            if [1,2,3,64,151,572,598,604].contains(number) {
                let image = UIGraphicsImageRenderer(size: canvas.bounds.size).image { context in
                    UIColor.systemBackground.setFill(); context.fill(canvas.bounds)
                    canvas.drawInk()
                }
                let attachment = XCTAttachment(image: image); attachment.name = String(format: "QCF-V2-shaped-page-%03d", number); attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
