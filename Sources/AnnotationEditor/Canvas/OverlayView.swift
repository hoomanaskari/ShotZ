import AnnotationKit
import AppKit

/// Selection outlines, handles, snap guides, marquee and the crop frame.
/// Lives above the scroll view in window points (not magnified), so lines
/// and handles stay crisp and constant-size at every zoom. Never takes clicks.
@MainActor final class OverlayView: NSView {
    struct Content {
        var selectionOutlines: [CGPath] = []
        /// Dashed outlines that help find otherwise invisible objects (redactions).
        var hintOutlines: [CGPath] = []
        var handles: [(Handle, isControl: Bool)] = []
        var guides: [(CGPoint, CGPoint)] = []
        var marquee: CGRect?
        /// Crop draft and the full image, in overlay points.
        var crop: (draft: CGRect, image: CGRect)?
        var cropLabel: String?
    }

    private let outlineLayer = CAShapeLayer()
    private let hintLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let controlHandleLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let marqueeLayer = CAShapeLayer()
    private let cropDimLayer = CAShapeLayer()
    private let cropFrameLayer = CAShapeLayer()
    private let cropLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for l in [cropDimLayer, cropFrameLayer, hintLayer, outlineLayer, guideLayer, marqueeLayer, handleLayer, controlHandleLayer] {
            l.actions = ObjectLayerStore.noActions.merging(["path": NSNull(), "fillColor": NSNull()]) { a, _ in a }
            layer?.addSublayer(l)
        }
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 1
        hintLayer.fillColor = nil
        hintLayer.lineWidth = 1
        hintLayer.lineDashPattern = [4, 3]
        handleLayer.lineWidth = 1.5
        controlHandleLayer.lineWidth = 1.5
        guideLayer.lineWidth = 1
        guideLayer.fillColor = nil
        marqueeLayer.lineWidth = 1
        cropDimLayer.fillRule = .evenOdd
        cropFrameLayer.fillColor = nil
        cropFrameLayer.lineWidth = 1
        cropLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        cropLabel.textColor = .white
        cropLabel.drawsBackground = true
        cropLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        cropLabel.isHidden = true
        addSubview(cropLabel)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor.cgColor
            outlineLayer.strokeColor = accent
            hintLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
            handleLayer.strokeColor = accent
            handleLayer.fillColor = NSColor.white.cgColor
            controlHandleLayer.strokeColor = NSColor.white.cgColor
            controlHandleLayer.fillColor = accent
            guideLayer.strokeColor = NSColor.systemPink.cgColor
            marqueeLayer.strokeColor = accent
            marqueeLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            cropDimLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
            cropFrameLayer.strokeColor = NSColor.white.cgColor
        }
    }

    func show(_ content: Content) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let outline = CGMutablePath()
        content.selectionOutlines.forEach { outline.addPath($0) }
        outlineLayer.path = outline
        let hints = CGMutablePath()
        content.hintOutlines.forEach { hints.addPath($0) }
        hintLayer.path = hints

        let handles = CGMutablePath(), controls = CGMutablePath()
        let r: CGFloat = 4.5
        for (h, isControl) in content.handles {
            let rect = CGRect(x: h.position.x - r, y: h.position.y - r, width: 2 * r, height: 2 * r)
            if isControl { controls.addEllipse(in: rect) } else { handles.addEllipse(in: rect) }
        }
        handleLayer.path = handles
        controlHandleLayer.path = controls

        let guides = CGMutablePath()
        for (a, b) in content.guides { guides.move(to: a); guides.addLine(to: b) }
        guideLayer.path = guides

        marqueeLayer.path = content.marquee.map { CGPath(rect: $0, transform: nil) }

        if let crop = content.crop {
            let dim = CGMutablePath()
            dim.addRect(crop.image)
            dim.addRect(crop.draft)
            cropDimLayer.path = dim
            let frame = CGMutablePath()
            frame.addRect(crop.draft.insetBy(dx: 0.5, dy: 0.5))
            // Thirds.
            for i in 1...2 {
                let x = crop.draft.minX + crop.draft.width * CGFloat(i) / 3
                let y = crop.draft.minY + crop.draft.height * CGFloat(i) / 3
                frame.move(to: CGPoint(x: x, y: crop.draft.minY)); frame.addLine(to: CGPoint(x: x, y: crop.draft.maxY))
                frame.move(to: CGPoint(x: crop.draft.minX, y: y)); frame.addLine(to: CGPoint(x: crop.draft.maxX, y: y))
            }
            cropFrameLayer.path = frame
            cropFrameLayer.opacity = 0.9
            let handlePath = CGMutablePath()
            for kind in CropTool.handleKinds {
                let p = CropTool.position(of: kind, in: crop.draft)
                handlePath.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
            handleLayer.path = handlePath
            if let label = content.cropLabel {
                cropLabel.stringValue = " \(label) "
                cropLabel.sizeToFit()
                cropLabel.setFrameOrigin(NSPoint(x: crop.draft.minX + 6, y: max(crop.draft.minY - cropLabel.frame.height - 4, crop.draft.minY + 6)))
                cropLabel.isHidden = false
            }
        } else {
            cropDimLayer.path = nil
            cropFrameLayer.path = nil
            cropLabel.isHidden = true
        }
    }
}
