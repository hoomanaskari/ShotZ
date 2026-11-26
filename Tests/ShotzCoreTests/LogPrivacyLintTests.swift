import Foundation
import Testing

/// Lint over Sources/: a log interpolation marked `privacy: .public` must not carry a file name,
/// path, URL, user-visible capture name or error description (those can contain paths). A heuristic
/// on the expression text, so it catches the usual shapes, not every possible one; anything it
/// doesn't recognise relies on review. The two allowed exceptions are ShotZ's own folder names.
struct LogPrivacyLintTests {
    static let pathLike = ["path(", ".path", "lastPathComponent", "localizedDescription", "describing: error",
                           "displayName", "url", "URL", "stderr", "args.joined", "fileURL", "folder", "directory"]
    /// Expressions that look path-like but name ShotZ's own folders (no user data).
    static let allowed: Set<String> = [
        "dir.lastPathComponent",              // FileHistoryStore: "Captures" or "Documents"
        "self.paths.root.lastPathComponent",  // AppCoordinator: the test-run folder, named by bundle id
        "variant.displayName",                // "ShotZ" or "ShotZ Dev"
        #"renderedImageURL == nil ? "original" : "annotated""#,   // a state word, not the URL
    ]

    @Test func noPathLikeValueIsLoggedPublicly() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let interpolation = try Regex(#"\\\(([^\\]*?), privacy: \.public\)"#)
        var checked = 0
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (i, line) in lines.enumerated() where line.contains("privacy: .public") {
                for match in line.matches(of: interpolation) {
                    checked += 1
                    let expr = String(match.output[1].substring ?? "").trimmingCharacters(in: .whitespaces)
                    guard !Self.allowed.contains(expr) else { continue }
                    let hit = Self.pathLike.first { expr.contains($0) }
                    #expect(hit == nil, "\(file.lastPathComponent):\(i + 1) logs `\(expr)` publicly")
                }
            }
        }
        #expect(checked > 20)   // the scan really ran over the log calls
    }
}
