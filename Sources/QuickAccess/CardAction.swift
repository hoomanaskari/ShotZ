import AppKit

/// Everything a card can do (SPEC §4.4).
enum CardAction: CaseIterable, Sendable {
    case copy, save, annotate, quickLook, close, closeAndDelete
    case showInFinder, copyFilePath, closeAll

    /// Hover-only keyboard shortcuts (SPEC §4.3). Pure; unit-tested.
    /// - Parameters:
    ///   - characters: `charactersIgnoringModifiers`, so ⌘C works on any layout.
    static func forKey(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> CardAction? {
        let mods = modifiers.intersection([.command, .shift, .option, .control])
        let key = characters?.lowercased()
        switch mods {
        case []:
            switch keyCode {
            case KeyCode.returnKey, KeyCode.keypadEnter: return .annotate
            case KeyCode.space: return .quickLook
            case KeyCode.escape: return .close
            default: return nil
            }
        case [.command]:
            if keyCode == KeyCode.delete { return .closeAndDelete }
            switch key {
            case "c": return .copy
            case "s": return .save
            case "e": return .annotate
            case "w": return .close
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Shortcut shown in tooltips.
    var shortcutHint: String? {
        switch self {
        case .copy: "⌘C"
        case .save: "⌘S"
        case .annotate: "⌘E"
        case .quickLook: String(localized: "Space")
        case .close: "⌘W"
        case .closeAndDelete: "⌘⌫"
        case .showInFinder, .copyFilePath, .closeAll: nil
        }
    }

    var title: String {
        switch self {
        case .copy: String(localized: "Copy")
        case .save: String(localized: "Save")
        case .annotate: String(localized: "Annotate")
        case .quickLook: String(localized: "Quick Look")
        case .close: String(localized: "Close")
        case .closeAndDelete: String(localized: "Delete")
        case .showInFinder: String(localized: "Show in Finder")
        case .copyFilePath: String(localized: "Copy File Path")
        case .closeAll: String(localized: "Close All")
        }
    }

    var symbolName: String {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "arrow.down.to.line"
        case .annotate: "pencil"
        case .quickLook: "eye"
        case .close: "xmark"
        case .closeAndDelete: "trash"
        case .showInFinder: "folder"
        case .copyFilePath: "link"
        case .closeAll: "xmark.square"
        }
    }

    var tooltip: String {
        guard let hint = shortcutHint else { return title }
        return "\(title) (\(hint))"
    }
}

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
}
