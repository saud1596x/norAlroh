import XCTest
import UIKit
@testable import Athar

@MainActor final class InteractiveMushafTests: XCTestCase {
    func testFittedViewportCentersWholePageAcrossPhoneSizesAndPageResets() {
        // Reading sizes after system safe areas and the two fixed toolbar lanes.
        for size in [CGSize(width: 300, height: 448), CGSize(width: 355, height: 567),
                     CGSize(width: 370, height: 660), CGSize(width: 410, height: 732),
                     CGSize(width: 760, height: 270)] {
            let viewport = OriginalMushafViewport(frame: CGRect(origin: .zero, size: size))
            viewport.layoutIfNeeded()
            for _ in 0..<3 {
                viewport.resetToFittedPage()
                let page = viewport.canvas.convert(viewport.canvas.bounds, to: viewport)
                XCTAssertEqual(page.midX, viewport.bounds.midX, accuracy: 0.5)
                XCTAssertEqual(page.midY, viewport.bounds.midY, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(page.minX, viewport.bounds.minX - 0.5)
                XCTAssertGreaterThanOrEqual(page.minY, viewport.bounds.minY - 0.5)
                XCTAssertLessThanOrEqual(page.maxX, viewport.bounds.maxX + 0.5)
                XCTAssertLessThanOrEqual(page.maxY, viewport.bounds.maxY + 0.5)
                XCTAssertEqual(page.width / page.height, 560.0 / 940.0, accuracy: 0.0001)
                viewport.setZoomScale(viewport.minimumZoomScale * 2, animated: false)
                viewport.setContentOffset(CGPoint(x: 50, y: 80), animated: false)
            }
        }
    }
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
                XCTAssertGreaterThanOrEqual(row.ink.minY, 0)
                XCTAssertLessThanOrEqual(row.ink.maxY, OriginalMushafCanvas.pageSize.height)
            }
            let titles = canvas.rowGeometry.filter { $0.kind == "surah_name" }
            XCTAssertEqual(titles.count, canvas.ornamentBounds.count, "Every title has its own original ornament")
            for (title, ornament) in zip(titles, canvas.ornamentBounds) {
                XCTAssertEqual(title.ink.midX, ornament.midX, accuracy: 0.01, "Title horizontal center on page \(number)")
                XCTAssertEqual(title.ink.midY, ornament.midY, accuracy: 0.01, "Title vertical center on page \(number)")
                XCTAssertTrue(ornament.contains(title.ink), "Full title ink fits on page \(number)")
                XCTAssertLessThanOrEqual(title.ink.height / ornament.height, 0.6401)
                XCTAssertLessThanOrEqual(title.ink.width / ornament.width, 0.4601)
                XCTAssertTrue(canvas.rowGeometry.filter { $0.kind == "ayah" }.allSatisfy {
                    !$0.ink.intersects(ornament)
                }, "Ornament must not cover any vowel or verse on page \(number)")
            }
            let originalRows = canvas.rowGeometry.map(\.ink)
            let originalOrnaments = canvas.ornamentBounds
            canvas.hiddenWordIDs = Set(page.words.map(\.id))
            XCTAssertEqual(canvas.rowGeometry.map(\.ink), originalRows, "All hidden words retain original locations")
            XCTAssertEqual(canvas.ornamentBounds, originalOrnaments, "Training cannot move headings")
            canvas.hiddenWordIDs = []
            // Capture every page with the exact native renderer, not a web mockup.
            do {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
                let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                    UIColor.systemBackground.setFill(); context.fill(canvas.bounds)
                    canvas.drawInk()
                }
                let attachment = XCTAttachment(image: image); attachment.name = String(format: "QCF-V2-shaped-page-%03d", number); attachment.lifetime = .keepAlways; add(attachment)
                if number == 604, let firstVerse = page.words.first?.verse {
                    let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
                    viewport.canvas.configure(page: page, corpus: corpus)
                    viewport.onTurn = { _ in }
                    viewport.layoutIfNeeded()
                    XCTAssertTrue(viewport.canTurnPages, "Fitted page supports swiping")
                    viewport.setZoomScale(viewport.minimumZoomScale * 2, animated: false)
                    XCTAssertFalse(viewport.canTurnPages, "Zoomed swipes must pan instead of flipping pages")
                    let region = try XCTUnwrap(viewport.canvas.regions.first)
                    let point = CGPoint(x: region.rect.midX, y: region.rect.midY)
                    viewport.setContentOffset(CGPoint(x: 30, y: 50), animated: false)
                    let screen = viewport.canvas.convert(point, to: viewport)
                    XCTAssertEqual(viewport.canvas.verse(at: viewport.convert(screen, to: viewport.canvas)), region.verse,
                        "Hit testing uses the same zoom and pan transformation as text")
                    viewport.setZoomScale(viewport.minimumZoomScale, animated: false)
                    XCTAssertTrue(viewport.canTurnPages)
                    let originalRegions = canvas.regions.map(\.rect)
                    let originalPNG = try XCTUnwrap(image.pngData())
                    canvas.hiddenWordIDs = Set(page.words.filter { $0.verse == firstVerse }.map(\.id))
                    let hiddenImage = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                        UIColor.systemBackground.setFill(); context.fill(canvas.bounds); canvas.drawInk()
                    }
                    XCTAssertNotEqual(try XCTUnwrap(hiddenImage.pngData()), originalPNG, "Training must actually suppress target glyphs")
                    XCTAssertEqual(canvas.regions.map(\.rect), originalRegions, "Hiding must not reflow any word or change hit regions")
                    let allowed = canvas.regions.filter { $0.verse == firstVerse }.map { $0.rect.insetBy(dx: -3, dy: -3) }
                    XCTAssertEqual(try changedPixelsOutside(allowed, before: image, after: hiddenImage), 0,
                        "Hidden glyphs must not move or alter any neighbouring text or decorations")
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
    private func changedPixelsOutside(_ regions: [CGRect], before: UIImage, after: UIImage) throws -> Int {
        let a = try XCTUnwrap(before.cgImage), b = try XCTUnwrap(after.cgImage)
        XCTAssertEqual(a.width, b.width); XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bitsPerPixel, 32); XCTAssertEqual(b.bitsPerPixel, 32)
        XCTAssertEqual(a.bytesPerRow, b.bytesPerRow)
        let left = try XCTUnwrap(a.dataProvider?.data), right = try XCTUnwrap(b.dataProvider?.data)
        let lhs = try XCTUnwrap(CFDataGetBytePtr(left)), rhs = try XCTUnwrap(CFDataGetBytePtr(right))
        var changed = 0
        for y in 0..<a.height { for x in 0..<a.width {
            guard !regions.contains(where: { $0.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) }) else { continue }
            let offset = y * a.bytesPerRow + x * 4
            if (0..<4).contains(where: { abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 3 }) { changed += 1 }
        } }
        return changed
    }

}
