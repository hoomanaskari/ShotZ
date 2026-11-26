import Foundation

/// The settings that shape an export, snapshotted per call.
public struct ExportConfiguration: Sendable, Equatable {
    public var exportFolder: URL
    public var format: ImageFormat
    /// 0…1, used for JPEG and HEIC.
    public var quality: Double
    public var retinaScale: RetinaScale

    public init(
        exportFolder: URL = ShotzPaths.defaultExportFolder,
        format: ImageFormat = .png,
        quality: Double = 0.9,
        retinaScale: RetinaScale = .native
    ) {
        self.exportFolder = exportFolder
        self.format = format
        self.quality = quality
        self.retinaScale = retinaScale
    }

    /// Reads the current values straight from `defaults` (thread-safe), using
    /// the same keys and defaults as `SettingsStore`.
    public static func current(defaults: UserDefaults = DevProfile.defaults) -> ExportConfiguration {
        let folder = defaults.string(forKey: SettingsKey.exportFolder).flatMap { $0.isEmpty ? nil : $0 }
        return ExportConfiguration(
            exportFolder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? ShotzPaths.defaultExportFolder,
            format: defaults.string(forKey: SettingsKey.exportFormat).flatMap(ImageFormat.init(rawValue:)) ?? .png,
            quality: 0.9,
            retinaScale: defaults.string(forKey: SettingsKey.retinaScale).flatMap(RetinaScale.init(rawValue:)) ?? .native
        )
    }
}
