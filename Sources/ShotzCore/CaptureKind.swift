/// What a finished capture turned out to be.
public enum CaptureKind: String, Codable, Sendable, Hashable {
    case area, window, fullscreen
}
