import Foundation
import Testing
@testable import ShotzCore

struct FileNamingTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    var date: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 10, minute: 42, second: 7)) ?? .distantPast
    }

    @Test func defaultPattern() {
        #expect(FileNaming.format(FileNaming.defaultPattern, date: date, calendar: calendar) == "Shotz 2026-11-26 at 10.42.07")
    }

    @Test func otherSpecifiers() {
        #expect(FileNaming.format("%y%m%d-%H%M%S 100%% %Q", date: date, calendar: calendar) == "261126-104207 100% %Q")
        #expect(FileNaming.format("trailing %", date: date, calendar: calendar) == "trailing %")
    }

    @Test func sanitizesSeparators() {
        #expect(FileNaming.sanitize("a/b:c") == "a-b.c")
        #expect(FileNaming.sanitize("   ") == "Shotz")
    }

    @Test func candidates() {
        #expect(FileNaming.candidate(base: "Shot", ext: "png", attempt: 1) == "Shot.png")
        #expect(FileNaming.candidate(base: "Shot", ext: "png", attempt: 3) == "Shot 3.png")
        #expect(FileNaming.candidate(base: "Shot", ext: "", attempt: 2) == "Shot 2")
    }

    @Test func uniqueURLSkipsExisting() {
        let dir = URL(filePath: "/tmp/x", directoryHint: .isDirectory)
        let taken: Set<String> = ["Shot.png", "Shot 2.png"]
        let url = FileNaming.uniqueURL(in: dir, base: "Shot", ext: "png") { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Shot 3.png")
    }

    @Test func uniqueURLOnDisk() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = FileNaming.uniqueURL(in: dir, base: "A", ext: "png")
        try Data().write(to: first)
        let second = FileNaming.uniqueURL(in: dir, base: "A", ext: "png")
        #expect(first.lastPathComponent == "A.png")
        #expect(second.lastPathComponent == "A 2.png")
    }
}
