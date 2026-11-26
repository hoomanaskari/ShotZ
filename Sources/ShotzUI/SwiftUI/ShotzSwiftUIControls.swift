import AppKit
import ShotzCore
import SwiftUI

/// SwiftUI counterpart of `ShotzToggleChip`: `Toggle("Outline", isOn: $on).toggleStyle(.shotzChip)`.
public struct ShotzToggleChipStyle: ToggleStyle {
    public var icon: ShotzIcon?
    public var size: ShotzUI.ControlSize
    public init(icon: ShotzIcon? = nil, size: ShotzUI.ControlSize = .compact) { self.icon = icon; self.size = size }

    public func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, icon: icon, size: size)
    }

    private struct ChipBody: View {
        let configuration: Configuration
        let icon: ShotzIcon?
        let size: ShotzUI.ControlSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let state = ShotzUI.ControlState(isHovered: isHovered, isSelected: configuration.isOn, isEnabled: isEnabled)
            let fills = ShotzUI.fills(for: .chip, state: state)
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: size.iconLabelGap) {
                    if let glyph = icon ?? (configuration.isOn ? .check : nil) {
                        ShotzIconView(glyph, size: size.iconSize)
                    } else {
                        Circle().strokeBorder(lineWidth: 1.25).frame(width: size.iconSize - 4, height: size.iconSize - 4)
                            .frame(width: size.iconSize, height: size.iconSize)
                    }
                    configuration.label
                }
                .font(Font(size.font))
                .foregroundStyle(Color(nsColor: fills.content))
                .padding(.horizontal, size.horizontalPadding + 1)
                .frame(height: size.height)
                .background { if let bg = fills.background { Capsule().fill(Color(nsColor: bg)) } }
                .overlay { if let b = fills.border { Capsule().strokeBorder(Color(nsColor: b), lineWidth: 1) } }
                .contentShape(Capsule())
                .frame(minHeight: size.hitHeight)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        }
    }
}

extension ToggleStyle where Self == ShotzToggleChipStyle {
    public static var shotzChip: ShotzToggleChipStyle { ShotzToggleChipStyle() }
    public static func shotzChip(icon: ShotzIcon?, size: ShotzUI.ControlSize = .compact) -> ShotzToggleChipStyle { ShotzToggleChipStyle(icon: icon, size: size) }
}

/// SwiftUI wrapper of `ShotzSegmentedControl` (identical look; the AppKit control draws).
public struct ShotzSegmentedPicker: NSViewRepresentable {
    let segments: [ShotzSegmentedControl.Segment]
    @Binding var selection: Int
    let size: ShotzUI.ControlSize

    public init(_ segments: [ShotzSegmentedControl.Segment], selection: Binding<Int>, size: ShotzUI.ControlSize = .regular) {
        self.segments = segments
        self._selection = selection
        self.size = size
    }

    public func makeNSView(context: Context) -> ShotzSegmentedControl {
        let c = ShotzSegmentedControl(segments: segments, selectedIndex: selection, size: size)
        c.onChange = { selection = $0 }
        return c
    }

    public func updateNSView(_ view: ShotzSegmentedControl, context: Context) {
        if view.segments != segments { view.segments = segments }
        if view.selectedIndex != selection { view.select(selection) }
        view.onChange = { selection = $0 }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShotzSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// SwiftUI wrapper of `ShotzSlider`.
public struct ShotzSliderView: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let icon: ShotzIcon?
    let label: String
    let format: ((Double) -> String)?

    public init(value: Binding<Double>, in range: ClosedRange<Double> = 0...1, icon: ShotzIcon? = nil, label: String, format: ((Double) -> String)? = nil) {
        self._value = value
        self.range = range
        self.icon = icon
        self.label = label
        self.format = format
    }

    public func makeNSView(context: Context) -> ShotzSlider {
        let s = ShotzSlider(value: value, in: range, icon: icon, label: label)
        if let format { s.format = format }
        s.onChange = { value = $0 }
        return s
    }

    public func updateNSView(_ view: ShotzSlider, context: Context) {
        if view.value != value { view.value = value }
        view.onChange = { value = $0 }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShotzSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }
}

/// SwiftUI wrapper of `ShotzSwatchRow`.
public struct ShotzSwatchPicker: NSViewRepresentable {
    let swatches: [ShotzSwatchRow.Swatch]
    @Binding var selection: Int?
    let onCustom: (() -> Void)?

    public init(_ swatches: [ShotzSwatchRow.Swatch], selection: Binding<Int?>, onCustom: (() -> Void)? = nil) {
        self.swatches = swatches
        self._selection = selection
        self.onCustom = onCustom
    }

    public func makeNSView(context: Context) -> ShotzSwatchRow {
        let row = ShotzSwatchRow(swatches: swatches, selectedIndex: selection)
        row.showsCustomWell = onCustom != nil
        configure(row)
        return row
    }

    public func updateNSView(_ view: ShotzSwatchRow, context: Context) {
        if view.selectedIndex != selection { view.selectedIndex = selection }
        configure(view)
    }

    private func configure(_ row: ShotzSwatchRow) {
        let count = swatches.count
        row.onSelect = { i in if i < count { selection = i } else { onCustom?() } }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShotzSwatchRow, context: Context) -> CGSize? { nsView.intrinsicContentSize }
}
