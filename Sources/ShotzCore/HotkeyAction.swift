/// Actions that can be bound to a global shortcut (SPEC §7 Shortcuts).
public enum HotkeyAction: String, Codable, Sendable, CaseIterable, Hashable {
    case captureFullscreen
    case captureArea
    case captureAllInOne
    case captureWindow
    case restoreLastClosed

    /// The capture mode this action triggers, if any.
    public var captureMode: CaptureMode? {
        switch self {
        case .captureFullscreen: .fullscreen
        case .captureArea: .area
        case .captureAllInOne: .allInOne
        case .captureWindow: .window
        case .restoreLastClosed: nil
        }
    }
}
