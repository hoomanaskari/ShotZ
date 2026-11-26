import AppKit
import ShotzCore

/// Every glyph the stack draws, mapped onto ShotzCore's shared `ShotzIcon`
/// set (Phosphor regular plus Shotz glyphs, rendered from vectors).
enum CardIcon: Equatable {
    case action(CardAction)
    case success
    case failure

    var shotzIcon: ShotzIcon {
        switch self {
        case .success: .check
        case .failure: .warning
        case .action(let a):
            switch a {
            case .close: .close
            case .annotate: .annotate
            case .quickLook: .quickLook
            case .copy: .copy
            case .save: .save
            case .closeAndDelete: .trash
            case .showInFinder: .folder
            case .copyFilePath: .share // TODO: a link glyph if ShotzIcon gains one
            case .closeAll: .stack
            }
        }
    }

    /// A template image `pointSize` square, tinted by the view that shows it.
    @MainActor func image(pointSize: CGFloat) -> NSImage? {
        shotzIcon.image(pointSize: pointSize)
    }
}
