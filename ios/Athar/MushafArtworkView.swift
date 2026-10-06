import SwiftUI
import UIKit

/// Artwork is a complete page. UIKit applies one uniform fit and, on request,
/// a scroll-view zoom to that same page and its interaction layer.
struct MushafArtworkView: UIViewRepresentable {
    let artwork: MushafArtworkLibrary.Artwork
    let corpus: [Surah]
    let selected: String?
    let onSelect: (String) -> Void
    let onToggleTools: () -> Void
    func makeUIView(context: Context) -> MushafArtworkViewport { MushafArtworkViewport() }
    func updateUIView(_ view: MushafArtworkViewport, context: Context) {
        view.set(artwork: artwork, corpus: corpus, selected: selected, onSelect: onSelect, onToggleTools: onToggleTools)
    }
}

final class MushafArtworkViewport: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    let canvas = MushafArtworkCanvas()
    private var pageSize = CGSize.zero
    private var lastViewport = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false; scroll.bouncesZoom = false
        scroll.addSubview(canvas); addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    func set(artwork: MushafArtworkLibrary.Artwork, corpus: [Surah], selected: String?,
             onSelect: @escaping (String) -> Void, onToggleTools: @escaping () -> Void) {
        let changed = canvas.artwork?.metadata.number != artwork.metadata.number
        if changed { scroll.setZoomScale(1, animated: false) }
        canvas.artwork = artwork; canvas.corpus = corpus; canvas.selected = selected
        canvas.onSelect = onSelect; canvas.onToggleTools = onToggleTools
        pageSize = CGSize(width: artwork.metadata.width, height: artwork.metadata.height)
        canvas.setNeedsDisplay(); canvas.updateAccessibility(); setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if lastViewport != bounds.size { scroll.setZoomScale(1, animated: false); lastViewport = bounds.size }
        scroll.frame = bounds
        if scroll.zoomScale == 1 {
            let fit = MushafPageTransform(pageSize: pageSize, viewport: bounds)
            canvas.frame = CGRect(origin: .zero, size: fit.frame.size)
            scroll.contentSize = fit.frame.size
        }
        centerPage()
        canvas.updateAccessibility()
    }
    private func centerPage() {
        scroll.contentInset = UIEdgeInsets(top: max(0, (bounds.height - scroll.contentSize.height) / 2),
            left: max(0, (bounds.width - scroll.contentSize.width) / 2),
            bottom: 0, right: 0)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage(); canvas.updateAccessibility() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { canvas.updateAccessibility() }
}

final class MushafArtworkCanvas: UIView {
    override class var layerClass: AnyClass { CATiledLayer.self }
    var artwork: MushafArtworkLibrary.Artwork?
    var corpus: [Surah] = []
    var selected: String?
    var onSelect: ((String) -> Void)?
    var onToggleTools: (() -> Void)?
    private(set) var renderedSuccessfully = false
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear
        if let tiled = layer as? CATiledLayer {
            tiled.levelsOfDetail = 1; tiled.levelsOfDetailBias = 3
            tiled.tileSize = CGSize(width: 512, height: 512)
        }
        isAccessibilityElement = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        tap.require(toFail: press); addGestureRecognizer(tap); addGestureRecognizer(press)
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    private var fit: MushafPageTransform? {
        guard let metadata = artwork?.metadata else { return nil }
        return MushafPageTransform(pageSize: CGSize(width: metadata.width, height: metadata.height), viewport: bounds)
    }
    override func draw(_ rect: CGRect) {
        renderedSuccessfully = false
        guard let artwork, let fit, fit.scale > 0, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.translateBy(x: fit.origin.x, y: fit.origin.y); context.scaleBy(x: fit.scale, y: fit.scale)
        // Hit polygons use the manifest's top-left coordinate space. The PDF is
        // drawn below with its ordinary bottom-left coordinate space.
        if let region = artwork.metadata.regions.first(where: { $0.verseKey == selected }) {
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.20).cgColor)
            for polygon in region.polygons {
                context.addPath(MushafArtworkGeometry.path(polygon)); context.fillPath()
            }
        }
        // Approved page PDFs must have transparent paper. Tint only coverage,
        // preserving the app's existing ink color and every original path.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.saveGState()
        context.translateBy(x: 0, y: artwork.metadata.height); context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(artwork.page); context.restoreGState()
        context.setBlendMode(.sourceIn); context.setFillColor(UIColor.label.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: artwork.metadata.width, height: artwork.metadata.height))
        context.endTransparencyLayer(); context.restoreGState()
        renderedSuccessfully = true
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) { onToggleTools?() }
    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let metadata = artwork?.metadata,
              let point = fit?.pagePoint(gesture.location(in: self)),
              let key = MushafArtworkGeometry.verse(at: point, regions: metadata.regions) else { return }
        onSelect?(key)
    }
    func updateAccessibility() {
        guard let metadata = artwork?.metadata, let fit, fit.scale > 0 else { accessibilityElements = nil; return }
        accessibilityElements = metadata.regions.compactMap { region -> UIAccessibilityElement? in
            let key = region.verseKey.split(separator: ":").compactMap { Int($0) }
            guard key.count == 2, corpus.indices.contains(key[0] - 1), corpus[key[0] - 1].ayahs.indices.contains(key[1] - 1) else { return nil }
            let element = MushafArtworkAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = QuranText.verse(chapter: key[0], ayah: corpus[key[0] - 1].ayahs[key[1] - 1])
            element.accessibilityHint = "خيارات الآية \(key[1])"; element.accessibilityTraits = .button
            // accessibilityPath is in screen coordinates; preserve disconnected
            // components instead of a box that includes adjacent ayahs.
            // convert point-by-point also accounts for the scroll view's zoom.
            let screen = CGMutablePath()
            for polygon in region.polygons {
                let points = polygon.map { point in convert(CGPoint(x: point.x * fit.scale + fit.origin.x, y: point.y * fit.scale + fit.origin.y), to: nil) }
                if let first = points.first { screen.move(to: first); for p in points.dropFirst() { screen.addLine(to: p) }; screen.closeSubpath() }
            }
            element.accessibilityPath = UIBezierPath(cgPath: screen)
            element.activate = { [weak self] in self?.onSelect?(region.verseKey) }
            return element
        }
    }
}

private final class MushafArtworkAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
}
