import AppKit
import SwiftUI

/// A single-line text field (file-name pattern, preset names): sunken fill, hairline edge, ShotZ
/// focus ring while editing. Reports every change and the commit (Return / focus loss).
@MainActor
public final class ShotzTextField: ShotzControlView, NSTextFieldDelegate {
    public var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }
    public var placeholder: String? { didSet { field.placeholderString = placeholder } }
    /// Monospaced for patterns and paths (`Typography.value`), body otherwise.
    public var usesMonospacedFont = false { didSet { field.font = usesMonospacedFont ? ShotzUI.Typography.value.font : ShotzUI.Typography.body.font } }
    public var preferredWidth: CGFloat = 220 { didSet { invalidateIntrinsicContentSize() } }
    public var onChange: ((String) -> Void)?
    public var onCommit: ((String) -> Void)?
    private let field = NSTextField()

    public init(_ value: String = "", placeholder: String? = nil, label: String, size: ShotzUI.ControlSize = .regular) {
        super.init(frame: .zero)
        shotzSize = size
        field.stringValue = value
        field.placeholderString = placeholder
        self.placeholder = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = ShotzUI.Typography.body.font
        field.textColor = ShotzUI.Palette.textPrimary
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityLabel(label)
        addSubview(field)
        setAccessibilityElement(false)
    }

    public override var intrinsicContentSize: NSSize { NSSize(width: preferredWidth, height: shotzSize.hitHeight) }
    public override var acceptsFirstResponder: Bool { false } // the inner field takes focus

    public override func layout() {
        super.layout()
        let chrome = chromeRect()
        let h = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: chrome.minX + ShotzUI.Space.s, y: (chrome.midY - h / 2).rounded(), width: chrome.width - 2 * ShotzUI.Space.s, height: h)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let chrome = chromeRect()
        let path = CGPath(roundedRect: chrome, cornerWidth: shotzSize.radius, cornerHeight: shotzSize.radius, transform: nil)
        var s = state
        s.isFocused = state.isFocused || field.currentEditor() != nil
        let fills = ShotzUI.ControlFills(background: ShotzUI.Palette.surfaceSunken, border: state.isEnabled ? ShotzUI.Palette.border : nil,
                                         content: ShotzUI.Palette.textPrimary, raised: false)
        drawChrome(path, fills: fills, state: s, in: ctx)
        field.isEnabled = state.isEnabled
        field.textColor = state.isEnabled ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textTertiary
    }

    public func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    public func controlTextDidChange(_ obj: Notification) { onChange?(field.stringValue) }
    public func controlTextDidEndEditing(_ obj: Notification) {
        needsDisplay = true
        onCommit?(field.stringValue)
        sendAction(action, to: target)
    }
}

/// SwiftUI counterpart: `ShotzTextFieldView("Pattern", text: $pattern, monospaced: true)`.
public struct ShotzTextFieldView: View {
    let placeholder: String
    @Binding var text: String
    let monospaced: Bool
    let size: ShotzUI.ControlSize
    let onCommit: (() -> Void)?
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(_ placeholder: String, text: Binding<String>, monospaced: Bool = false, size: ShotzUI.ControlSize = .regular, onCommit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.monospaced = monospaced
        self.size = size
        self.onCommit = onCommit
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? ShotzUI.Typography.value.swiftUIFont : ShotzUI.Typography.body.swiftUIFont)
            .foregroundStyle(Color(nsColor: isEnabled ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textTertiary))
            .focused($focused)
            .onSubmit { onCommit?() }
            .padding(.horizontal, ShotzUI.Space.s)
            .frame(height: size.height)
            .background(shape.fill(Color(nsColor: ShotzUI.Palette.surfaceSunken)))
            .overlay(shape.strokeBorder(Color(nsColor: ShotzUI.Palette.border), lineWidth: 1))
            .overlay { if focused { shape.inset(by: -3).strokeBorder(Color(nsColor: ShotzUI.Palette.focusRing), lineWidth: 3) } }
            .frame(minHeight: size.hitHeight)
    }
}
