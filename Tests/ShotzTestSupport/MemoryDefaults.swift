import Foundation

/// Preferences for tests that live only in memory: nothing reaches cfprefsd, so a test run leaves
/// no `<suite>.plist` in ~/Library/Preferences. (A real `UserDefaults(suiteName:)` suite keeps its
/// plist even after `removePersistentDomain` and deleting the file: cfprefsd writes it again.)
///
/// Every typed getter (`bool`, `string`, `data`, `integer`, `url`…) goes through `object(forKey:)`,
/// so code under test sees ordinary UserDefaults behaviour. Use one instance per test.
public final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var store: [String: Any] = [:]
    private let lock = NSLock()

    public init() {
        // The base object is only a shell: every read and write below is overridden.
        super.init(suiteName: nil)!
    }

    public override func object(forKey key: String) -> Any? { lock.withLock { store[key] } }

    public override func set(_ value: Any?, forKey key: String) {
        lock.withLock { store[key] = value }
    }

    public override func removeObject(forKey key: String) { lock.withLock { store[key] = nil } }

    public override func dictionaryRepresentation() -> [String: Any] { lock.withLock { store } }

    /// The in-memory store stands in for this suite's persistent domain, whatever the name.
    public override func persistentDomain(forName domainName: String) -> [String: Any]? {
        lock.withLock { store.isEmpty ? nil : store }
    }

    public override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        lock.withLock { store = domain }
    }

    public override func removePersistentDomain(forName domainName: String) { lock.withLock { store = [:] } }

    public override func synchronize() -> Bool { true }
}

/// A folder under the temp dir that removes itself when the value goes away.
public final class TemporaryFolder: @unchecked Sendable {
    public let url: URL

    public init(_ label: String = "Tests") {
        url = FileManager.default.temporaryDirectory
            .appending(path: "ShotzTests-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
