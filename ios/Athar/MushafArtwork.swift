import Foundation
import CoreGraphics
import CryptoKit

/// One edition, one coordinate system. Artwork and hit regions are inseparable.
/// No word spacing, shaping, line fitting or font substitution happens here.
struct MushafArtworkManifest: Codable {
    let schema: Int
    let edition: String
    let sourceURL: String
    let sourceRevision: String
    let rightsRecord: String
    let reviewStatus: String
    let reviewedReferencePages: [Int]
    let pages: [Page]

    struct Point: Codable { let x: Double; let y: Double }
    struct Region: Codable {
        let verseKey: String
        // Separate polygons for separate printed lines. Never union their boxes.
        let polygons: [[Point]]
    }
    struct Page: Codable {
        let number: Int
        let width: Double
        let height: Double
        let file: String
        let sha256: String
        let regions: [Region]
    }
    enum Invalid: Error { case metadata, approval, page, verse, region, hash, artwork }

    func validated(corpus: [Surah], requireApproval: Bool = true) throws -> Self {
        guard schema == 1, !edition.isEmpty, URL(string: sourceURL)?.scheme == "https",
              !sourceRevision.isEmpty, !rightsRecord.isEmpty else { throw Invalid.metadata }
        guard !requireApproval || (reviewStatus == "APPROVED_MATCHING_REFERENCE"
            && Set([1, 2, 3, 151, 604]).isSubset(of: Set(reviewedReferencePages))) else { throw Invalid.approval }
        guard pages.map(\.number) == Array(1...604) else { throw Invalid.page }
        let orderedKeys = corpus.flatMap { s in s.ayahs.map { "\(s.number):\($0.number)" } }
        guard corpus.map(\.number) == Array(1...114), orderedKeys.count == 6236 else { throw Invalid.verse }
        let canonical = Set(orderedKeys)
        var seen: [String] = []
        var previous: String?
        for page in pages {
            guard page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0,
                  page.width <= 10000, page.height <= 10000,
                  page.file == String(format: "mushaf-artwork-%03d.pdf", page.number),
                  page.sha256.count == 64, page.sha256.allSatisfy({ $0.isHexDigit }),
                  !page.regions.isEmpty, Set(page.regions.map(\.verseKey)).count == page.regions.count else { throw Invalid.page }
            for region in page.regions {
                guard canonical.contains(region.verseKey), !region.polygons.isEmpty else { throw Invalid.verse }
                for polygon in region.polygons {
                    guard (3...512).contains(polygon.count), polygon.allSatisfy({
                        $0.x.isFinite && $0.y.isFinite && (0...page.width).contains($0.x) && (0...page.height).contains($0.y)
                    }), abs(Self.signedArea(polygon)) > 0.01 else { throw Invalid.region }
                }
                // A verse can continue on the next page, but cannot reappear later.
                if previous != region.verseKey { seen.append(region.verseKey); previous = region.verseKey }
            }
        }
        guard seen == orderedKeys else { throw Invalid.verse }
        return self
    }

    private static func signedArea(_ polygon: [Point]) -> Double {
        zip(polygon, Array(polygon.dropFirst()) + [polygon[0]]).reduce(0) { sum, pair in
            sum + pair.0.x * pair.1.y - pair.1.x * pair.0.y
        } / 2
    }
}

struct MushafPageTransform {
    let scale: CGFloat
    let origin: CGPoint
    let pageSize: CGSize
    init(pageSize: CGSize, viewport: CGRect) {
        self.pageSize = pageSize
        if pageSize.width > 0, pageSize.height > 0, viewport.width > 0, viewport.height > 0 {
            scale = min(viewport.width / pageSize.width, viewport.height / pageSize.height)
            origin = CGPoint(x: viewport.midX - pageSize.width * scale / 2,
                             y: viewport.midY - pageSize.height * scale / 2)
        } else { scale = 0; origin = viewport.origin }
    }
    var frame: CGRect { CGRect(origin: origin, size: CGSize(width: pageSize.width * scale, height: pageSize.height * scale)) }
    func pagePoint(_ point: CGPoint) -> CGPoint? {
        guard scale > 0, frame.contains(point) else { return nil }
        return CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}

enum MushafArtworkGeometry {
    static func path(_ polygon: [MushafArtworkManifest.Point]) -> CGPath {
        let path = CGMutablePath()
        guard let first = polygon.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in polygon.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        path.closeSubpath()
        return path
    }
    static func verse(at point: CGPoint, regions: [MushafArtworkManifest.Region]) -> String? {
        regions.first { region in region.polygons.contains { path($0).contains(point) } }?.verseKey
    }
}

/// Only approved, hash-pinned packages can replace the production reader.
/// An absent package is different from a malformed installed package.
@MainActor final class MushafArtworkLibrary {
    enum Availability { case checking, absent, ready(MushafArtworkLibrary), rejected }
    struct Artwork {
        let metadata: MushafArtworkManifest.Page
        let document: CGPDFDocument
        let page: CGPDFPage
    }
    let manifest: MushafArtworkManifest
    private let bundle: Bundle
    private var retained: [Int: Artwork] = [:]
    private var originalDocument: CGPDFDocument?
    nonisolated static let originalSHA256 = "5c4297de1fb6b654f641eed33242408d89432cbecf8a96ff5d297cb45fea7f07"
    private init(manifest: MushafArtworkManifest, bundle: Bundle) { self.manifest = manifest; self.bundle = bundle }

