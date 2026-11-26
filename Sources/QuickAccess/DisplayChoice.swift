import CoreGraphics
import ShotzCore

/// Which display a card's stack lives on (SPEC §4.1). Pure.
enum DisplayChoice {
    /// - Parameters:
    ///   - captured: display the capture came from.
    ///   - available: connected displays.
    ///   - main: the primary display (menu bar).
    static func resolve(captured: CGDirectDisplayID, setting: StackDisplay, available: [CGDirectDisplayID], main: CGDirectDisplayID) -> CGDirectDisplayID {
        switch setting {
        case .main:
            return main
        case .whereCaptured:
            return available.contains(captured) ? captured : main
        }
    }
}
