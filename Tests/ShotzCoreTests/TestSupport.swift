import Foundation

/// A fresh temp directory per call, removed by the caller if desired.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ShotzTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
