public protocol CaptureEngine: Sendable {
    /// Runs one capture. Returns nil when the user cancels (Esc).
    func capture(_ mode: CaptureMode, options: CaptureOptions) async throws -> CaptureResult?
}
