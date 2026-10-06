import XCTest
import UIKit
import CryptoKit
@testable import Athar

final class MushafArtworkTests: XCTestCase {
    func testCompletePageFitsUniformlyInPortraitLandscapeAndTablet() {
        let page = CGSize(width: 345, height: 550)
        for viewport in [CGRect(x: 0, y: 0, width: 390, height: 650),
                         CGRect(x: 0, y: 0, width: 760, height: 260),
                         CGRect(x: 0, y: 0, width: 810, height: 1000)] {
            let transform = MushafPageTransform(pageSize: page, viewport: viewport)
            XCTAssertTrue(viewport.contains(transform.frame))
            XCTAssertEqual(transform.frame.width / page.width, transform.frame.height / page.height, accuracy: 0.00001)
            let original = CGPoint(x: 173, y: 414)
            let screen = CGPoint(x: original.x * transform.scale + transform.origin.x, y: original.y * transform.scale + transform.origin.y)
            let recovered = transform.pagePoint(screen)!
            XCTAssertEqual(recovered.x, original.x, accuracy: 0.00001)
            XCTAssertEqual(recovered.y, original.y, accuracy: 0.00001)
        }
    }
    func testSelectionAcrossThreeLinesDoesNotSelectNeighborOrTheGap() {
        let a = MushafArtworkManifest.Region(verseKey: "2:7", polygons: [
            rectangle(220, 10, 110, 30), rectangle(10, 50, 320, 30), rectangle(10, 90, 90, 30)])
        let b = MushafArtworkManifest.Region(verseKey: "2:8", polygons: [rectangle(100, 90, 230, 30)])
        let regions = [a, b]
        XCTAssertEqual(MushafArtworkGeometry.verse(at: CGPoint(x: 250, y: 20), regions: regions), "2:7")
        XCTAssertEqual(MushafArtworkGeometry.verse(at: CGPoint(x: 160, y: 65), regions: regions), "2:7")
        XCTAssertEqual(MushafArtworkGeometry.verse(at: CGPoint(x: 30, y: 105), regions: regions), "2:7")
        XCTAssertEqual(MushafArtworkGeometry.verse(at: CGPoint(x: 160, y: 105), regions: regions), "2:8")
        XCTAssertNil(MushafArtworkGeometry.verse(at: CGPoint(x: 160, y: 40), regions: regions))
        XCTAssertNil(MushafArtworkGeometry.verse(at: CGPoint(x: 100, y: 20), regions: regions))
    }
    func testMissingApprovalCannotActivateEvenACompleteManifest() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let manifest = fixtureManifest(corpus: corpus, status: "AWAITING_MATCHING_ASSETS")
        XCTAssertNoThrow(try manifest.validated(corpus: corpus, requireApproval: false))
        XCTAssertThrowsError(try manifest.validated(corpus: corpus))
    }
    func testMissingPageWrongVerseOrderAndOutsideCoordinatesAreRejected() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let original = fixtureManifest(corpus: corpus, status: "APPROVED_MATCHING_REFERENCE")
        XCTAssertNoThrow(try original.validated(corpus: corpus))
        XCTAssertThrowsError(try replacing(original, pages: Array(original.pages.dropLast())).validated(corpus: corpus))
        var pages = original.pages
        let page = pages[0]
        var regions = page.regions; regions.swapAt(0, 1)
        pages[0] = .init(number: page.number, width: page.width, height: page.height, file: page.file, sha256: page.sha256, regions: regions)
        XCTAssertThrowsError(try replacing(original, pages: pages).validated(corpus: corpus))
        pages = original.pages
        regions = page.regions
        regions[0] = .init(verseKey: regions[0].verseKey, polygons: [rectangle(-1, 0, 10, 10)])
        pages[0] = .init(number: page.number, width: page.width, height: page.height, file: page.file, sha256: page.sha256, regions: regions)
        XCTAssertThrowsError(try replacing(original, pages: pages).validated(corpus: corpus))
    }
    @MainActor func testOriginalPublisherPDFIsCompleteAndNativeCanvasMatchesDirectPDFRendering() async throws {
        guard Bundle.main.url(forResource: "king-fahd-standard39-2", withExtension: "pdf") != nil else {
            throw XCTSkip("Install the pinned publisher PDF using the preparation script")
        }
        let corpus = try XCTUnwrap(QuranResources.corpus)
        guard case .ready(let library) = await MushafArtworkLibrary.installed(corpus: corpus) else {
            return XCTFail("Pinned original PDF rejected")
        }
        XCTAssertEqual(library.manifest.pages.map(\.number), Array(1...604))
        XCTAssertEqual(library.chapterStartPages.count, 114)
        XCTAssertEqual(library.chapterStartPages[71], 572)
        XCTAssertEqual(Array(library.chapterStartPages.suffix(3)), [604, 604, 604])
        for number in 1...604 {
            let artwork = try library.artwork(number: number)
            XCTAssertEqual(artwork.document.numberOfPages, 640)
            XCTAssertTrue(artwork.metadata.regions.isEmpty, "Never borrow coordinates from another edition")
        }
        for number in [1, 2, 3, 151, 572, 598, 604] {
            let artwork = try library.artwork(number: number)
            let size = CGSize(width: artwork.metadata.width, height: artwork.metadata.height)
            let canvas = MushafArtworkCanvas(frame: CGRect(origin: .zero, size: size))
            canvas.artwork = artwork
            let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let actual = renderer.image { _ in canvas.draw(canvas.bounds) }
            let reference = renderer.image { output in
                let context = output.cgContext
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
                context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
                context.drawPDFPage(artwork.page)
            }
            XCTAssertTrue(canvas.renderedSuccessfully)
            XCTAssertEqual(actual.pngData(), reference.pngData(), "Original page pixel output changed: \(number)")
            let attachment = XCTAttachment(image: actual)
            attachment.name = String(format: "KFGQPC-original-native-page-%03d", number)
            attachment.lifetime = .keepAlways; add(attachment)
            let viewport = MushafArtworkViewport(frame: CGRect(x: 0, y: 0, width: 430, height: 740))
            viewport.set(artwork: artwork, corpus: corpus, selected: nil, onSelect: { _ in }, onToggleTools: {})
            viewport.layoutIfNeeded()
            XCTAssertTrue(viewport.bounds.contains(viewport.canvas.convert(viewport.canvas.bounds, to: viewport)))
        }
    }
    @MainActor func testProductionCanvasDrawsAnUnchangedVectorPageAndSelectionOverlay() throws {
        // NON-QURAN geometry fixture, not an after screenshot or Mushaf evidence.
        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes as CFMutableData) else { return XCTFail("PDF consumer") }
        var box = CGRect(x: 0, y: 0, width: 345, height: 550)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 20, y: 500, width: 305, height: 3))
        context.fill(CGRect(x: 100, y: 100, width: 145, height: 3))
        context.endPDFPage(); context.closePDF()
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let pdf = try XCTUnwrap(document.page(at: 1))
        let page = MushafArtworkManifest.Page(number: 1, width: 345, height: 550,
            file: "mushaf-artwork-001.pdf", sha256: String(repeating: "0", count: 64),
            regions: [.init(verseKey: "1:1", polygons: [rectangle(20, 30, 305, 30)])])
        let artwork = MushafArtworkLibrary.Artwork(metadata: page, document: document, page: pdf)
        let canvas = MushafArtworkCanvas(frame: CGRect(x: 0, y: 0, width: 345, height: 550))
        canvas.artwork = artwork; canvas.selected = "1:1"
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { _ in canvas.draw(canvas.bounds) }
        XCTAssertTrue(canvas.renderedSuccessfully)
        XCTAssertEqual(image.size, canvas.bounds.size)
        let attachment = XCTAttachment(image: image); attachment.name = "NON-QURAN-vector-geometry-fixture"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [MushafArtworkManifest.Point] {
        [.init(x: x, y: y), .init(x: x + w, y: y), .init(x: x + w, y: y + h), .init(x: x, y: y + h)]
    }
    private func fixtureManifest(corpus: [Surah], status: String) -> MushafArtworkManifest {
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let pages = (1...604).map { number -> MushafArtworkManifest.Page in
            let from = (number - 1) * keys.count / 604
            let to = number * keys.count / 604
            let regions = keys[from..<to].enumerated().map { index, key in
                MushafArtworkManifest.Region(verseKey: key, polygons: [rectangle(10, Double(index) * 35, 320, 30)])
            }
            return .init(number: number, width: 345, height: 550, file: String(format: "mushaf-artwork-%03d.pdf", number),
                sha256: String(repeating: "0", count: 64), regions: regions)
        }
        return .init(schema: 1, edition: "NON-QURAN TEST FIXTURE", sourceURL: "https://example.invalid/fixture",
            sourceRevision: "test", rightsRecord: "fixture only", reviewStatus: status,
            reviewedReferencePages: [1, 2, 3, 151, 604], pages: pages)
    }
    private func replacing(_ manifest: MushafArtworkManifest, pages: [MushafArtworkManifest.Page]) -> MushafArtworkManifest {
        .init(schema: manifest.schema, edition: manifest.edition, sourceURL: manifest.sourceURL,
            sourceRevision: manifest.sourceRevision, rightsRecord: manifest.rightsRecord,
            reviewStatus: manifest.reviewStatus, reviewedReferencePages: manifest.reviewedReferencePages, pages: pages)
    }
}
