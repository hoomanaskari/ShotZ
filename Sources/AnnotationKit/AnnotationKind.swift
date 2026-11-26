/// The kind of an object, one per drawing tool. Used for per-tool default styles.
public enum AnnotationKind: String, Codable, Sendable, CaseIterable, Hashable {
    case arrow, rectangle, ellipse, line, text, highlighter, redact, counter, pen
}

extension AnnotationObject {
    public var kind: AnnotationKind {
        switch shape {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .text: .text
        case .highlight: .highlighter
        case .redact: .redact
        case .counter: .counter
        case .pen: .pen
        }
    }
}
