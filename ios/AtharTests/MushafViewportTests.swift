import XCTest
import UIKit
@testable import Athar

@MainActor final class MushafViewportTests: XCTestCase {
    func testPlaybackLockCancelsManualDragButAllowsAutomaticPageReplacement() async throws {
        try OriginalMushafCompanion.register()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        let rows = try OriginalMushafRows.load(), fonts = MushafFonts()
        await fonts.load("QCF2003")
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
        viewport.canvas.configure(page: .page(3, snapshot: snapshot, rows: rows, keys: keys), corpus: corpus)
        viewport.onTurn = { _ in XCTFail("Playback must reject manual page commits") }
        viewport.layoutIfNeeded()
        XCTAssertTrue(viewport.canTurnPages)
        viewport.canvas.layer.sublayerTransform = CATransform3DMakeTranslation(100, 0, 0)
        viewport.allowsManualPageTurns = false
        XCTAssertFalse(viewport.canTurnPages)
        XCTAssertTrue(CATransform3DIsIdentity(viewport.canvas.layer.sublayerTransform))
        // This is the same replacement path used by accepted playback timing.
        viewport.replacePage(number: 4, animated: false) { viewport.resetToFittedPage() }
        XCTAssertEqual(viewport.pageNumber, 4)
        XCTAssertFalse(viewport.canTurnPages)
        viewport.allowsManualPageTurns = true
        XCTAssertTrue(viewport.canTurnPages, "Stopping playback restores manual navigation")
    }
    func testPreparingNeighborFontsPreservesVisiblePageErrorAndPreparesBothDirections() async {
        let fonts = MushafFonts()
        await fonts.load("invalid-current-font")
        let originalError = fonts.error
        await fonts.prepareNeighbors(of: 2)
        XCTAssertEqual(fonts.error, originalError)
        XCTAssertEqual(fonts.names["QCF2001"], "QCF2001")
        XCTAssertEqual(fonts.names["QCF2003"], "QCF2003")
        await fonts.load("QCF2003")
        XCTAssertNil(fonts.error)
    }
    func testNonAnimatedReplacementClearsDraggedTransformAndKeepsPageCentered() {
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
        viewport.layoutIfNeeded()
        viewport.canvas.layer.sublayerTransform = CATransform3DMakeTranslation(120, 0, 0)
        viewport.replacePage(number: 3, animated: false) { viewport.resetToFittedPage() }
        XCTAssertEqual(viewport.pageNumber, 3)
        XCTAssertFalse(viewport.turningPage)
        XCTAssertTrue(CATransform3DIsIdentity(viewport.canvas.layer.sublayerTransform))
        assertFitted(viewport)
    }
    func testMeasuredReaderInsetsKeepReferenceDefaultsAndFitLargeControls() {
        XCTAssertEqual(MushafReaderInsets.reserved(96, minimum: 44, visible: false), 96)
        XCTAssertEqual(MushafReaderInsets.reserved(120, minimum: 60, visible: false), 120,
                       "An ordinary toolbar toggle must preserve the reading frame")
        XCTAssertEqual(MushafReaderInsets.reserved(96, minimum: 44, visible: false, fullScreen: true), 0,
                       "Only the explicit full-screen mode changes the reading frame")
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
        let data = try XCTUnwrap(QCFV2ContentCache.bundledSnapshot())
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
            let firstWord = try XCTUnwrap(canvas.regions.first)
            canvas.activeWordID = firstWord.word
            XCTAssertNotNil(canvas.activeWordPath())
            canvas.hiddenWordIDs = [firstWord.word]
            XCTAssertNil(canvas.activeWordPath(), "Word tracking must never reveal hidden Quran text")
            canvas.hiddenWordIDs = []; canvas.activeWordID = Int.max
            XCTAssertNil(canvas.activeWordPath(), "A word from another page cannot be highlighted here")
            canvas.activeWordID = nil
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
    func testShortTapOnlyTogglesToolsAndNeverSelectsVerse() throws {
        let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
        var toggles = 0
        viewport.onToggleTools = { toggles += 1 }
        viewport.canvas.onVerse = { _ in XCTFail("Verse selection belongs to long press or accessibility") }
        viewport.handleShortTap()
        XCTAssertEqual(toggles, 1)
        viewport.allowsVerseSelection = false
        viewport.handleShortTap()
        XCTAssertEqual(toggles, 2, "Tools remain available when verse selection is disabled")
        viewport.onToggleTools = nil
        viewport.handleShortTap()
        XCTAssertEqual(toggles, 2, "A missing tools callback must not fall back to selecting a verse")
        let namedSelections = (viewport.gestureRecognizers ?? []).filter { $0.name == "noor.mushaf.verse-selection" }
        XCTAssertEqual(namedSelections.count, 1, "The verse-selection recognizer must have a unique stable name")
        let selection = try XCTUnwrap(namedSelections.first as? UILongPressGestureRecognizer)
        XCTAssertEqual(selection.minimumPressDuration, 0.4)
        XCTAssertEqual(selection.allowableMovement, 10)
    }
    func testTajweedKeepsSourceHeadingAndBasmalaCoordinates() async throws {
        try OriginalMushafCompanion.register()
        let metadata = try OriginalMushafRows.load()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let fonts = MushafFonts()
        // Opening templates, a surah beginning, and the final multi-surah face.
        for number in [1, 2, 177, 604] {
            await fonts.load(String(format: "QCF2%03d", number))
            let source = OriginalPageData.page(number, snapshot: snapshot, rows: metadata, keys: keys)
            let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
            canvas.configure(page: source, corpus: corpus)
            XCTAssertTrue(canvas.renderedSuccessfully, canvas.failureReason ?? "Page \(number)")
            let original = canvas.rowGeometry.filter { $0.kind != "ayah" }.map(\.ink)
            let ornaments = canvas.ornamentBounds
            XCTAssertFalse(original.isEmpty)
            canvas.tajweedEnabled = true
            canvas.configure(page: source, corpus: corpus)
            XCTAssertTrue(canvas.renderedSuccessfully, canvas.failureReason ?? "Tajweed page \(number)")
            XCTAssertEqual(canvas.rowGeometry.filter { $0.kind != "ayah" }.map(\.ink), original,
                           "Tajweed changes the painted source outlines, never heading anchors")
            XCTAssertEqual(canvas.ornamentBounds, ornaments)
            for ornament in canvas.ornamentBounds {
                XCTAssertTrue(canvas.rowGeometry.filter { $0.kind == "ayah" }.allSatisfy { !$0.ink.intersects(ornament) },
                              "Fixed source headings must also clear actual Tajweed ink on page \(number)")
            }
            canvas.tajweedEnabled = false
            canvas.configure(page: source, corpus: corpus)
            XCTAssertEqual(canvas.rowGeometry.filter { $0.kind != "ayah" }.map(\.ink), original)
        }
    }
    func testDarkNativeTitleAndBasmalaUseViewTraitsInsideLightDrawingHost() async throws {
        try OriginalMushafCompanion.register()
        let metadata = try OriginalMushafRows.load()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let fonts = MushafFonts()
        await fonts.load("QCF2604")
        let source = OriginalPageData.page(604, snapshot: snapshot, rows: metadata, keys: keys)
        for tajweed in [false, true] {
            let canvas = OriginalMushafCanvas(frame: CGRect(origin: .zero, size: OriginalMushafCanvas.pageSize))
            canvas.overrideUserInterfaceStyle = .dark
            // A detached view does not receive an automatic layout pass before
            // this direct configure/draw path. Update its real UIKit traits.
            canvas.updateTraitsIfNeeded()
            canvas.tajweedEnabled = tajweed
            var captured: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                canvas.configure(page: source, corpus: corpus)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                captured = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                    UIColor.black.setFill(); context.fill(canvas.bounds)
                    canvas.drawInk()
                }
            }
            XCTAssertTrue(canvas.renderedSuccessfully, canvas.failureReason ?? "Dark page 604")
            let image = try XCTUnwrap(captured?.cgImage)
            let headers = canvas.rowGeometry.filter { $0.kind != "ayah" }
            XCTAssertEqual(headers.count, 6)
            for row in headers {
                let crop = try XCTUnwrap(image.cropping(to: row.ink.integral))
                XCTAssertGreaterThan(try brightOpaquePixels(crop), 10,
                                     "Dark \(row.kind) on row \(row.line) must remain visible even with light ambient traits")
            }
        }
    }
    func testDetachedViewportAppliesRequestedAppearanceBeforeShapingAndRefreshesColors() async throws {
        try OriginalMushafCompanion.register()
        let metadata = try OriginalMushafRows.load()
        let snapshot = try JSONDecoder().decode(QCFV2Snapshot.self, from: XCTUnwrap(QCFV2ContentCache.bundledSnapshot())).validated()
        let corpus = try XCTUnwrap(QuranResources.corpus)
        let keys = corpus.flatMap { surah in surah.ayahs.map { "\(surah.number):\($0.number)" } }
        let fonts = MushafFonts()
        await fonts.load("QCF2604")
        let source = OriginalPageData.page(604, snapshot: snapshot, rows: metadata, keys: keys)
        for tajweed in [false, true] {
            let viewport = OriginalMushafViewport(frame: CGRect(x: 0, y: 0, width: 366, height: 656))
            let canvas = viewport.canvas
            XCTAssertNil(viewport.window, "Exercise first configuration before window inheritance")
            viewport.overrideUserInterfaceStyle = .dark
            canvas.overrideUserInterfaceStyle = .light
            canvas.tajweedEnabled = tajweed
            var originalGeometry: [CGRect]?
            for (index, style) in [UIUserInterfaceStyle.dark, .dark, .light, .dark].enumerated() {
                let before = canvas.shapingPasses
                // This exact boundary is called by makeUIView/updateUIView
                // before reading the coordinator or constructing any CTLine.
                viewport.applyAppearance(style)
                XCTAssertNil(viewport.window)
                XCTAssertEqual(viewport.overrideUserInterfaceStyle, style)
                XCTAssertEqual(canvas.overrideUserInterfaceStyle, style)
                XCTAssertEqual(viewport.traitCollection.userInterfaceStyle, style)
                XCTAssertEqual(canvas.traitCollection.userInterfaceStyle, style)
                canvas.configure(page: source, corpus: corpus)
                XCTAssertTrue(canvas.renderedSuccessfully, canvas.failureReason ?? "Detached appearance")
                XCTAssertEqual(canvas.shapingPasses, before + (index == 1 ? 0 : 1),
                    "A changed appearance must configure its resolved colors; an unchanged one must reuse its page")
                let geometry = canvas.rowGeometry.map(\.ink)
                if let originalGeometry { XCTAssertEqual(geometry, originalGeometry, "Appearance must not change page geometry") }
                else { originalGeometry = geometry }
                var captured: UIImage?
                let opposite = UITraitCollection(userInterfaceStyle: style == .dark ? .light : .dark)
                opposite.performAsCurrent {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                    captured = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                        (style == .dark ? UIColor.black : .white).setFill(); context.fill(canvas.bounds)
                        canvas.drawInk()
                    }
                }
                let image = try XCTUnwrap(captured?.cgImage)
                var inkBounds = canvas.rowGeometry.filter { $0.kind != "ayah" }.map(\.ink)
                let firstVerse = try XCTUnwrap(source.words.first?.verse)
                inkBounds.append(canvas.regions.filter { $0.verse == firstVerse }.reduce(CGRect.null) { $0.union($1.rect) })
                for bounds in inkBounds {
                    let crop = try XCTUnwrap(image.cropping(to: bounds.integral))
                    XCTAssertGreaterThan(try brightOpaquePixels(crop, foregroundIsDark: style == .light), 10,
                        "Detached V\(tajweed ? 4 : 2) style \(style.rawValue) must paint contrasting header and ordinary Quran ink")
                }
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
    private func brightOpaquePixels(_ image: CGImage, foregroundIsDark: Bool = false) throws -> Int {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let bitmap = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap))
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return stride(from: 0, to: bytes.count, by: 4).filter {
            let contrasting = foregroundIsDark
                ? bytes[$0] < 75 && bytes[$0 + 1] < 75 && bytes[$0 + 2] < 75
                : bytes[$0] > 180 && bytes[$0 + 1] > 180 && bytes[$0 + 2] > 180
            return contrasting && bytes[$0 + 3] > 230
        }.count
    }
}
