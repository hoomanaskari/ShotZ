import os
import Foundation
import ShotzCore

/// History: JSON index plus the private captures folder under Application Support.
/// TODO(engineer A): export path / edited flags in the index, daily pruning.
public actor FileHistoryStore: HistoryStore {
    private let paths: ShotzPaths
    private var entries: [CaptureResult]?
    private let log = ShotzLog.logger("History")

    public init(paths: ShotzPaths = .default) {
        self.paths = paths
    }

    public func add(_ capture: CaptureResult) async {
        var list = loaded()
        list.removeAll { $0.id == capture.id }
        list.insert(capture, at: 0)
        entries = list
        persist()
    }

    /// Newest first.
    public func recent(limit: Int) async -> [CaptureResult] {
        Array(loaded().prefix(max(limit, 0)))
    }

    public func entry(id: CaptureResult.ID) -> CaptureResult? {
        loaded().first { $0.id == id }
    }

    public func remove(id: CaptureResult.ID, deleteFile: Bool) async {
        var list = loaded()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let entry = list.remove(at: index)
        entries = list
        persist()
        if deleteFile { deleteFiles(of: entry) }
    }

    /// Removes entries (and their files) older than `interval` seconds.
    public func prune(olderThan interval: TimeInterval, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-interval)
        let list = loaded()
        let (keep, drop) = (list.filter { $0.createdAt >= cutoff }, list.filter { $0.createdAt < cutoff })
        guard !drop.isEmpty else { return }
        entries = keep
        persist()
        drop.forEach(deleteFiles)
        log.info("Pruned \(drop.count) history entries")
    }

    public nonisolated func documentURL(for id: CaptureResult.ID) -> URL {
        paths.documents.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    // MARK: Storage

    private func loaded() -> [CaptureResult] {
        if let entries { return entries }
        let url = paths.historyIndex
        var list: [CaptureResult] = []
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                list = try decoder.decode([CaptureResult].self, from: Data(contentsOf: url))
            } catch {
                log.error("History index unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            }
        }
        entries = list
        return list
    }

    private func persist() {
        do {
            try paths.createDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries ?? []).write(to: paths.historyIndex, options: .atomic)
        } catch {
            log.error("Saving history index failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteFiles(of entry: CaptureResult) {
        let fm = FileManager.default
        for url in [entry.fileURL, documentURL(for: entry.id)] where fm.fileExists(atPath: url.path(percentEncoded: false)) {
            do { try fm.removeItem(at: url) } catch {
                log.error("Deleting \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
