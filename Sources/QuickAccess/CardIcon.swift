import AppKit

/// Every glyph the stack draws, in one place.
/// TEMP until ShotzCore's `ShotzIcon` (Phosphor, one weight) is on main:
/// SF Symbols stand in; the Phosphor names are in `phosphorName`.
enum CardIcon: Equatable {
    case action(CardAction)
    case success
    case failure

    var phosphorName: String {
        switch self {
        case .success: "check-circle"
        case .failure: "warning-circle"
        case .action(let a):
            switch a {
            case .close: "x"
            case .annotate: "pencil-simple"
            case .quickLook: "eye"
            case .copy: "copy"
            case .save: "download-simple"
            case .closeAndDelete: "trash"
            case .showInFinder: "folder-open"
            case .copyFilePath: "link-simple"
            case .closeAll: "x-square"
            }
        }
    }

    private var fallbackSymbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.circle.fill"
        case .action(let a): a.symbolName
        }
    }

    /// A template image sized for `pointSize`, tinted by the view that shows it.
    @MainActor func image(pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}
