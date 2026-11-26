import AppKit
import ShotzCore
import ShotzUI

/// Format, quality and scale choices under the Save As panel, built from ShotzUI controls.
@MainActor final class SaveAsAccessory: NSObject {
    let view: NSView
    private let formatPopup: ShotzPopUpButton
    private let qualitySlider = ShotzSlider(value: 0.9, in: 0.3...1, step: 0.01, label: String(localized: "Quality"), size: EditorControls.actionSize)
    private let scaleControl = ShotzSegmentedControl(segments: [.init(title: "1×"), .init(title: "2×")], selectedIndex: 1, size: EditorControls.actionSize)
    private weak var panel: NSSavePanel?

    private(set) var format: ImageFormat
    var quality: Double { qualitySlider.value }
    /// Output pixels per point.
    var scaleFactor: Int { scaleControl.selectedIndex == 0 ? 1 : 2 }

    init(format: ImageFormat, panel: NSSavePanel) {
        self.format = format
        self.panel = panel
        let formats = ImageFormat.allCases
        formatPopup = ShotzPopUpButton(items: formats.map { $0.rawValue.uppercased() }, selectedIndex: formats.firstIndex(of: format) ?? 0,
                                       size: EditorControls.actionSize)
        formatPopup.setAccessibilityLabel(String(localized: "Format"))
        qualitySlider.trackWidth = 140
        qualitySlider.format = EditorControls.percent
        qualitySlider.valuePlaceholder = "100 %"
        scaleControl.setAccessibilityLabel(String(localized: "Scale"))
        let form = ShotzFormStack(rows: [
            .init(String(localized: "Format"), formatPopup),
            .init(String(localized: "Quality"), qualitySlider),
            .init(String(localized: "Scale"), scaleControl),
        ], labelWidth: 64)
        let size = form.intrinsicContentSize
        let container = NSView(frame: NSRect(x: 0, y: 0, width: max(320, size.width + 2 * ShotzUI.Space.l), height: size.height + 2 * ShotzUI.Space.m))
        form.frame = NSRect(x: ((container.bounds.width - size.width) / 2).rounded(), y: ShotzUI.Space.m, width: size.width, height: size.height)
        form.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(form)
        view = container
        super.init()
        formatPopup.onChange = { [weak self] i in self?.formatChanged(formats[i]) }
        updateQuality()
    }

    private func formatChanged(_ new: ImageFormat) {
        format = new
        panel?.allowedContentTypes = [format.utType]
        if let panel {
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + format.fileExtension
        }
        updateQuality()
    }

    private func updateQuality() {
        qualitySlider.isEnabled = format != .png
    }
}
