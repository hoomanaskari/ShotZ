public enum CaptureError: Error, Sendable, Equatable {
    case permissionDenied
    case busy
    case failed(String)
}
