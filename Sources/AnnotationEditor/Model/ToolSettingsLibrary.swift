import Foundation
import ShotzCore

/// Last-used options per tool, remembered across launches (SPEC §5.2).
/// Shared by all editor windows. Keys: `editor.tool.<kind>`, `editor.lastTool`.
@MainActor final class ToolSettingsLibrary {
    private let defaults: UserDefaults
    private var cache: [ToolKind: ToolSettings] = [:]
    private let log = ShotzLog.logger("AnnotationEditor")

    static let lastToolKey = "editor.lastTool"
    static func key(for kind: ToolKind) -> String { "editor.tool.\(kind.rawValue)" }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func settings(for kind: ToolKind) -> ToolSettings {
        if let cached = cache[kind] { return cached }
        var value = ToolSettings.defaults(for: kind)
        if let data = defaults.data(forKey: Self.key(for: kind)) {
            do {
                value = try JSONDecoder().decode(ToolSettings.self, from: data)
            } catch {
                log.error("Ignoring unreadable tool settings for \(kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        cache[kind] = value
        return value
    }

    func set(_ value: ToolSettings, for kind: ToolKind) {
        guard cache[kind] != value else { return }
        cache[kind] = value
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: Self.key(for: kind))
        } catch {
            log.error("Cannot store tool settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ kind: ToolKind, _ change: (inout ToolSettings) -> Void) {
        var s = settings(for: kind)
        change(&s)
        set(s, for: kind)
    }

    var lastTool: ToolKind {
        get { defaults.string(forKey: Self.lastToolKey).flatMap(ToolKind.init(rawValue:)) ?? .arrow }
        set { defaults.set(newValue.rawValue, forKey: Self.lastToolKey) }
    }
}
