import AppKit
import ShotzCore

/// A numeric field with − / + steppers and monospaced digits: crop W × H, counter start value.
/// Typing commits on Return or focus loss; the steppers and ↑/↓ change by `step`.
@MainActor
public final class ShotzNumberField: ShotzControlView, NSTextFieldDelegate {
    public var value: Double { didSet { value = min(max(value, minValue), maxValue); syncText(); setAccessibilityValue(text(for: value)) } }
    public var minValue: Double
    public var maxValue: Double
    public var step: Double
    /// Shown after the number, e.g. "px".
    public var suffix: String? { didSet { syncText(); invalidateIntrinsicContentSize() } }
    public var fractionDigits = 0 { didSet { syncText() } }
    /// Digits reserved so the field doesn't resize while typing.
    public var digits = 4 { didSet { invalidateIntrinsicContentSize() } }
    public var onChange: ((Double) -> Void)?

    private let field = NSTextField()
    private let minus: ShotzButton
    private let plus: ShotzButton

    public init(value: Double, in range: ClosedRange<Double>, step: Double = 1, label: String, size: ShotzUI.ControlSize = .compact) {
        self.value = value
        minValue = range.lowerBound
        maxValue = range.upperBound
        self.step = step
        minus = ShotzButton(icon: .minus, role: .quiet, size: .compact)
        plus = ShotzButton(icon: .plus, role: .quiet, size: .compact)
        super.init(frame: .zero)
        shotzSize = size
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = ShotzUI.Typography.value.font
        field.textColor = ShotzUI.Palette.textPrimary
        field.delegate = self
        field.setAccessibilityLabel(label)
        minus.setAccessibilityLabel(String(localized: "Decrease \(label)"))
        plus.setAccessibilityLabel(String(localized: "Increase \(label)"))
        minus.onAction = { [weak self] _ in self?.nudge(-1) }
        plus.onAction = { [weak self] _ in self?.nudge(1) }
        for v in [field, minus, plus] as [NSView] { addSubview(v) }
        setAccessibilityElement(false)
        syncText()
    }

    private func text(for v: Double) -> String {
        let n = String(format: "%.\(fractionDigits)f", v)
        return suffix.map { "\(n) \($0)" } ?? n
    }

    private func syncText() { field.stringValue = text(for: value) }

    private func nudge(_ direction: Double) {
        value += direction * step
        onChange?(value)
        sendAction(action, to: target)
    }

    public override var intrinsicContentSize: NSSize {
        let sample = String(repeating: "8", count: digits) + (suffix.map { " \($0)" } ?? "")
        let textW = ceil((sample as NSString).size(withAttributes: [.font: ShotzUI.Typography.value.font]).width) + 8
        return NSSize(width: textW + 2 * (shotzSize.height - 2), height: shotzSize.hitHeight)
    }

    public override func layout() {
        super.layout()
        let chrome = chromeRect()
        let side = chrome.height - 2
        minus.frame = CGRect(x: chrome.minX, y: (bounds.midY - 14).rounded(), width: side, height: 28)
        plus.frame = CGRect(x: chrome.maxX - side, y: (bounds.midY - 14).rounded(), width: side, height: 28)
        let fieldHeight = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: chrome.minX + side, y: (chrome.midY - fieldHeight / 2).rounded(), width: chrome.width - 2 * side, height: fieldHeight)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let chrome = chromeRect()
        let path = CGPath(roundedRect: chrome, cornerWidth: shotzSize.radius, cornerHeight: shotzSize.radius, transform: nil)
        let editing = field.currentEditor() != nil
        var fills = ShotzUI.ControlFills(background: ShotzUI.Palette.surfaceSunken, border: ShotzUI.Palette.border, content: ShotzUI.Palette.textPrimary, raised: false)
        if !state.isEnabled { fills.border = nil }
        var drawState = state
        drawState.isFocused = state.isFocused || editing
        drawChrome(path, fills: fills, state: drawState, in: ctx)
        field.textColor = state.isEnabled ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textTertiary
        minus.isEnabled = state.isEnabled && value > minValue
        plus.isEnabled = state.isEnabled && value < maxValue
    }

    public override var acceptsFirstResponder: Bool { false } // the text field takes focus

    public func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }

    public func controlTextDidEndEditing(_ obj: Notification) {
        let digitsOnly = field.stringValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
        if let v = Double(digitsOnly), v != value {
            value = v
            onChange?(value)
            sendAction(action, to: target)
        } else {
            syncText()
        }
        needsDisplay = true
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): nudge(1); return true
        case #selector(NSResponder.moveDown(_:)): nudge(-1); return true
        default: return false
        }
    }
}
