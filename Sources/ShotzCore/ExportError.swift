public enum ExportError: Error, Sendable, Equatable {
    case unreadableImage(String)
    case encodingFailed(String)
    case pasteboardWriteFailed
}
