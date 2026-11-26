import AppKit
import UniformTypeIdentifiers

/// Pasteboard contents of a card drag: the export file's URL, plus the file's
/// bytes under its image type (promised, read only if a receiver asks), so
/// file targets (Finder, Mail, chat, browsers) and image targets both accept it.
final class DragFileWriter: NSObject, NSPasteboardWriting {
    let fileURL: URL
    private let imageType: NSPasteboard.PasteboardType?

    init(fileURL: URL) {
        self.fileURL = fileURL
        imageType = UTType(filenameExtension: fileURL.pathExtension).map { NSPasteboard.PasteboardType($0.identifier) }
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL] + (imageType.map { [$0] } ?? [])
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : .promised
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL { return (fileURL as NSURL).pasteboardPropertyList(forType: .fileURL) }
        guard type == imageType else { return nil }
        do {
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            return nil // receiver gets no image data and falls back to the file URL
        }
    }
}
