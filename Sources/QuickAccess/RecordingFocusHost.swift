/// A `KeyFocusHost` that only counts calls. Used by unit tests and by the
/// in-process self-test, so neither ever takes real keyboard focus.
@MainActor final class RecordingFocusHost: KeyFocusHost {
    private(set) var takes = 0
    private(set) var releases = 0
    var holdsKey: Bool { takes > releases }

    func takeKey() { takes += 1 }
    func relinquishKey() { releases += 1 }
}