    static func installed(bundle: Bundle = .main, corpus: [Surah]) async -> Availability {
        if let originalURL = bundle.url(forResource: "king-fahd-standard39-2", withExtension: "pdf") {
            do {
                let pages = try await Task.detached(priority: .userInitiated) {
                    let bytes = try Data(contentsOf: originalURL, options: .mappedIfSafe)
                    guard Self.digest(bytes) == Self.originalSHA256,
                          let document = CGPDFDocument(originalURL as CFURL),
                          document.numberOfPages == 640, !document.isEncrypted else { throw MushafArtworkManifest.Invalid.hash }
                    return try (1...604).map { number -> MushafArtworkManifest.Page in
                        // The publisher's three opening leaves precede printed page 1.
                        guard let page = document.page(at: number + 3) else { throw MushafArtworkManifest.Invalid.page }
                        let box = page.getBoxRect(.mediaBox)
                        guard page.rotationAngle == 0, box.minX == 0, box.minY == 0,
                              abs(box.width - 382.6771545410156) < 0.001,
                              abs(box.height - 547.0866088867188) < 0.001,
                              page.getBoxRect(.cropBox) == box else { throw MushafArtworkManifest.Invalid.artwork }
                        // Empty regions deliberately disable unverified verse hit testing.
                        return .init(number: number, width: Double(box.width), height: Double(box.height),
                            file: "king-fahd-standard39-2.pdf", sha256: Self.originalSHA256, regions: [])
                    }
                }.value
                let manifest = MushafArtworkManifest(schema: 1, edition: "KFGQPC المصحف العادي standard39-2",
                    sourceURL: "https://qurancomplex.gov.sa/wp-content/uploads/isdarat/hafs/standard39-2.pdf",
                    sourceRevision: Self.originalSHA256, rightsRecord: "Distribution review pending",
                    reviewStatus: "USER_CONFIRMED_SOURCE_NATIVE_REVIEW_PENDING", reviewedReferencePages: [604], pages: pages)
                let library = MushafArtworkLibrary(manifest: manifest, bundle: bundle)
                library.originalDocument = CGPDFDocument(originalURL as CFURL)
                guard library.originalDocument != nil else { throw MushafArtworkManifest.Invalid.artwork }
                return .ready(library)
            } catch { return .rejected }
        }
        guard let url = bundle.url(forResource: "mushaf-artwork-manifest", withExtension: "json") else { return .absent }
        do {
            let manifest = try await Task.detached(priority: .userInitiated) {
                let manifest = try JSONDecoder().decode(MushafArtworkManifest.self, from: Data(contentsOf: url)).validated(corpus: corpus)
                // Refuse incomplete packages before the reader appears, not on page 604.
                for metadata in manifest.pages {
                    guard let url = bundle.url(forResource: String(metadata.file.dropLast(4)), withExtension: "pdf"),
                          let bytes = try? Data(contentsOf: url), Self.digest(bytes) == metadata.sha256 else { throw MushafArtworkManifest.Invalid.hash }
                    _ = try Self.decode(bytes, metadata: metadata)
                }
                return manifest
            }.value
            return .ready(MushafArtworkLibrary(manifest: manifest, bundle: bundle))
        } catch { return .rejected }
    }

    func artwork(number: Int) throws -> Artwork {
        if let cached = retained[number] { return cached }
        guard (1...604).contains(number) else { throw MushafArtworkManifest.Invalid.page }
        let metadata = manifest.pages[number - 1]
        if let document = originalDocument {
            guard let page = document.page(at: number + 3) else { throw MushafArtworkManifest.Invalid.artwork }
            return Artwork(metadata: metadata, document: document, page: page)
        }
        guard let url = bundle.url(forResource: String(metadata.file.dropLast(4)), withExtension: "pdf") else { throw MushafArtworkManifest.Invalid.artwork }
        let bytes = try Data(contentsOf: url)
        guard Self.digest(bytes) == metadata.sha256 else { throw MushafArtworkManifest.Invalid.hash }
        let artwork = try Self.decode(bytes, metadata: metadata)
        // Retain at most a small neighborhood; no 604-page in-memory raster cache.
        retained = retained.filter { abs($0.key - number) <= 1 }
        retained[number] = artwork
        return artwork
    }
    private nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private nonisolated static func decode(_ bytes: Data, metadata: MushafArtworkManifest.Page) throws -> Artwork {
        guard let provider = CGDataProvider(data: bytes as CFData), let document = CGPDFDocument(provider),
              document.numberOfPages == 1, !document.isEncrypted, let page = document.page(at: 1) else { throw MushafArtworkManifest.Invalid.artwork }
        let box = page.getBoxRect(.mediaBox)
        guard page.rotationAngle == 0, abs(box.minX) < 0.001, abs(box.minY) < 0.001,
              abs(box.width - metadata.width) < 0.001, abs(box.height - metadata.height) < 0.001,
              page.getBoxRect(.cropBox) == box else { throw MushafArtworkManifest.Invalid.artwork }
        return Artwork(metadata: metadata, document: document, page: page)
    }
}
