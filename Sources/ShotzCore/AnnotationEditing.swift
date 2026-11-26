import Foundation

/// The editor. Implemented by AnnotationEditor.
@MainActor public protocol AnnotationEditing: AnyObject {
    func openEditor(for capture: CaptureResult)
    func openEditor(imageAt url: URL)
}
