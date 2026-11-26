/// How much work `AnnotationRenderer.draw` may do.
public enum RenderQuality: Sendable, Equatable {
    /// Exact output (export, settled editor layers). Redactions are computed at full
    /// resolution and cached in the `BaseImageProvider`.
    case final
    /// Cheap approximation for live interaction (dragging/resizing a redaction): uses the
    /// provider's downsampled preview image and caches nothing.
    case preview
}
