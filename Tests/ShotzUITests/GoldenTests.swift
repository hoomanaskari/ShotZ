import AppKit
import ImageIO
import Testing
@testable import ShotzUI

/// Golden images for the tokens and key controls (system blue pinned). Record or refresh with
/// SHOTZ_RECORD_GOLDENS=1 swift test --filter ShotzUITests.GoldenTests, then inspect before committing.
@MainActor
@Suite(.serialized)
struct GoldenTests {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
    static let recording = ProcessInfo.processInfo.environment["SHOTZ_RECORD_GOLDENS"] == "1"
    init() { _ = NSApplication.shared }

    static func keyControls() -> GallerySheet {
        let sheet = GallerySheet(width: 760, columnWidth: 120)
        sheet.row("Buttons", [ShotzButton(title: "Save", icon: .save, role: .primary), ShotzButton(title: "Copy", icon: .copy, role: .secondary),
                              ShotzButton(title: "Reset", role: .quiet), ShotzButton(icon: .more, role: .quiet)])
        let selected = ShotzToolButton(icon: .arrowTool); selected.isSelected = true
        let hovered = ShotzToolButton(icon: .rectangle); hovered.stateOverride = .hover
        let chipOn = ShotzToggleChip(title: "Outline", isOn: true)
        sheet.row("Tool · chip", [ShotzToolButton(icon: .select), selected, hovered, ShotzToggleChip(title: "Outline"), chipOn])
        sheet.row("Segmented", [ShotzSegmentedControl(segments: ["Arrow", "Line", "Shape"].map { .init(title: $0) }, selectedIndex: 1)], columnWidth: 300)
        let slider = ShotzSlider(value: 0.6, icon: .opacity, label: "Opacity", size: .compact); slider.trackWidth = 96
        sheet.row("Swatches · slider", [ShotzSwatchRow(swatches: GalleryTests.presetSwatches, selectedIndex: 0), slider], columnWidth: 290)
        sheet.finish()
        return sheet
    }

    @Test(arguments: ["light", "dark"]) func goldens(_ appearanceName: String) throws {
        ShotzUI.Palette.accentOverride = GalleryOutput.blue
        defer { ShotzUI.Palette.accentOverride = nil }
        let appearance = NSAppearance(named: appearanceName == "dark" ? .darkAqua : .aqua)!
        for (name, sheet) in [("tokens", TokensSheet.make()), ("key-controls", Self.keyControls())] {
            let image = sheet.render(appearance: appearance, scale: 2)
            let url = Self.directory.appending(path: "\(name)-\(appearanceName)@2x.png")
            if Self.recording {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(dest, image, nil)
                #expect(CGImageDestinationFinalize(dest))
                continue
            }
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "missing golden \(url.lastPathComponent)")
            let golden = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
            #expect(golden.width == image.width && golden.height == image.height, "\(name): size changed")
            guard golden.width == image.width, golden.height == image.height else { continue }
            let a = Self.rgba(image), b = Self.rgba(golden)
            var differing = 0
            for i in stride(from: 0, to: a.count, by: 4) where (0..<4).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > 24 }) { differing += 1 }
            let fraction = Double(differing) / Double(image.width * image.height)
            #expect(fraction <= 0.004, "\(name)-\(appearanceName): \(differing) pixels differ")
        }
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buf
    }
}
