import os
import Foundation
import ImageIO
import ShotzCore

/// History (SPEC §6): a versioned JSON index plus the private captures folder
/// under Application Support.
///
/// - Every mutation is written atomically before the call returns. The actor
///   has no suspension points inside a mutation, so rapid concurrent `add`s
///   are serialised and none is lost.
/// - A corrupt index is moved aside and the index is rebuilt from the PNGs in
///   the captures folder, so captures are never orphaned by a bad file.
/// - Entries whose PNG has gone missing are skipped when read and dropped on
///   the next `prune`.
public actor FileHistoryStore: HistoryStore {
    private let paths: ShotzPaths
    private var entries: [HistoryEntry]?   // newest first; nil until loaded
    private let log = ShotzLog.logger("History")

    public init(paths: ShotzPaths = .default) {
        self.paths = paths
    }

    // MARK: HistoryStore

    public func add(_ capture: CaptureResult) async {
        var list = loaded()
        let previous = list.first { $0.id == capture.id }
        list.removeAll { $0.id == capture.id }
        list.insert(HistoryEntry(capture: capture, exportURL: previous?.exportURL), at: 0)
        list.sort { $0.capture.createdAt > $1.capture.createdAt }
        entries = list
        persist()
    }

    /// Newest first, skipping entries whose image file no longer exists.
    public func recent(limit: Int) async -> [CaptureResult] {
        recentEntries(limit: limit).map(\.capture)
    }

    public func remove(id: CaptureResult.ID, deleteFile: Bool) async {
        var list = loaded()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let entry = list.remove(at: index)
        entries = list
        persist()
        if deleteFile { deleteFiles(of: entry.capture) }
    }

    public nonisolated func documentURL(for id: CaptureResult.ID) -> URL {
        paths.documents.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    // MARK: Queries

    public func recentEntries(limit: Int) -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        var out: [HistoryEntry] = []
        for entry in loaded() where Self.exists(entry.capture.fileURL) {
            out.append(entry)
            if out.count == limit { break }
        }
        return out
    }

    public func entry(id: CaptureResult.ID) -> HistoryEntry? {
        loaded().first { $0.id == id }
    }

    public var count: Int { loaded().count }

    /// True when the editor has written an editable document for this capture.
    public nonisolated func hasDocument(for id: CaptureResult.ID) -> Bool {
        Self.exists(documentURL(for: id))
    }

    // MARK: Mutations

    /// Records the latest export of a capture (Save, auto-save).
    public func markExported(id: CaptureResult.ID, to url: URL) {
        var list = loaded()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].exportURL = url
        entries = list
        persist()
    }

    /// Applies the retention setting; `.forever` only drops missing files.
    @discardableResult
    public func prune(retention: HistoryRetention, now: Date = Date()) -> Int {
        prune(olderThan: retention.interval, now: now)
    }

    /// Removes entries (and their files) older than `interval` seconds, and
    /// entries whose image file is missing. Returns how many were removed.
    @discardableResult
    public func prune(olderThan interval: TimeInterval?, now: Date = Date()) -> Int {
        let cutoff = interval.map { now.addingTimeInterval(-$0) }
        let list = loaded()
        var keep: [HistoryEntry] = []
        var expired: [HistoryEntry] = []
        var missing = 0
        for entry in list {
            if let cutoff, entry.capture.createdAt < cutoff {
                expired.append(entry)
            } else if !Self.exists(entry.capture.fileURL) {
                missing += 1
                // The image is gone; its editable document is useless too.
                deleteDocument(of: entry.capture.id)
            } else {
                keep.append(entry)
            }
        }
        guard keep.count != list.count else { return 0 }
        entries = keep
        persist()
        expired.forEach { deleteFiles(of: $0.capture) }
        log.info("Pruned \(expired.count) expired and \(missing) missing history entries")
        return expired.count + missing
    }

    /// Clear history: removes every entry and every file in the captures and
    /// documents folders (including files the index did not know about).
    public func clear() {
        entries = []
        persist()
        let fm = FileManager.default
        for dir in [paths.captures, paths.documents] {
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            } catch {
                log.error("Listing \(dir.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            for item in items { remove(item) }
        }
        log.info("History cleared")
    }

    // MARK: Storage

    private func loaded() -> [HistoryEntry] {
        if let entries { return entries }
        let list = readIndex()
        entries = list
        return list
    }

    private func readIndex() -> [HistoryEntry] {
        let url = paths.historyIndex
        guard Self.exists(url) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("History index unreadable: \(error.localizedDescription, privacy: .public)")
            return recoverFromCorruptIndex()
        }
        let decoder = HistoryDates.decoder()
        if let file = try? decoder.decode(HistoryIndexFile.self, from: data) {
            return file.entries.sorted { $0.capture.createdAt > $1.capture.createdAt }
        }
        // Foundation-era index: a bare array of captures.
        if let legacy = try? decoder.decode([Lenient<CaptureResult>].self, from: data) {
            log.info("Migrating legacy history index")
            return legacy.compactMap(\.value).map { HistoryEntry(capture: $0) }
                .sorted { $0.capture.createdAt > $1.capture.createdAt }
        }
        return recoverFromCorruptIndex()
    }

    /// Moves the bad index aside and rebuilds entries from the captures folder.
    private func recoverFromCorruptIndex() -> [HistoryEntry] {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = paths.root.appending(path: "history.corrupt-\(stamp).json", directoryHint: .notDirectory)
        do {
            try fm.moveItem(at: paths.historyIndex, to: aside)
        } catch {
            log.error("Could not move corrupt index aside: \(error.localizedDescription, privacy: .public)")
        }
        let rebuilt = Self.entriesFromCapturesFolder(paths.captures)
        log.error("History index corrupt; rebuilt \(rebuilt.count) entries from the captures folder")
        entries = rebuilt
        persist()
        return rebuilt
    }

    static func entriesFromCapturesFolder(_ folder: URL) -> [HistoryEntry] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        } catch {
            return []
        }
        return files.compactMap { url -> HistoryEntry? in
            guard ["png", "jpg", "jpeg", "heic", "tiff"].contains(url.pathExtension.lowercased()),
                  let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            let dpi = props[kCGImagePropertyDPIWidth] as? Double ?? 72
            let created = (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? Date()
            let capture = CaptureResult(
                fileURL: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                kind: .area,
                pixelSize: CGSize(width: width, height: height),
                scale: max(1, (dpi / 72).rounded()),
                displayID: 0,
                createdAt: created
            )
            return HistoryEntry(capture: capture)
        }
        .sorted { $0.capture.createdAt > $1.capture.createdAt }
    }

    private func persist() {
        do {
            try paths.createDirectories()
            let encoder = HistoryDates.encoder()
            let data = try encoder.encode(HistoryIndexFile(entries: entries ?? []))
            try data.write(to: paths.historyIndex, options: .atomic)
        } catch {
            log.error("Saving history index failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteFiles(of capture: CaptureResult) {
        // Only ever delete inside Shotz's own folders.
        if capture.fileURL.standardizedFileURL.path(percentEncoded: false)
            .hasPrefix(paths.captures.standardizedFileURL.path(percentEncoded: false)) {
            remove(capture.fileURL)
        } else {
            log.notice("Not deleting \(capture.fileURL.lastPathComponent, privacy: .public): outside the captures folder")
        }
        deleteDocument(of: capture.id)
    }

    private func deleteDocument(of id: CaptureResult.ID) {
        remove(documentURL(for: id))
    }

    private func remove(_ url: URL) {
        guard Self.exists(url) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            log.error("Deleting \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
