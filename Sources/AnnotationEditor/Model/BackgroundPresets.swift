import AnnotationKit
import Foundation
import ShotzCore

/// The user's named background presets and the last-used background.
/// Keys: `editor.background.last`, `editor.background.presets`.
@MainActor final class BackgroundPresets {
    struct Named: Codable, Equatable {
        var name: String
        var style: BackgroundStyle
    }

    static let lastKey = "editor.background.last"
    static let presetsKey = "editor.background.presets"

    private let defaults: UserDefaults
    private let log = ShotzLog.logger("AnnotationEditor")

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// AnnotationKit's 12 built-in gradients.
    static var gradients: [BackgroundStyle.GradientFill] { GradientPreset.all.map(\.fill) }

    static var defaultStyle: BackgroundStyle {
        BackgroundStyle(fill: .gradient(gradients[1]))
    }

    var last: BackgroundStyle {
        get { decode(BackgroundStyle.self, Self.lastKey) ?? Self.defaultStyle }
        set { encode(newValue, Self.lastKey) }
    }

    var saved: [Named] {
        get { decode([Named].self, Self.presetsKey) ?? [] }
        set { encode(newValue, Self.presetsKey) }
    }

    /// Saves (or replaces, by name) a preset.
    func save(_ style: BackgroundStyle, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = saved.filter { $0.name != trimmed }
        all.append(Named(name: trimmed, style: style))
        saved = all
    }

    func delete(name: String) {
        saved = saved.filter { $0.name != name }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            log.error("Ignoring unreadable \(key, privacy: .public): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        do { defaults.set(try JSONEncoder().encode(value), forKey: key) } catch {
            log.error("Cannot store \(key, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }
}
