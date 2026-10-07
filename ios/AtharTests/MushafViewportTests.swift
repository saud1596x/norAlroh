import XCTest
import UIKit
@testable import Athar

@MainActor final class MushafViewportTests: XCTestCase {
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
