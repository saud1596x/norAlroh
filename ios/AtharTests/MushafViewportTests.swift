import XCTest
import UIKit
@testable import Athar

@MainActor final class MushafViewportTests: XCTestCase {
    func testMeasuredReaderInsetsKeepReferenceDefaultsAndFitLargeControls() {
        XCTAssertEqual(MushafReaderInsets.reserved(nil, minimum: 44), 44)
        XCTAssertEqual(MushafReaderInsets.reserved(44, minimum: 44), 44)
        XCTAssertEqual(MushafReaderInsets.reserved(60, minimum: 60), 60)
        XCTAssertEqual(MushafReaderInsets.reserved(.nan, minimum: 44), 44)
        XCTAssertEqual(MushafReaderInsets.reserved(-1, minimum: 60), 60)
        let top = MushafReaderInsets.reserved(96, minimum: 44)
        let bottom = MushafReaderInsets.reserved(84, minimum: 60)
        XCTAssertEqual(top, 96); XCTAssertEqual(bottom, 84)
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: top, width: 370, height: 660 - top - bottom))
        viewport.layoutIfNeeded()
        assertFitted(viewport)
    }
    func testQueuedFailureCannotReplaceNewPageOrRetryGeneration() async {
        let original = UUID()
        let oldPageFailure = MushafRenderIdentity(page: 14, generation: original)
        var currentPage = 14; var generation = original; var failed = false
        let queued = Task { @MainActor in
            if oldPageFailure.isCurrent(page: currentPage, generation: generation) { failed = true }
        }
        currentPage = 15; generation = UUID()
        await queued.value
        XCTAssertFalse(failed, "A delayed failure from page14 cannot hide page15")
        currentPage = 14
        let afterRetry = Task { @MainActor in
            if oldPageFailure.isCurrent(page: currentPage, generation: generation) { failed = true }
        }
        await afterRetry.value
        XCTAssertFalse(failed, "Returning to page14 or retrying it cannot accept its old drawing result")
        let currentFailure = MushafRenderIdentity(page: currentPage, generation: generation)
        XCTAssertTrue(currentFailure.isCurrent(page: currentPage, generation: generation), "A genuine current failure remains reportable")
    }
    func testVerifiedFontRecoveryClearsFailureOnlyAfterSuccessfulRegistration() async throws {
        let fonts = MushafFonts()
        await fonts.load("not-a-page-font")
        XCTAssertNotNil(fonts.error); XCTAssertTrue(fonts.names.isEmpty)
        await fonts.load("still-not-a-page-font")
        XCTAssertNotNil(fonts.error, "An unsuccessful retry must retain the visible error")
        await fonts.load("QCF2001")
        XCTAssertEqual(fonts.names["QCF2001"], "QCF2001")
        XCTAssertNotNil(UIFont(name: "QCF2001", size: 24), "Success uses the actual verified bundled font")
        XCTAssertNil(fonts.error)
        await fonts.load("not-a-page-font")
        XCTAssertNotNil(fonts.error)
        await fonts.load("QCF2001")
        XCTAssertNil(fonts.error, "Returning to a verified cached page must recover the display state")
    }
    func testInitialEntryRetriesAfterReadyPageAndConsumesScopeOnlyOnce() {
        var entry = MushafInitialEntry()
        XCTAssertNil(entry.consume(requestScope: true, startStudy: true, ready: false, visible: true, cancelled: false))
        XCTAssertFalse(entry.consumed, "A failed first load must remain retryable")
        XCTAssertEqual(entry.consume(requestScope: true, startStudy: true, ready: true, visible: true, cancelled: false), .scope)
        XCTAssertNil(entry.consume(requestScope: true, startStudy: true, ready: true, visible: true, cancelled: false),
            "Closing the scope or another retry must not start a second entry or microphone request")
    }
    func testCancelledOrInvisibleInitialEntryCannotStartLateRecitation() {
        var entry = MushafInitialEntry()
        XCTAssertNil(entry.consume(requestScope: false, startStudy: true, ready: true, visible: false, cancelled: false))
        XCTAssertNil(entry.consume(requestScope: false, startStudy: true, ready: true, visible: true, cancelled: true))
        XCTAssertFalse(entry.consumed)
        entry.cancel()
        XCTAssertNil(entry.consume(requestScope: false, startStudy: true, ready: true, visible: true, cancelled: false),
            "A completed load from a dismissed reader must not request microphone access")
        var freshEntry = MushafInitialEntry()
        XCTAssertEqual(freshEntry.consume(requestScope: false, startStudy: true, ready: true, visible: true, cancelled: false), .study)
        XCTAssertNil(freshEntry.consume(requestScope: false, startStudy: true, ready: true, visible: true, cancelled: false))
    }
    func testAuthoredInkAndHeadingAlignmentAtReferencePages() async throws {
        try OriginalMushafCompanion.register()
        let metadata = try OriginalMushafRows.load()
        let url = URL(string: "https://noor-quran-sync.onrender.com/v1/mushaf/snapshot")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: data).validated()
        try metadata.validate(snapshot)
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let fonts = MushafFonts()
        for number in [1, 2, 151, 560, 603, 604] {
            await fonts.load(String(format: "QCF2%03d", number))
            XCTAssertNil(fonts.error, "Font page \(number)")
            let source = OriginalPageData.page(number, snapshot: snapshot, rows: metadata, keys: keys)
            let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
            viewport.canvas.configure(page: source, corpus: corpus)
            viewport.layoutIfNeeded()
            let canvas = viewport.canvas
            XCTAssertTrue(canvas.renderedSuccessfully, canvas.failureReason ?? "Page \(number)")
            let authoredInk = canvas.rowGeometry.map(\.ink)
            let ornaments = canvas.ornamentBounds
            // A selected verse may span several authored lines. Its halo must
            // reach each selected word, and never include adjacent Quran ink.
            let verseKeys = Array(Set(canvas.regions.map(\.verse))).sorted()
            for key in Set([verseKeys.first!, verseKeys[verseKeys.count / 2], verseKeys.last!]) {
                let selectedWords = canvas.regions.filter { $0.verse == key }
                let halo = try XCTUnwrap(canvas.selectionPath(for: key))
                XCTAssertFalse(halo.isEmpty, "Missing selection: page \(number), \(key)")
                let selectedBounds = selectedWords.reduce(CGRect.null) { $0.union($1.rect) }.insetBy(dx: -2.1, dy: -2.1)
                XCTAssertTrue(selectedBounds.contains(halo.boundingBoxOfPath), "Selection must stay close to actual ink")
                for neighbor in canvas.regions where neighbor.verse != key {
                    for path in neighbor.paths where path.boundingBoxOfPath.intersects(halo.boundingBoxOfPath) {
                        XCTAssertTrue(halo.intersection(path).isEmpty, "Selection covers adjacent verse \(neighbor.verse) on page \(number)")
                    }
                }
                canvas.selected = key
                canvas.hiddenWordIDs = Set(selectedWords.map(\.word))
                XCTAssertNil(canvas.selectionPath(for: key), "Training must not reveal a hidden verse through its outline")
                canvas.hiddenWordIDs = []
                XCTAssertNotNil(canvas.selectionPath(for: key))
                canvas.selected = nil
                XCTAssertNil(canvas.selectionPath(for: nil))
                XCTAssertEqual(canvas.rowGeometry.map(\.ink), authoredInk, "Selection must not reflow text")
                XCTAssertEqual(canvas.ornamentBounds, ornaments)
            }
            XCTAssertEqual(ornaments.count, source.rows.filter { $0.type == "surah_name" }.count)
            for row in canvas.rowGeometry {
                let authored = try XCTUnwrap(source.rows.first { $0.line == row.line })
                if authored.centered {
                    XCTAssertEqual(row.ink.midX, OriginalMushafCanvas.pageSize.width / 2,
                                   accuracy: 0.01, "Actual ink center: page \(number), row \(row.line)")
                } else {
                    XCTAssertEqual(row.ink.maxX, OriginalMushafCanvas.pageSize.width - 15,
                                   accuracy: 0.01, "Authored right edge: page \(number), row \(row.line)")
                }
                if row.kind == "surah_name" {
                    let ornament = try XCTUnwrap(ornaments.first { $0.minY <= row.ink.minY && $0.maxY >= row.ink.maxY })
                    XCTAssertEqual(row.ink.midX, ornament.midX, accuracy: 0.01)
                    XCTAssertEqual(row.ink.midY, ornament.midY, accuracy: 0.01)
                    XCTAssertTrue(ornament.contains(row.ink), "Title must fit its original frame")
                }
            }
            // Resizing changes only the viewport's uniform scale, never source ink.
            for size in [CGSize(width: 296, height: 460), CGSize(width: 406, height: 728), CGSize(width: 788, height: 246)] {
                viewport.frame.size = size
                viewport.setNeedsLayout(); viewport.layoutIfNeeded()
                assertFitted(viewport)
                XCTAssertEqual(canvas.transform.b, 0, accuracy: 0.0001, "No rotation or shear")
                XCTAssertEqual(canvas.transform.c, 0, accuracy: 0.0001, "No rotation or shear")
                XCTAssertEqual(canvas.transform.a, canvas.transform.d, accuracy: 0.0001, "No stretching")
                XCTAssertEqual(canvas.rowGeometry.map(\.ink), authoredInk)
                XCTAssertEqual(canvas.ornamentBounds, ornaments)
            }
        }
    }
    func testCompletePageIsCenteredWithoutStretchingAcrossReadingSizes() {
        for size in [CGSize(width: 296, height: 460), CGSize(width: 351, height: 560),
                     CGSize(width: 366, height: 656), CGSize(width: 406, height: 728),
                     CGSize(width: 788, height: 246), CGSize(width: 1000, height: 1140)] {
            let viewport = OriginalMushafViewport(frame: CGRect(origin: .zero, size: size))
            viewport.layoutIfNeeded()
            assertFitted(viewport)
            let offset = viewport.contentOffset
            for _ in 0..<10 { viewport.setNeedsLayout(); viewport.layoutIfNeeded() }
            XCTAssertEqual(viewport.contentOffset, offset, "Layout must not drift")
        }
    }
    func testLargerReadingPreferenceEnlargesWholePageAndRetainsScrollAccess() {
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 370, height: 660))
        viewport.layoutIfNeeded()
        let initial = viewport.zoomScale
        viewport.readingMagnification = 1.15
        viewport.resetToFittedPage()
        XCTAssertEqual(viewport.zoomScale, initial * 1.15, accuracy: 0.001)
        XCTAssertEqual(viewport.canvas.transform.a, viewport.canvas.transform.d, accuracy: 0.001)
        XCTAssertGreaterThan(viewport.canvas.frame.height, viewport.bounds.height)
        viewport.setContentOffset(CGPoint(x: 0, y: viewport.canvas.frame.height - viewport.bounds.height), animated: false)
        XCTAssertGreaterThan(viewport.contentOffset.y, 0)
        viewport.readingMagnification = 1
        viewport.resetToFittedPage()
        assertFitted(viewport)
    }
    func testTurningAfterZoomAndPanRestoresCenteredPage() {
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
        viewport.layoutIfNeeded()
        viewport.setZoomScale(viewport.minimumZoomScale * 2, animated: false)
        viewport.setContentOffset(CGPoint(x: 70, y: 120), animated: false)
        viewport.resetToFittedPage()
        assertFitted(viewport)
    }
    func testResizingRefitsAndPreservesRelativeZoom() {
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
        viewport.layoutIfNeeded()
        viewport.frame.size = CGSize(width: 760, height: 260)
        viewport.setNeedsLayout(); viewport.layoutIfNeeded()
        assertFitted(viewport)
        viewport.setZoomScale(viewport.minimumZoomScale * 2, animated: false)
        viewport.frame.size = CGSize(width: 406, height: 728)
        viewport.setNeedsLayout(); viewport.layoutIfNeeded()
        XCTAssertEqual(viewport.zoomScale / viewport.minimumZoomScale, 2, accuracy: 0.001)
        viewport.resetToFittedPage()
        assertFitted(viewport)
    }
    private func assertFitted(_ viewport: OriginalMushafViewport, file: StaticString = #filePath, line: UInt = #line) {
        let page = viewport.canvas.convert(viewport.canvas.bounds, to: viewport)
        XCTAssertEqual(page.midX, viewport.bounds.midX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(page.midY, viewport.bounds.midY, accuracy: 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(page.minX, viewport.bounds.minX - 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(page.minY, viewport.bounds.minY - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(page.maxX, viewport.bounds.maxX + 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(page.maxY, viewport.bounds.maxY + 0.5, file: file, line: line)
        XCTAssertEqual(page.width / page.height, 560.0 / 940.0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(viewport.contentInsetAdjustmentBehavior, .never, file: file, line: line)
        XCTAssertEqual(viewport.contentOffset.x, -viewport.contentInset.left, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(viewport.contentOffset.y, -viewport.contentInset.top, accuracy: 0.5, file: file, line: line)
    }
}
