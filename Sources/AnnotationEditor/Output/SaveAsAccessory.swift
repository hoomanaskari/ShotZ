import AppKit
import ShotzCore

/// Format, quality and scale choices under the Save As panel.
@MainActor final class SaveAsAccessory: NSObject {
    let view: NSView
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualitySlider = NSSlider(value: 0.9, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: String(localized: "Quality:"))
    private let scaleControl = NSSegmentedControl(labels: ["1×", "2×"], trackingMode: .selectOne, target: nil, action: nil)
    private weak var panel: NSSavePanel?

    private(set) var format: ImageFormat
    var quality: Double { qualitySlider.doubleValue }
    /// Output pixels per point.
    var scaleFactor: Int { scaleControl.selectedSegment == 0 ? 1 : 2 }

    init(format: ImageFormat, panel: NSSavePanel) {
        self.format = format
        self.panel = panel
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "Format:")), formatPopup],
            [qualityLabel, qualitySlider],
            [NSTextField(labelWithString: String(localized: "Scale:")), scaleControl],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            qualitySlider.widthAnchor.constraint(equalToConstant: 160),
        ])
        view = container
        super.init()
        for f in ImageFormat.allCases {
            let item = NSMenuItem(title: f.rawValue.uppercased(), action: nil, keyEquivalent: "")
            item.representedObject = f.rawValue
            formatPopup.menu?.addItem(item)
        }
        formatPopup.selectItem(at: formatPopup.indexOfItem(withRepresentedObject: format.rawValue))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        scaleControl.selectedSegment = 1
        updateQuality()
    }

    @objc private func formatChanged() {
        format = (formatPopup.selectedItem?.representedObject as? String).flatMap(ImageFormat.init(rawValue:)) ?? .png
        panel?.allowedContentTypes = [format.utType]
        if let panel {
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + format.fileExtension
        }
        updateQuality()
    }

    private func updateQuality() {
        qualitySlider.isEnabled = format != .png
        qualityLabel.textColor = format == .png ? .tertiaryLabelColor : .labelColor
    }
}
