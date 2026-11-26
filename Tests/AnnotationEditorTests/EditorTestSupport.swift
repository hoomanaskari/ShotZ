import AnnotationKit
import CoreGraphics
import Foundation
@testable import AnnotationEditor
import ShotzTestSupport

/// A fresh model on a 1600 × 1000 document with isolated defaults.
@MainActor
func makeModel(size: CGSize = CGSize(width: 1600, height: 1000), tool: ToolKind = .select) -> EditorModel {
    let defaults = MemoryDefaults()
    let doc = AnnotationDocument(baseImageURL: URL(filePath: "/tmp/none.png"), pixelSize: size, scale: 2)
    let model = EditorModel(store: DocumentStore(document: doc), library: ToolSettingsLibrary(defaults: defaults), initialTool: tool)
    model.pointsPerPixel = 1
    model.snappingSetting = { false }
    return model
}

extension EditorModel {
    func drag(_ from: CGPoint, _ to: CGPoint, _ mods: ToolModifiers = [], steps: Int = 5) {
        tool.mouseDown(ToolEvent(from, mods))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            tool.mouseDragged(ToolEvent(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), mods))
        }
        tool.mouseUp(ToolEvent(to, mods))
    }

    func click(_ p: CGPoint, _ mods: ToolModifiers = [], count: Int = 1) {
        tool.mouseDown(ToolEvent(p, mods, clickCount: count))
        tool.mouseUp(ToolEvent(p, mods, clickCount: count))
    }

    var objects: [AnnotationObject] { document.objects }
}

/// Records in-place text editing requests instead of showing a text view.
@MainActor final class FakeTextHost: TextEditingHost {
    var began: [(AnnotationObject, Bool)] = []
    var isEditingText = false
    func beginEditing(_ object: AnnotationObject, isNew: Bool) {
        began.append((object, isNew))
        isEditingText = true
    }
    func endEditing() { isEditingText = false }
}

func rect(of object: AnnotationObject) -> CGRect? {
    if case .rectangle(let r, _) = object.shape { return r }
    return nil
}
