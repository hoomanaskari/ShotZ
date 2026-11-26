import AnnotationKit
import Foundation
import ShotzCore

/// Built-in gradients (Shotz's own) and the user's named background presets.
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

    static let gradients: [BackgroundStyle.GradientFill] = {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> RGBAColor { RGBAColor(red: r, green: g, blue: b) }
        return [
            .init(from: c(0.98, 0.76, 0.55), to: c(0.93, 0.45, 0.55), angle: 135),
            .init(from: c(0.30, 0.78, 0.85), to: c(0.20, 0.40, 0.85), angle: 135),
            .init(from: c(0.62, 0.88, 0.48), to: c(0.18, 0.62, 0.52), angle: 135),
            .init(from: c(0.42, 0.30, 0.80), to: c(0.90, 0.42, 0.62), angle: 45),
            .init(from: c(0.99, 0.62, 0.25), to: c(0.86, 0.22, 0.25), angle: 90),
            .init(from: c(0.86, 0.93, 0.98), to: c(0.62, 0.74, 0.92), angle: 90),
            .init(from: c(0.36, 0.40, 0.47), to: c(0.16, 0.18, 0.22), angle: 90),
            .init(from: c(0.99, 0.90, 0.40), to: c(0.98, 0.60, 0.30), angle: 135),
            .init(from: c(0.93, 0.66, 0.92), to: c(0.60, 0.45, 0.92), angle: 135),
            .init(from: c(0.20, 0.42, 0.30), to: c(0.08, 0.20, 0.18), angle: 135),
            .init(from: c(0.96, 0.90, 0.80), to: c(0.84, 0.74, 0.62), angle: 90),
            .init(from: c(0.12, 0.16, 0.36), to: c(0.36, 0.18, 0.48), angle: 45),
        ]
    }()

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
            log.error("Ignoring unreadable \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        do { defaults.set(try JSONEncoder().encode(value), forKey: key) } catch {
            log.error("Cannot store \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
