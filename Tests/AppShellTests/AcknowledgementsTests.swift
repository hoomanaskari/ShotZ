import Foundation
import Testing
@testable import AppShell

/// Settings ▸ Advanced ▸ Acknowledgements reads the licences bundle.sh copies into the app.
@MainActor
struct AcknowledgementsTests {
    func bundle(with files: [String: String]) throws -> (Bundle, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShotzAckTests-\(UUID().uuidString).bundle", directoryHint: .isDirectory)
        let resources = dir.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("<plist version=\"1.0\"><dict/></plist>".utf8).write(to: dir.appending(path: "Contents/Info.plist"))
        for (name, text) in files { try Data(text.utf8).write(to: resources.appending(path: name)) }
        return (try #require(Bundle(url: dir)), dir)
    }

    @Test func showsShotZsLicenceThenTheThirdPartyNotices() throws {
        let (bundle, dir) = try bundle(with: ["LICENSE": "MIT License\nShotZ", "THIRD-PARTY-NOTICES": "Phosphor Icons\nSparkle"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = AcknowledgementsWindowController.text(bundle: bundle)
        let licence = try #require(text.range(of: "MIT License"))
        let notices = try #require(text.range(of: "Sparkle"))
        #expect(licence.lowerBound < notices.lowerBound)
        #expect(text.contains("Phosphor Icons"))
    }

    @Test func saysSoWhenAFileIsMissing() throws {
        let (bundle, dir) = try bundle(with: ["LICENSE": "MIT License"])
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AcknowledgementsWindowController.text(bundle: bundle).contains("THIRD-PARTY-NOTICES is not included in this build."))
    }

    /// The repository copies bundle.sh ships are present and not empty.
    @Test func repositoryLicencesExist() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["LICENSE", "THIRD-PARTY-NOTICES"] {
            let data = try Data(contentsOf: root.appending(path: name))
            #expect(!data.isEmpty, "\(name) is empty")
        }
    }
}
