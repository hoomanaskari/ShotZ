import Darwin
import Foundation
import Testing
@testable import AnnotationKit
import ShotzCore

struct AnnotationDocumentPermissionTests {
    @Test func savedDocumentsAreOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShotzDocPermTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "doc.json")
        let document = AnnotationDocument(baseImageURL: dir.appending(path: "a.png"), pixelSize: CGSize(width: 4, height: 3), scale: 1)
        try document.save(to: url)
        #expect(PrivateStorage.mode(of: url) == 0o600)
        try document.save(to: url)   // atomic overwrite keeps it
        #expect(PrivateStorage.mode(of: url) == 0o600)
    }
}
